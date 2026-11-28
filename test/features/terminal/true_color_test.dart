import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('xterm true color', () {
    test('stores semicolon and colon RGB colors', () {
      final terminal = Terminal();

      terminal.write('\x1b[38;2;12;34;56;48:2::78:90:123mX');

      final line = terminal.buffer.lines[0];
      expect(line.getForeground(0) & CellColor.typeMask, CellColor.rgb);
      expect(line.getForeground(0) & CellColor.valueMask, 0x0c2238);
      expect(line.getBackground(0) & CellColor.typeMask, CellColor.rgb);
      expect(line.getBackground(0) & CellColor.valueMask, 0x4e5a7b);
    });

    test('ignores malformed extended colors without throwing', () {
      final terminal = Terminal();

      expect(
        () => terminal.write(
          '\x1b[38m\x1b[48;2;1m\x1b[38;2;256;0;0m'
          '\x1b[48:2::0:0:999mX',
        ),
        returnsNormally,
      );

      final line = terminal.buffer.lines[0];
      expect(line.getForeground(0) & CellColor.typeMask, CellColor.normal);
      expect(line.getBackground(0) & CellColor.typeMask, CellColor.normal);
    });

    test('resets RGB colors', () {
      final terminal = Terminal();

      terminal.write(
        '\x1b[38;2;12;34;56;48;2;78;90;123mX'
        '\x1b[39mY\x1b[49mZ',
      );

      final line = terminal.buffer.lines[0];
      expect(line.getForeground(1) & CellColor.typeMask, CellColor.normal);
      expect(line.getBackground(1) & CellColor.typeMask, CellColor.rgb);
      expect(line.getForeground(2) & CellColor.typeMask, CellColor.normal);
      expect(line.getBackground(2) & CellColor.typeMask, CellColor.normal);
    });
  });
}
