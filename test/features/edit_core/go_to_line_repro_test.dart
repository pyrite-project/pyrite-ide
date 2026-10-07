import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/editor/code_forge_controller.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/features/edit_core/main.dart';

/// Drives the real Ctrl+G flow - shortcut, dialog, submit, scroll jump -
/// through the app's [EditCore] subtree, and fails on ANY framework error
/// raised while the dialog tears down.
///
/// The bug this pins down: `showDialog` completes the moment the route is
/// popped, before the exit animation and unmount. Disposing the caller's
/// `TextEditingController` at that point disposes one the dialog's `TextField`
/// is still listening to, which throws *inside* the route's unmount. The
/// framework then reports that unmount as a second, unrelated-looking
/// assertion from `InheritedElement.debugDeactivated`
/// ("'_dependents.isEmpty': is not true"). So this asserts on the whole error
/// list, not on that one string - the underlying
/// "TextEditingController was used after being disposed" is the real signal.
void main() {
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // Rust runtime unavailable; the test cannot run.
    }
  });

  testWidgets('Ctrl+G jumps to a line without tearing the dialog down dirty', (
    tester,
  ) async {
    bool rustReady;
    try {
      final probe = PyriteCodeForgeController();
      probe.dispose();
      rustReady = true;
    } catch (_) {
      rustReady = false;
    }
    // The engine silently no-ops without the Rust runtime, which would make
    // this test vacuously pass.
    expect(rustReady, isTrue, reason: 'code_forge Rust runtime must load');

    final dir = Directory.systemTemp.createTempSync('pyrite_gotoline');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}main.py')
      ..writeAsStringSync(List.generate(400, (i) => 'line $i').join('\n'));

    final controller = PyriteCodeForgeController();
    addTearDown(controller.dispose);
    controller.text = file.readAsStringSync();

    const targetLine = 380;
    final errors = <FlutterErrorDetails>[];
    var dialogOpened = false;
    var dialogClosed = false;
    double? pixelsAfterJump;

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [useLsp.overrideWith((ref) => false)],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => Scaffold(
                    body: EditCore(file: file, editorController: controller),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      controller.openedFile = file.path;
      // Assigning openedFile kicks off real async IO (git/file reads) that a
      // fake-async zone would hang on forever.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();

      final prevOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
        prevOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = prevOnError);

      controller.focusNode?.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      dialogOpened = find.text('跳转到行').evaluate().isNotEmpty;
      expect(dialogOpened, isTrue, reason: 'Ctrl+G must open the dialog');

      await tester.enterText(find.byType(TextField), '$targetLine');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Let the engine's 300ms centering animation run to completion, and the
      // dialog's exit animation finish on top of it. The highlight flash in
      // the scroll's .then callback needs the widget still attached.
      //
      // The real delay lets the engine's real Future.delayed complete, while
      // the pump advances the *fake* animation clock - a bare pump() inside
      // runAsync leaves every animation frozen on its first frame, so the
      // dialog would look stuck forever.
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Checked only after the exit animation: the route stops being visible
      // gradually, and an early check would pass even if the dialog were
      // stuck.
      dialogClosed = find.text('跳转到行').evaluate().isEmpty;

      pixelsAfterJump = tester
          .state<TwoDimensionalScrollableState>(
            find.byType(TwoDimensionalScrollable),
          )
          .verticalScrollable
          .position
          .pixels;
    });

    expect(dialogClosed, isTrue, reason: 'submitting must close the dialog');

    // The jump is the point of the shortcut: line 380 of 400 has to be
    // scrolled into view, not left at the top of the file.
    expect(
      pixelsAfterJump,
      isNotNull,
      reason: 'the editor viewport must exist after the jump',
    );
    expect(
      pixelsAfterJump,
      greaterThan(0),
      reason: 'jumping to line $targetLine must scroll away from the top',
    );

    // The caret must land on the requested line.
    expect(
      controller.getLineAtOffset(controller.selection.extentOffset),
      targetLine - 1,
      reason: 'the caret must end up on the requested line',
    );

    expect(
      errors.map((d) => d.exceptionAsString()).toList(),
      isEmpty,
      reason:
          'the dialog must tear down without framework errors. A '
          "'TextEditingController was used after being disposed' here means "
          'the controller outlived the widget listening to it; an '
          "'_dependents.isEmpty' assert is the same failure surfacing late.\n"
          '${errors.map((d) => d.exceptionAsString()).join('\n---\n')}',
    );
  });
}
