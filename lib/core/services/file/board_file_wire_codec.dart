import 'dart:convert';
import 'dart:typed_data';

/// Encodes board file text for ASCII-only raw REPL source and JSON payloads.
String encodeBoardFileText(String value) => base64.encode(utf8.encode(value));

String decodeBoardFileText(String value) {
  return utf8.decode(base64.decode(value));
}

String encodeBoardFileBytes(List<int> value) => base64.encode(value);

Uint8List decodeBoardFileBytes(String value) => base64.decode(value);

String boardFileTextExpression(String value) {
  return '_decode_text(${jsonEncode(encodeBoardFileText(value))})';
}
