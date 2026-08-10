import 'dart:convert';
import 'dart:typed_data';

enum WebReplFileOperation {
  put(1),
  get(2);

  const WebReplFileOperation(this.code);
  final int code;
}

class WebReplFileProtocolException implements Exception {
  const WebReplFileProtocolException(this.message);

  final String message;

  @override
  String toString() => 'WebReplFileProtocolException: $message';
}

Uint8List buildWebReplFileRequest({
  required WebReplFileOperation operation,
  required String path,
  required int fileSize,
}) {
  final pathBytes = Uint8List.fromList(utf8.encode(path));
  if (pathBytes.length > 64) {
    throw WebReplFileProtocolException(
      'WebREPL file paths are limited to 64 UTF-8 bytes.',
    );
  }
  if (fileSize < 0 || fileSize > 0xffffffff) {
    throw WebReplFileProtocolException(
      'WebREPL file size is outside the supported 32-bit range.',
    );
  }

  final request = Uint8List(82);
  final data = ByteData.sublistView(request);
  request[0] = 0x57; // W
  request[1] = 0x41; // A
  request[2] = operation.code;
  request[3] = 0;
  data.setUint64(4, 0, Endian.little);
  data.setUint32(12, fileSize, Endian.little);
  data.setUint16(16, pathBytes.length, Endian.little);
  request.setRange(18, 18 + pathBytes.length, pathBytes);
  return request;
}

int parseWebReplFileResponse(List<int> response) {
  if (response.length != 4 || response[0] != 0x57 || response[1] != 0x42) {
    throw const WebReplFileProtocolException(
      'Invalid WebREPL file response signature.',
    );
  }
  return ByteData.sublistView(
    Uint8List.fromList(response),
  ).getUint16(2, Endian.little);
}
