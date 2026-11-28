import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// SGR attribute bookkeeping, checked on the cell buffer instead of on pixels.
///
/// These are the attributes that used to leak out of a single escape sequence
/// and stay on for the rest of the session: a bold run that never ended made
/// every later character bold, and an underline that could not be switched off
/// underlined the whole screen. A full-screen TUI (Claude Code, htop, ...)
/// redraws with whatever attribute is current, so one leak is visible on every
/// line.
void main() {
  /// Writes [input] and returns the attributes of the printable cells of the
  /// first line, in order.
  List<int> attributesOf(String input) {
    final terminal = Terminal();
    terminal.resize(40, 10);
    terminal.write(input);
    final line = terminal.buffer.lines[0];
    final result = <int>[];
    for (var x = 0; x < line.length; x++) {
      if (line.getCodePoint(x) == 0) break;
      result.add(line.getAttributes(x));
    }
    return result;
  }

  test('22 ends a bold run', () {
    // "Normal intensity" is how programs close a bold run; nothing sends 21.
    expect(attributesOf('\x1b[1mAB\x1b[22mCD'), [1, 1, 0, 0]);
  });

  test('22 ends a faint run', () {
    expect(attributesOf('\x1b[2mAB\x1b[22mCD'), [
      CellAttr.faint,
      CellAttr.faint,
      0,
      0,
    ]);
  });

  test('22 clears bold and faint together', () {
    expect(attributesOf('\x1b[1;2mAB\x1b[22mCD'), [
      CellAttr.bold | CellAttr.faint,
      CellAttr.bold | CellAttr.faint,
      0,
      0,
    ]);
  });

  test('24 ends an underline run', () {
    expect(attributesOf('\x1b[4mAB\x1b[24mCD'), [
      CellAttr.underline,
      CellAttr.underline,
      0,
      0,
    ]);
  });

  test('4:0 is "no underline"', () {
    // The sub-parameter form spells "underline off" as 4:0. Reading it as
    // "underline on" is what left the attribute stuck: a program that closes
    // its underline this way never sends a bare 24.
    expect(attributesOf('\x1b[4mAB\x1b[4:0mCD'), [
      CellAttr.underline,
      CellAttr.underline,
      0,
      0,
    ]);
  });

  test('4:3 is a styled underline and still underlines', () {
    expect(attributesOf('\x1b[4:3mAB\x1b[24mCD'), [
      CellAttr.underline,
      CellAttr.underline,
      0,
      0,
    ]);
  });

  test('underline colour does not turn into another attribute', () {
    // 58 takes the same arguments as 38/48. They have to be consumed with the
    // sequence, or `58;5;236` reads as "blink" and `58;2;r;g;b` as "faint".
    expect(attributesOf('\x1b[58;5;236mAB\x1b[59mCD'), [0, 0, 0, 0]);
    expect(attributesOf('\x1b[58;2;255;0;0mAB'), [0, 0]);
    expect(attributesOf('\x1b[58:2::255:0:0mAB'), [0, 0]);
  });

  test('extended colours still consume their arguments', () {
    final terminal = Terminal();
    terminal.resize(40, 10);
    terminal.write('\x1b[38;2;1;2;3mAB');
    final line = terminal.buffer.lines[0];

    expect(line.getForeground(0), CellColor.rgb | 0x010203);
    expect(line.getAttributes(0), 0);
    expect(line.getAttributes(1), 0);
  });

  test('a private-prefixed m is not SGR', () {
    // `CSI > 4 ; 1 m` is XTMODKEYS. Reading it as SGR reset the attributes and
    // set bold, so a shell that enables modifyOtherKeys on startup changed the
    // appearance of everything that followed.
    expect(attributesOf('\x1b[4mA\x1b[>4;1mB'), [
      CellAttr.underline,
      CellAttr.underline,
    ]);
  });
}
