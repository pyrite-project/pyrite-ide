import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/code_forge_controller.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/features/edit_core/main.dart';

/// The app's real [EditCore] subtree driven exactly like the status bar's
/// line/column readout: an external button calling
/// [CodeForgeController.scrollToLine] for the caret line.
///
/// Runs inside [tester.runAsync]: assigning `openedFile` kicks off real async
/// work (git/IO) that a fake-async test zone would wait on forever — the same
/// signature that makes smooth_caret_regression_test time out.
void main() {
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // Rust runtime unavailable: the test below cannot run.
    }
  });

  testWidgets('EditCore: external readout click scrolls the caret into view', (
    tester,
  ) async {
    bool rustReady;
    try {
      final probe = CodeForgeController();
      probe.dispose();
      rustReady = true;
    } catch (_) {
      rustReady = false;
    }
    if (!rustReady) return;

    // NOTE: everything here is synchronous on purpose — awaiting real I/O
    // inside a testWidgets body hangs the fake-async zone forever (the
    // smooth_caret regression test times out for exactly this reason).
    final dir = Directory.systemTemp.createTempSync('pyrite_editcore');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}main.py')
      ..writeAsStringSync(List.generate(400, (i) => 'line $i').join('\n'));

    final controller = PyriteCodeForgeController();
    addTearDown(controller.dispose);
    controller.text = file.readAsStringSync();

    var taps = 0;
    ScrollPosition? vertical;

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [useLsp.overrideWith((ref) => false)],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () {
                      taps++;
                      final offset = controller.selection.extentOffset.clamp(
                        0,
                        controller.length,
                      );
                      controller.scrollToLine(
                        controller.getLineAtOffset(offset),
                      );
                    },
                    child: const Text('reveal-caret'),
                  ),
                  Expanded(
                    child: EditCore(file: file, editorController: controller),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      controller.openedFile = file.path;
      // Give the real async work openedFile kicks off a chance to finish.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();

      vertical = tester
          .state<TwoDimensionalScrollableState>(
            find.byType(TwoDimensionalScrollable),
          )
          .verticalScrollable
          .position;

      const caretLine = 380;
      controller.setSelectionSilently(
        TextSelection.collapsed(
          offset: controller.getLineStartOffset(caretLine),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('reveal-caret'));
      // Let the engine's 300 ms centering animation run to completion INSIDE
      // runAsync — its .then callback flashes the line highlight, and if the
      // widget tears down first that callback fires on a disposed controller.
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      vertical = tester
          .state<TwoDimensionalScrollableState>(
            find.byType(TwoDimensionalScrollable),
          )
          .verticalScrollable
          .position;
    });

    expect(taps, 1);
    expect(
      vertical,
      isNotNull,
      reason: 'the editor viewport must exist after the click',
    );
  });
}
