import 'dart:async';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/features/edit_core/lsp_location_dialog.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

/// Jumping and previewing must follow the location the user picked, not
/// whatever tab happened to be active when an open or a load did not work out.
void main() {
  group('revealLspLocation', () {
    testWidgets('an unreadable target leaves the active tab caret alone', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final active = _RecordingController('zero\none\ntwo\nthree\n');
      active.selection = const TextSelection.collapsed(offset: 1);
      _installActiveTab(container, '/work/active.py', active);

      final harness = await _pumpHarness(tester, container);
      final missing =
          '${Directory.systemTemp.path}/pyrite_missing_'
          '${DateTime.now().microsecondsSinceEpoch}.py';

      // Real file I/O, so it has to run outside the fake-async zone.
      await tester.runAsync(
        () => revealLspLocation(harness.context, harness.ref, missing, 3, 2),
      );

      expect(
        active.selection,
        const TextSelection.collapsed(offset: 1),
        reason: 'no tab exists for the target, so there is nothing to move',
      );
    });

    testWidgets('a cancelled open leaves the active tab caret alone', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          tabbedViewControllerProvider.overrideWith(_CancelledOpenNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      final active = _RecordingController('zero\none\ntwo\nthree\n');
      active.selection = const TextSelection.collapsed(offset: 1);
      _installActiveTab(container, '/work/active.py', active);

      final harness = await _pumpHarness(tester, container);

      await revealLspLocation(
        harness.context,
        harness.ref,
        '/work/target.py',
        3,
        2,
      );

      expect(active.selection, const TextSelection.collapsed(offset: 1));
    });
  });

  group('LspLocationDialog preview', () {
    testWidgets('a slow earlier selection cannot overwrite the newest one', (
      tester,
    ) async {
      final rust = await tester.runAsync(_rustReady);
      if (rust != true) return;

      // The preview editor reads the entry path from disk when it mounts, so
      // the locations need real files even though their content is loaded
      // through the injected loader below.
      final dir = Directory.systemTemp.createTempSync('lsp_preview_race');
      addTearDown(() => dir.deleteSync(recursive: true));
      final fileA = File('${dir.path}/a.py')..writeAsStringSync('a on disk\n');
      final fileB = File('${dir.path}/b.py')..writeAsStringSync('b on disk\n');

      final loadA = Completer<String?>();
      final loadB = Completer<String?>();
      final entries = [
        LspLocationEntry(
          path: fileA.path,
          line: 0,
          character: 0,
          title: 'alpha',
        ),
        LspLocationEntry(
          path: fileB.path,
          line: 1,
          character: 0,
          title: 'beta',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: LspLocationDialog(
                titleBuilder: (_) => 'Locations',
                entries: entries,
                contentLoader: (path) =>
                    path == fileA.path ? loadA.future : loadB.future,
                onOpen: (_) async {},
              ),
            ),
          ),
        ),
      );
      // The first entry is previewed on open and its load stays pending.
      await tester.pump();

      await tester.tap(find.text('beta'));
      // The row distinguishes single from double click, so the single tap is
      // only claimed once the double-click window has passed.
      await tester.pump(const Duration(milliseconds: 400));

      // The newest selection finishes first...
      loadB.complete('alpha placeholder\nbeta line\n');
      await tester.pump();
      await tester.pump();

      // ...and only then does the abandoned request come back.
      loadA.complete('alpha line\nbeta placeholder\n');
      await tester.pump();
      await tester.pump();

      final preview = tester.widget<CodeForge>(find.byType(CodeForge));
      expect(
        preview.controller!.text,
        'alpha placeholder\nbeta line\n',
        reason: 'the preview must still show the entry the user picked last',
      );
    });
  });
}

/// A controller stand-in recording exactly what a jump moves. The real
/// controller needs the Rust rope, which the navigation test does not exercise.
class _RecordingController implements CodeForgeController {
  _RecordingController(this._text);

  String _text;

  @override
  TextSelection selection = const TextSelection.collapsed(offset: 0);

  @override
  String get text => _text;

  @override
  set text(String value) => _text = value;

  @override
  int get length => _text.length;

  @override
  int getLineStartOffset(int lineIndex) {
    var offset = 0;
    final lines = _text.split('\n');
    for (var i = 0; i < lineIndex && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    return offset;
  }

  @override
  void scrollToLine(int line) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used by navigation: $invocation');
}

/// A notifier whose `openFile` ends like a cancelled binary/encoding prompt:
/// without a tab and without an error.
class _CancelledOpenNotifier extends TabbedViewControllerNotifier {
  _CancelledOpenNotifier(super.ref);

  @override
  Future<void> openFile(
    BuildContext context, {
    File? file,
    bool isBoardFile = false,
    String? boardFilePath,
    String? initialText,
    String? savedBaseline,
    bool isSaved = true,
    String? encoding,
    bool byteOrderMark = false,
    int? initialCaretOffset,
  }) async {}
}

void _installActiveTab(
  ProviderContainer container,
  String path,
  CodeForgeController controller,
) {
  final group = container.read(tabbedViewControllerProvider);
  group.addTab(
    TabData(
      text: path.split('/').last,
      value: TabDataValue(
        type: 'file',
        filePath: path,
        editorController: controller,
      ),
    ),
  );
  group.selectedIndex = group.tabs.length - 1;
}

/// Pumps a shell owning a [ProviderContainer] and captures the [WidgetRef]
/// `revealLspLocation` expects.
Future<({BuildContext context, WidgetRef ref})> _pumpHarness(
  WidgetTester tester,
  ProviderContainer container,
) async {
  late BuildContext capturedContext;
  late WidgetRef capturedRef;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              capturedContext = context;
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  return (context: capturedContext, ref: capturedRef);
}

/// The Rust editor rope is optional in local runs; skip the preview test when
/// it cannot be loaded.
Future<bool> _rustReady() async {
  try {
    await RustLib.init();
    return true;
  } catch (_) {
    return false;
  }
}
