import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduces the status bar's line/column click: a button OUTSIDE the editor
/// subtree calls [CodeForgeController.scrollToLine] for the caret line, and
/// the viewport must move so that line becomes visible.
void main() {
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // Rust runtime unavailable: the tests below cannot run.
    }
  });

  bool rustReady() {
    try {
      final probe = CodeForgeController();
      probe.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  testWidgets('clicking an external readout scrolls the caret line into view', (
    tester,
  ) async {
    if (!rustReady()) return;

    final controller = CodeForgeController();
    addTearDown(controller.dispose);
    controller.useSpaceAsTab = true;
    controller.tabSize = 4;
    final lineCount = 400;
    controller.text = List.generate(lineCount, (i) => 'line $i').join('\n');

    ScrollPosition? editorScroll;
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // Mimics the status bar's line/column button: outside the
              // editor's subtree, same instance of the controller.
              TextButton(
                onPressed: () {
                  taps++;
                  final offset = controller.selection.extentOffset.clamp(
                    0,
                    controller.length,
                  );
                  final line = controller.getLineAtOffset(offset);
                  controller.scrollToLine(line);
                },
                child: const Text('reveal-caret'),
              ),
              Expanded(child: CodeForge(controller: controller)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    // The caret blink animates forever, so pumpAndSettle would never settle;
    // fixed steps let layout and the initial fold/highlight work settle.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // The editor scrolls through a TwoDimensionalScrollable, whose vertical
    // axis carries the code viewport.
    final twoDState = tester.state<TwoDimensionalScrollableState>(
      find.byType(TwoDimensionalScrollable),
    );
    editorScroll = twoDState.verticalScrollable.position;
    expect(editorScroll.hasContentDimensions, isTrue);
    expect(editorScroll.pixels, 0.0);

    // Park the caret near the bottom of the document.
    final caretLine = lineCount - 20;
    final caretOffset = controller.getLineStartOffset(caretLine);
    controller.setSelectionSilently(
      TextSelection.collapsed(offset: caretOffset),
    );
    await tester.pump();

    await tester.tap(find.text('reveal-caret'));
    expect(taps, 1);
    // The engine centers the target line over a 300 ms animation.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      editorScroll.pixels,
      greaterThan(0.0),
      reason: 'clicking the readout must scroll the caret line into view',
    );
  });
}
