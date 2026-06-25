import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/file/board_file_wire_codec.dart';

void main() {
  test('encodes Chinese board file text as ASCII-safe base64', () {
    const value = '/脚本/温度传感器.py';

    final encoded = encodeBoardFileText(value);
    final expression = boardFileTextExpression(value);

    expect(decodeBoardFileText(encoded), value);
    expect(encoded.runes.every((rune) => rune < 0x80), isTrue);
    expect(expression.runes.every((rune) => rune < 0x80), isTrue);
    expect(expression, startsWith('_decode_text('));
  });
}
