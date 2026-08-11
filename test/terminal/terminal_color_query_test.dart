import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/features/function_page.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('desktop terminal answers OSC foreground and background queries', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);
    configureTerminalColorQueries(terminal, TerminalThemes.defaultTheme);

    terminal.write('\x1b]10;?\x07');
    terminal.write('\x1b]11;?\x1b\\');

    expect(output, [
      '\x1b]10;rgb:cccc/cccc/cccc\x1b\\',
      '\x1b]11;rgb:1e1e/1e1e/1e1e\x1b\\',
    ]);
  });

  test('desktop terminal ignores OSC color setters', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);
    configureTerminalColorQueries(terminal, TerminalThemes.defaultTheme);

    terminal.write('\x1b]10;rgb:ffff/0000/0000\x07');

    expect(output, isEmpty);
  });

  testWidgets('dark and custom defaults use a white foreground', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    late TerminalTheme theme;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              theme = buildTerminalTheme(context, ref);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(container.read(terminalLigatures), isTrue);
    expect(container.read(terminalAppearance), TerminalAppearance.dark);
    expect(container.read(terminalMinimumContrast), isTrue);
    expect(theme.foreground, const Color(0xFFFFFFFF));
    expect(theme.minimumContrastRatio, 4.5);

    container.read(terminalAppearance.notifier).state =
        TerminalAppearance.custom;
    await tester.pump();

    expect(container.read(terminalCustomForeground), 0xFFFFFFFF);
    expect(theme.foreground, const Color(0xFFFFFFFF));
  });
}
