import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:code_forge/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for the paint-phase assertion in the smooth caret:
/// starting `caretSmoothController.forward(from: 0.0)` inside `paint` used to
/// notify its `markNeedsPaint` listener synchronously, which the framework
/// asserts against while the paint phase is running.
///
/// The Rust-backed rope needs `code_forge.dll`; when it cannot be loaded the
/// suite is skipped so CI without a built runtime stays green.
void main() {
  Future<bool> rustReady() async {
    try {
      await RustLib.init();
      return true;
    } catch (_) {
      return false;
    }
  }

  testWidgets('a caret move with smooth cursor paints without asserting', (
    tester,
  ) async {
    if (!await rustReady()) return;

    final dir = await Directory.systemTemp.createTemp('smooth_caret');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}main.py')
      ..writeAsStringSync('hello world\nsecond line\n');

    final controller = CodeForgeController();
    addTearDown(controller.dispose);
    controller.openedFile = file.path;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeForge(
            controller: controller,
            filePath: file.path,
            smoothCursor: true,
          ),
        ),
      ),
    );
    await tester.pump();
    // First paint snaps (no animation start yet).

    // Moving the caret changes the resolved target, which starts the glide
    // from inside the paint phase — the exact moment that used to throw.
    controller.text = 'hello world\nsecond line\nx';
    await tester.pump();

    // Let the glide run to completion; every tick repaints.
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(controller.text, 'hello world\nsecond line\nx');
  });
}
