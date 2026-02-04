import 'dart:convert';
import 'dart:typed_data';

Uint8List encodeLspMessage(Map<String, dynamic> message) {
  final json = jsonEncode(message);
  final jsonBytes = utf8.encode(json);
  final headerBytes = ascii.encode('Content-Length: ${jsonBytes.length}\r\n\r\n');

  final builder = BytesBuilder(copy: false)
    ..add(headerBytes)
    ..add(jsonBytes);
  return builder.takeBytes();
}
