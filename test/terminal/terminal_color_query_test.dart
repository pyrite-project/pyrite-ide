import 'package:flutter_test/flutter_test.dart';
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
}
