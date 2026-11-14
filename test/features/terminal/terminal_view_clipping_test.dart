import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('clips terminal painting to the viewport', (tester) async {
    final terminal = Terminal();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 20,
            child: TerminalView(terminal, padding: EdgeInsets.zero),
          ),
        ),
      ),
    );

    final renderView = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_TerminalView',
    );
    expect(renderView, findsOneWidget);
    expect(
      renderView,
      paints..clipRect(rect: const Rect.fromLTWH(0, 0, 120, 20)),
    );
  });

  testWidgets('ANSI clear does not reveal a partial scrollback line', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 100);
    final scrollController = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 240,
            height: 35,
            child: TerminalView(
              terminal,
              padding: EdgeInsets.zero,
              scrollController: scrollController,
            ),
          ),
        ),
      ),
    );

    for (var index = 0; index < 20; index++) {
      terminal.write('scrollback-$index\r\n');
    }
    terminal.write('\x1b[H\x1b[2J');
    await tester.pump();

    final renderView = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_TerminalView',
    );
    expect(renderView, findsOneWidget);
    expect(renderView, isNot(paints..paragraph()));
  });
}
