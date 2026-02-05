import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file.dart';
import 'package:pyrite_ide/core/services/pylsp/core.dart';
import 'package:pyrite_ide/core/services/pylsp/data.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:pyrite_ide/features/edit_core/main.dart';
import 'package:pyrite_ide/features/edit_core/lsp_span_builder.dart';
import 'package:pyrite_ide/pages/edit/welcome.dart';
import 'package:re_editor/re_editor.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:xterm/xterm.dart';

final StateProvider<Map<String, CodeLineEditingController>>
editorControllerMap = StateProvider<Map<String, CodeLineEditingController>>(
  (ref) => {},
);

Map<String, int> documentVersions = {};

final Map<String, Timer> _didChangeDebounceTimers = {};
final Map<String, String> _lastSyncedTextByPath = {};
final Map<String, int> _textLengthHintByPath = {};

final StateProvider<TabbedViewController> tabbedViewController =
    StateProvider<TabbedViewController>(
      (ref) => TabbedViewController(
        [
          TabData(
            value: {"type": "page", "id": "welcome"},
            text: "欢迎",
            content: Welcome(),
            leading: (context, status) => Padding(
              padding: EdgeInsetsGeometry.directional(
                start: 5,
                end: 10,
                top: 5,
                bottom: 5,
              ),
              child: Image.asset(
                "assets/icons/app_icon.png",
                width: 15,
                height: 15,
              ),
            ),
          ),
        ],
        onTabRemove: (tabData) {
          if (tabData.value["type"] == "file") {
            final String path = tabData.value["id"];
            final String uri = Uri.file(path).toString();

            // Dispose editor resources eagerly to avoid leaks on large files.
            ref.read(openFilesMap).remove(path);
            final controller = ref.read(editorControllerMap)[path];
            controller?.dispose();
            ref.read(editorControllerMap).remove(path);

            documentVersions.remove(path);
            _didChangeDebounceTimers.remove(path)?.cancel();
            _lastSyncedTextByPath.remove(path);
            _textLengthHintByPath.remove(path);

            // Drop diagnostics for closed documents to keep memory bounded.
            ref.read(diagnosticsByUri.notifier).state = {
              ...ref.read(diagnosticsByUri),
            }..remove(uri);
            ref.read(documentHighlightsByUri.notifier).state = {
              ...ref.read(documentHighlightsByUri),
            }..remove(uri);
            ref.read(semanticTokensByUri.notifier).state = {
              ...ref.read(semanticTokensByUri),
            }..remove(uri);

            unawaited(() async {
              try {
                final client = await PythonLspService(ref).client;
                client.sendNotification('textDocument/didClose', {
                  'textDocument': {'uri': uri},
                });
              } catch (_) {
                // Ignore: LSP may be unavailable during shutdown/init.
              }
            }());
          }
        },
      ),
    );

final Terminal terminal = Terminal();

Duration _didChangeDebounceForTextLength(int length) {
  if (length <= 50 * 1000) return const Duration(milliseconds: 250);
  if (length <= 200 * 1000) return const Duration(milliseconds: 500);
  if (length <= 1000 * 1000) return const Duration(milliseconds: 1200);
  return const Duration(milliseconds: 2000);
}

typedef _MinimalEdit = ({
  int startOffset,
  int endOffset,
  String replacementText,
});

_MinimalEdit? _computeMinimalEdit(String oldText, String newText) {
  if (identical(oldText, newText)) return null;

  final oldLength = oldText.length;
  final newLength = newText.length;
  final minLength = math.min(oldLength, newLength);

  var prefix = 0;
  while (prefix < minLength &&
      oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }

  if (prefix == oldLength && prefix == newLength) return null;

  var oldSuffix = oldLength;
  var newSuffix = newLength;
  while (oldSuffix > prefix &&
      newSuffix > prefix &&
      oldText.codeUnitAt(oldSuffix - 1) == newText.codeUnitAt(newSuffix - 1)) {
    oldSuffix--;
    newSuffix--;
  }

  return (
    startOffset: prefix,
    endOffset: oldSuffix,
    replacementText: newText.substring(prefix, newSuffix),
  );
}

typedef _RangePositions = ({
  int startLine,
  int startCharacter,
  int endLine,
  int endCharacter,
});

_RangePositions _rangePositionsForOffsets(
  String text,
  int startOffset,
  int endOffset,
) {
  var line = 0;
  var lineStart = 0;

  var startLine = 0;
  var startCharacter = 0;

  for (var i = 0; i <= endOffset; i++) {
    if (i == startOffset) {
      startLine = line;
      startCharacter = i - lineStart;
    }
    if (i == endOffset) {
      return (
        startLine: startLine,
        startCharacter: startCharacter,
        endLine: line,
        endCharacter: i - lineStart,
      );
    }
    if (text.codeUnitAt(i) == 10) {
      line++;
      lineStart = i + 1;
    }
  }

  return (
    startLine: startLine,
    startCharacter: startCharacter,
    endLine: line,
    endCharacter: endOffset - lineStart,
  );
}

List<Map<String, dynamic>> _buildIncrementalContentChanges(
  String oldText,
  String newText,
) {
  final edit = _computeMinimalEdit(oldText, newText);
  if (edit == null) return const [];

  final positions = _rangePositionsForOffsets(
    oldText,
    edit.startOffset,
    edit.endOffset,
  );

  return [
    {
      'range': {
        'start': {
          'line': positions.startLine,
          'character': positions.startCharacter,
        },
        'end': {
          'line': positions.endLine,
          'character': positions.endCharacter,
        },
      },
      'rangeLength': edit.endOffset - edit.startOffset,
      'text': edit.replacementText,
    },
  ];
}

void _scheduleDidChange({
  required String path,
  required CodeLineEditingController controller,
  required LspClient client,
}) {
  final debounceDuration = _didChangeDebounceForTextLength(
    _textLengthHintByPath[path] ?? controller.text.length,
  );

  _didChangeDebounceTimers[path]?.cancel();
  _didChangeDebounceTimers[path] = Timer(debounceDuration, () {
    _didChangeDebounceTimers.remove(path);

    final currentVersion = documentVersions[path];
    if (currentVersion == null) return;

    final oldText = _lastSyncedTextByPath[path];
    final newText = controller.text;

    if (oldText == null) {
      _lastSyncedTextByPath[path] = newText;
      _textLengthHintByPath[path] = newText.length;
      return;
    }

    if (identical(oldText, newText)) return;

    final contentChanges = client.supportsIncrementalSync
        ? _buildIncrementalContentChanges(oldText, newText)
        : [
            {'text': newText},
          ];
    if (contentChanges.isEmpty) return;

    final nextVersion = currentVersion + 1;
    documentVersions[path] = nextVersion;

    client.sendNotification("textDocument/didChange", {
      "textDocument": {
        "uri": Uri.file(path).toString(),
        "version": nextVersion,
      },
      "contentChanges": contentChanges,
    });

    _lastSyncedTextByPath[path] = newText;
    _textLengthHintByPath[path] = newText.length;
  });
}

Future<TabData> createNewFileTab(
  File file,
  WidgetRef ref,
  CodeLineEditingController editorController,
) async {
  String pattern = "\\";

  if (Platform.isWindows) {
    pattern = "\\";
  } else {
    pattern = "/";
  }

  Map<String, dynamic> value = {
    "type": "file",
    "id": file.path,
    "file": file,
    "editor_controller": editorController,
  };

  final uri = Uri.file(file.path).toString();
  ref.read(activeDiagnosticUri.notifier).state = uri;

  final client = await PythonLspService(ref).maybeClient;
  if (client != null) {
    final version = documentVersions[value["id"]] ?? 1;
    documentVersions[value["id"]] = version;

    client.sendNotification('textDocument/didOpen', {
      'textDocument': {
        'uri': uri,
        'languageId': 'python',
        'version': version,
        'text': editorController.text,
      },
    });
  }

  return TabData(
    value: value,
    text: file.path.split(pattern).last,
    content: EditCore(file: file, editorController: editorController),
  );
}

Future<CodeLineEditingController> createNewEditorController(
  File file,
  WidgetRef ref,
) async {
  final String initialText = await file.readAsString();
  final uri = Uri.file(file.path).toString();
  CodeLineEditingController controller = CodeLineEditingController(
    codeLines: initialText.codeLines,
    spanBuilder: buildLspSpanBuilder(uri: uri),
  );

  final client = await PythonLspService(ref).maybeClient;
  if (client != null) {
    documentVersions[file.path] = 1;
    _lastSyncedTextByPath[file.path] = controller.text;
    _textLengthHintByPath[file.path] = controller.text.length;

    controller.addListener(() {
      _scheduleDidChange(
        path: file.path,
        controller: controller,
        client: client,
      );
    });
  }
  return controller;
}

void onTabTap(
  TabData tab,
  TabbedViewController controller,
  int newTabIndex,
  dynamic ref,
) async {
  controller.selectedIndex = newTabIndex;
  if (tab.value["type"] == "file") {
    ref.read(activeDiagnosticUri.notifier).state =
        Uri.file(tab.value["id"]).toString();
  } else {
    ref.read(activeDiagnosticUri.notifier).state = null;
  }
}

void afterTabClose(
  int index,
  TabbedViewController controller,
  dynamic ref,
) async {
  final selectedTab = controller.selectedTab;
  if (selectedTab != null && selectedTab.value["type"] == "file") {
    ref.read(activeDiagnosticUri.notifier).state =
        Uri.file(selectedTab.value["id"]).toString();
    return;
  }

  cleanDiagnostics(ref);
}
