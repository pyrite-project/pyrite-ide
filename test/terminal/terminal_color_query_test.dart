import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
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

  test('desktop terminal follows OSC 11 background setters by default', () {
    final output = <String>[];
    final background = ValueNotifier<Color?>(null);
    addTearDown(background.dispose);
    final terminal = Terminal(onOutput: output.add);
    configureTerminalColorQueries(
      terminal,
      TerminalThemes.defaultTheme,
      backgroundColor: background,
    );

    terminal.write('\x1b]11;rgb:1234/5678/9abc\x07');
    expect(background.value, const Color(0xFF12569A));

    terminal.write('\x1b]11;?\x07');
    expect(output.single, '\x1b]11;rgb:1212/5656/9a9a\x1b\\');

    terminal.write('\x1b]111\x07');
    expect(background.value, isNull);
  });

  test(
    'OSC colors accept standard component widths and reject malformed data',
    () {
      expect(parseTerminalOscColor('rgb:f/0/8'), const Color(0xFFFF0088));
      expect(parseTerminalOscColor('#abc'), const Color(0xFFAABBCC));
      expect(parseTerminalOscColor('#112233445566'), const Color(0xFF113355));
      expect(parseTerminalOscColor('rgb:gg/00/00'), isNull);
      expect(parseTerminalOscColor('#12345'), isNull);
    },
  );

  test('program background changes only the copied terminal theme', () {
    final base = TerminalThemes.defaultTheme;
    final changed = terminalThemeWithBackground(base, const Color(0xFF123456));

    expect(base.background, const Color(0xFF1E1E1E));
    expect(changed.background, const Color(0xFF123456));
    expect(changed.foreground, base.foreground);
    expect(changed.red, base.red);
    expect(changed.minimumContrastRatio, base.minimumContrastRatio);
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
    expect(container.read(terminalMinimumContrast), isFalse);
    expect(theme.foreground, const Color(0xFFFFFFFF));
    expect(theme.minimumContrastRatio, 1.0);

    container.read(terminalAppearance.notifier).state =
        TerminalAppearance.custom;
    await tester.pump();

    expect(container.read(terminalCustomForeground), 0xFFFFFFFF);
    expect(theme.foreground, const Color(0xFFFFFFFF));
  });

  testWidgets('active UI theme can also provide terminal colors', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ansi = List<String>.generate(
      16,
      (index) => '#${(index + 1).toRadixString(16).padLeft(6, '0')}',
    );
    container.read(dataRegistryProvider).registerTheme('fixture', 'shared', {
      'color.primary': '#112233',
      'terminal.foreground': '#AABBCC',
      'terminal.background': '#101820',
      'terminal.ansi': ansi,
    });
    container.read(activePluginThemeId.notifier).state = 'fixture::shared';
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

    expect(theme.foreground, const Color(0xFFAABBCC));
    expect(theme.background, const Color(0xFF101820));
    expect(theme.red, const Color(0xFF000002));
    expect(theme.brightWhite, const Color(0xFF000010));
    expect(
      container
          .read(dataRegistryProvider)
          .getThemeById('fixture::shared')
          ?.colorPrimary,
      const Color(0xFF112233),
    );
  });
}
