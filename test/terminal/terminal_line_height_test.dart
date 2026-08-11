import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/features/function_page.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('terminal line height setting updates the rendered cell height', (
    tester,
  ) async {
    final terminal = Terminal();
    final terminalViewKey = GlobalKey<TerminalViewState>();
    late WidgetRef widgetRef;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              widgetRef = ref;
              return SizedBox(
                width: 640,
                height: 240,
                child: TerminalView(
                  terminal,
                  key: terminalViewKey,
                  textStyle: buildTerminalStyle(ref),
                ),
              );
            },
          ),
        ),
      ),
    );

    final initialCellHeight =
        terminalViewKey.currentState!.renderTerminal.cellSize.height;

    widgetRef.read(terminalLineHeight.notifier).state = 1.8;
    await tester.pump();

    final updatedCellHeight =
        terminalViewKey.currentState!.renderTerminal.cellSize.height;
    expect(updatedCellHeight, greaterThan(initialCellHeight));
    expect(buildTerminalStyle(widgetRef).height, 1.8);
  });
}
