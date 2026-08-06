import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/base_usb_serial.dart';

void main() {
  test('encodes non-ASCII REPL input while preserving ASCII controls', () {
    expect(
      encodeReplInputForDevice('print("你好")\r\n'),
      r'print("\u4f60\u597d")'
      '\r\n',
    );
    expect(encodeReplInputForDevice('😀'), r'\U0001f600');
    expect(encodeReplInputForDevice('tab\t\x03'), 'tab\t\x03');
  });
}
