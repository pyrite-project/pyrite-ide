import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_file_protocol.dart';

void main() {
  test('builds the official WebREPL PUT request header', () {
    final request = buildWebReplFileRequest(
      operation: WebReplFileOperation.put,
      path: '/main.py',
      fileSize: 0x12345678,
    );
    final data = ByteData.sublistView(request);

    expect(request, hasLength(82));
    expect(request.sublist(0, 4), [0x57, 0x41, 1, 0]);
    expect(data.getUint64(4, Endian.little), 0);
    expect(data.getUint32(12, Endian.little), 0x12345678);
    expect(data.getUint16(16, Endian.little), utf8.encode('/main.py').length);
    expect(request.sublist(18, 26), utf8.encode('/main.py'));
  });

  test('encodes WebREPL paths as UTF-8', () {
    const path = '/中文.py';
    final request = buildWebReplFileRequest(
      operation: WebReplFileOperation.get,
      path: path,
      fileSize: 0,
    );
    final pathBytes = utf8.encode(path);

    expect(request[2], 2);
    expect(
      ByteData.sublistView(request).getUint16(16, Endian.little),
      pathBytes.length,
    );
    expect(request.sublist(18, 18 + pathBytes.length), pathBytes);
  });

  test('rejects paths which exceed the protocol field', () {
    expect(
      () => buildWebReplFileRequest(
        operation: WebReplFileOperation.put,
        path: '/${List.filled(22, '中').join()}',
        fileSize: 1,
      ),
      throwsA(isA<WebReplFileProtocolException>()),
    );
  });

  test('parses WebREPL status responses', () {
    expect(parseWebReplFileResponse([0x57, 0x42, 0, 0]), 0);
    expect(parseWebReplFileResponse([0x57, 0x42, 2, 0]), 2);
    expect(
      () => parseWebReplFileResponse([0x57, 0x41, 0, 0]),
      throwsA(isA<WebReplFileProtocolException>()),
    );
  });
}
