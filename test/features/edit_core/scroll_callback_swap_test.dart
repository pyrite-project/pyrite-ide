import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A keyed widget swap (theme changes drive [CodeForge]'s rebuild key) creates
/// the replacement renderer BEFORE the outgoing renderer unmounts. The
/// outgoing renderer's dispose used to null the controller's scroll callback
/// unconditionally, wiping the replacement's registration — every later
/// [CodeForgeController.scrollToLine] then threw "Editor is not initialized"
/// until some future rebuild re-registered it. That is exactly what the
/// status bar's line/column readout hit in the running app.
void main() {
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // Rust runtime unavailable: the test below cannot run.
    }
  });

  testWidgets('a keyed rebuild keeps the controller scrollable', (
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

    final controller = CodeForgeController();
    addTearDown(controller.dispose);
    controller.text = List.generate(400, (i) => 'line $i').join('\n');

    Future<void> pumpWithKey(String key) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CodeForge(key: ValueKey(key), controller: controller),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.runAsync(() async {
      await pumpWithKey('initial');
      // Sanity: the freshly mounted editor drives scrolling.
      controller.setSelectionSilently(
        TextSelection.collapsed(offset: controller.getLineStartOffset(380)),
      );
      await tester.pump();
      controller.scrollToLine(380);
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }

      // Swap the key: replacement renderer registers, outgoing one unmounts.
      await pumpWithKey('rebuilt');
      // The swap must NOT have wiped the callback — this is the regression.
      controller.scrollToLine(200);
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
