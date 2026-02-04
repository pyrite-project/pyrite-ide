import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/pylsp/protocol.dart';

void main() {
  test('encodeLspMessage sets Content-Length to UTF-8 byte length', () {
    final message = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'textDocument/didChange',
      'params': {
        'text': '中文字符 mixed ASCII',
      },
    };

    final bytes = encodeLspMessage(message);

    const delimiter = '\r\n\r\n';
    final delimiterBytes = ascii.encode(delimiter);
    final headerEnd = _indexOfSubsequence(bytes, delimiterBytes);
    expect(headerEnd, isNot(-1));

    final header = ascii.decode(bytes.sublist(0, headerEnd));
    final match = RegExp(r'Content-Length: (\d+)').firstMatch(header);
    expect(match, isNotNull);

    final contentLength = int.parse(match!.group(1)!);
    final bodyBytes = bytes.sublist(headerEnd + delimiterBytes.length);

    expect(contentLength, bodyBytes.length);

    final json = jsonEncode(message);
    expect(utf8.decode(bodyBytes), json);

    if (json.runes.any((rune) => rune > 0x7f)) {
      expect(contentLength, isNot(json.length));
    }
  });
}

int _indexOfSubsequence(List<int> list, List<int> subsequence) {
  for (var i = 0; i <= list.length - subsequence.length; i++) {
    var found = true;
    for (var j = 0; j < subsequence.length; j++) {
      if (list[i + j] != subsequence[j]) {
        found = false;
        break;
      }
    }
    if (found) return i;
  }
  return -1;
}

