import 'dart:convert';

List<int> encodeLspMessage(Map<String, dynamic> message) {
  final body = utf8.encode(jsonEncode(message));
  final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');
  return [...header, ...body];
}
