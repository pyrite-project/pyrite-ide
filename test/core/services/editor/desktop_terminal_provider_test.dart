import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/desktop_terminal_provider.dart';

void main() {
  test('PTY output preserves UTF-8 characters split across chunks', () async {
    const text = 'prompt \ue0b0 \u4e2d\u6587';
    final bytes = utf8.encode(text);
    final chunks = Stream<List<int>>.fromIterable(bytes.map((byte) => [byte]));

    final decoded = await decodeTerminalOutput(chunks).join();

    expect(decoded, text);
    expect(decoded, isNot(contains('\ufffd')));
  });
}
