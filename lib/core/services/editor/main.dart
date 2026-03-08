import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:code_forge/LSP/lsp.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/file/local.dart';
import 'package:pyrite_ide/core/services/pylsp/core.dart';
import 'package:pyrite_ide/core/services/pylsp/data.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:pyrite_ide/features/edit_core/main.dart';
import 'package:pyrite_ide/features/edit_core/lsp_span_builder.dart';
import 'package:pyrite_ide/pages/edit/welcome.dart';
import 'package:re_editor/re_editor.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:xterm/xterm.dart';

final Map<String, CodeForgeController> editorControllerMap = {};

LspClient? client;

final Terminal repl = Terminal();
final TerminalController replController = TerminalController();

class TabDataValue {
  const TabDataValue({
    required this.type,
    required this.filePath,
    this.editorController,
    this.file,
  });
  final String type;
  final String filePath;
  final File? file;
  final CodeForgeController? editorController;
}

final StateProvider<TabbedViewController> tabbedViewController =
    StateProvider<TabbedViewController>(
      (ref) => TabbedViewController(
        [
          TabData(
            closable: false,
            value: TabDataValue(type: "page", filePath: "welcome"),
            text: "欢迎   ",
            content: EditorWelcome(),
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
          if (tabData.value.type == "file") {
            final String path = tabData.value.filePath;
            final String uri = Uri.file(path).toString();

            // Dispose editor resources eagerly to avoid leaks on large files.
            openFilesMap.remove(path);
            final controller = editorControllerMap[path];
            controller?.dispose();
            editorControllerMap.remove(path);
          }
        },
      ),
    );

Future<TabData> createNewFileTab(
  File file,
  WidgetRef ref,
  CodeForgeController editorController,
) async {
  if (openFilesisSavedMap[file.path] == null) {
    openFilesisSavedMap[file.path] = StateProvider<bool>((ref) => true);
  }

  String pattern = "\\";

  if (Platform.isWindows) {
    pattern = "\\";
  } else {
    pattern = "/";
  }

  TabDataValue value = TabDataValue(
    type: "file",
    filePath: file.path,
    file: file,
    editorController: editorController,
  );

  final uri = Uri.file(file.path).toString();
  ref.read(activeDiagnosticUri.notifier).state = uri;

  return TabData(
    value: value,
    text: file.path.split(pattern).last,
    content: EditCore(file: file, editorController: editorController),
    keepAlive: true,
  );
}

Future<CodeForgeController> createNewEditorController(
  File file,
  WidgetRef ref,
) async {
  String pattern = "\\";

  if (Platform.isWindows) {
    pattern = "\\";
  } else {
    pattern = "/";
  }
  final String initialText = await file.readAsString();
  final uri = Uri.file(file.path).toString().split(pattern);
  final List<String> _workspacePath = List.from(uri);
  _workspacePath.removeLast();
  final String workspacePath = uri.join(pattern);
  CodeForgeController controller = CodeForgeController(
    lspConfig: LspSocketConfig(
      workspacePath: workspacePath,
      languageId: "python",
      serverUrl: "ws://127.0.0.1:2026",
    ),
  );
  controller.text = initialText;
  controller.openedFile = file.path;
  // controller 在初始化 LSP 的时候会对 openedFile 进行非空断言
  return controller;
}

void onTabTap(
  TabData tab,
  TabbedViewController controller,
  int newTabIndex,
  dynamic ref,
) async {
  controller.selectedIndex = newTabIndex;
  if (tab.value.type == "file") {
    ref.read(activeDiagnosticUri.notifier).state = Uri.file(
      tab.value.filePath,
    ).toString();
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
  if (selectedTab != null && selectedTab.value.type == "file") {
    ref.read(activeDiagnosticUri.notifier).state = Uri.file(
      selectedTab.value.filePath,
    ).toString();
    return;
  }

  cleanDiagnostics(ref);
}

void afterFileSave() {
  final TabData nowTab = container.read(tabbedViewController).selectedTab!;
  container.read(openFilesisSavedMap[nowTab.value.filePath]!.notifier).state =
      true;
  nowTab.leading = (context, status) {
    return null;
  };
}
