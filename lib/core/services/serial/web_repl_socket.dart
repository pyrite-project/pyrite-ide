import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class WebReplSocket {
  WebReplSocket._(this._socket, this._iterator);

  final Socket _socket;
  final StreamIterator<Uint8List> _iterator;
  final StreamController<Object> _controller = StreamController<Object>();
  final List<int> _receiveBuffer = [];
  final Random _random = Random.secure();

  BytesBuilder? _fragmentBuffer;
  int? _fragmentOpcode;
  bool _closed = false;

  Stream<Object> get stream => _controller.stream;

  static Future<WebReplSocket> connect(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final socket = await Socket.connect(uri.host, uri.port, timeout: timeout);
    final iterator = StreamIterator<Uint8List>(socket);
    try {
      final random = Random.secure();
      final key = base64.encode(
        List<int>.generate(16, (_) => random.nextInt(256)),
      );
      final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      socket.add(
        ascii.encode(
          'GET ${path.isEmpty ? '/' : path} HTTP/1.1\r\n'
          'Host: ${uri.host}:${uri.port}\r\n'
          'Connection: Upgrade\r\n'
          'Upgrade: websocket\r\n'
          'Sec-WebSocket-Key: $key\r\n'
          'Sec-WebSocket-Version: 13\r\n'
          '\r\n',
        ),
      );
      await socket.flush();

      final response = <int>[];
      var headerEnd = -1;
      while (headerEnd < 0) {
        if (!await iterator.moveNext().timeout(timeout)) {
          throw const WebSocketException(
            'WebREPL closed during the WebSocket handshake',
          );
        }
        response.addAll(iterator.current);
        headerEnd = _indexOfHeaderEnd(response);
        if (response.length > 16 * 1024) {
          throw const WebSocketException(
            'WebREPL returned an oversized WebSocket handshake',
          );
        }
      }

      final header = latin1.decode(response.sublist(0, headerEnd));
      final statusLine = const LineSplitter().convert(header).firstOrNull ?? '';
      if (!RegExp(r'^HTTP/1\.[01] 101(?:\s|$)').hasMatch(statusLine)) {
        throw WebSocketException(
          'WebREPL did not upgrade to WebSocket: $statusLine',
        );
      }

      final result = WebReplSocket._(socket, iterator);
      final remaining = response.sublist(headerEnd + 4);
      unawaited(result._readFrames(remaining));
      return result;
    } catch (_) {
      await iterator.cancel();
      await socket.close();
      rethrow;
    }
  }

  static int _indexOfHeaderEnd(List<int> data) {
    for (var index = 0; index <= data.length - 4; index++) {
      if (data[index] == 13 &&
          data[index + 1] == 10 &&
          data[index + 2] == 13 &&
          data[index + 3] == 10) {
        return index;
      }
    }
    return -1;
  }

  Future<void> _readFrames(List<int> initialData) async {
    try {
      if (initialData.isNotEmpty) _addIncoming(initialData);
      while (!_closed && await _iterator.moveNext()) {
        _addIncoming(_iterator.current);
      }
    } catch (error, stackTrace) {
      if (!_closed) _controller.addError(error, stackTrace);
    } finally {
      await _finish();
    }
  }

  void _addIncoming(List<int> data) {
    _receiveBuffer.addAll(data);
    while (_tryReadFrame()) {}
  }

  bool _tryReadFrame() {
    if (_receiveBuffer.length < 2) return false;

    final first = _receiveBuffer[0];
    final second = _receiveBuffer[1];
    final fin = first & 0x80 != 0;
    final opcode = first & 0x0f;
    final masked = second & 0x80 != 0;
    var payloadLength = second & 0x7f;
    var offset = 2;

    if (payloadLength == 126) {
      if (_receiveBuffer.length < offset + 2) return false;
      payloadLength =
          (_receiveBuffer[offset] << 8) | _receiveBuffer[offset + 1];
      offset += 2;
    } else if (payloadLength == 127) {
      if (_receiveBuffer.length < offset + 8) return false;
      payloadLength = 0;
      for (var index = 0; index < 8; index++) {
        payloadLength = (payloadLength << 8) | _receiveBuffer[offset + index];
      }
      offset += 8;
    }

    List<int>? mask;
    if (masked) {
      if (_receiveBuffer.length < offset + 4) return false;
      mask = _receiveBuffer.sublist(offset, offset + 4);
      offset += 4;
    }
    if (_receiveBuffer.length < offset + payloadLength) return false;

    final payload = Uint8List.fromList(
      _receiveBuffer.sublist(offset, offset + payloadLength),
    );
    _receiveBuffer.removeRange(0, offset + payloadLength);
    if (mask != null) {
      for (var index = 0; index < payload.length; index++) {
        payload[index] ^= mask[index % 4];
      }
    }
    _handleFrame(opcode, fin, payload);
    return true;
  }

  void _handleFrame(int opcode, bool fin, Uint8List payload) {
    switch (opcode) {
      case 0x0:
        final fragments = _fragmentBuffer;
        if (fragments == null) return;
        fragments.add(payload);
        if (fin) {
          final fragmentOpcode = _fragmentOpcode;
          final data = fragments.takeBytes();
          _fragmentBuffer = null;
          _fragmentOpcode = null;
          if (fragmentOpcode != null) _emitData(fragmentOpcode, data);
        }
      case 0x1:
      case 0x2:
        if (fin) {
          _emitData(opcode, payload);
        } else {
          _fragmentOpcode = opcode;
          _fragmentBuffer = BytesBuilder(copy: false)..add(payload);
        }
      case 0x8:
        unawaited(_finish());
      case 0x9:
        _sendFrame(0xA, payload);
      case 0xA:
        break;
    }
  }

  void _emitData(int opcode, Uint8List payload) {
    if (_controller.isClosed) return;
    if (opcode == 0x1) {
      _controller.add(utf8.decode(payload, allowMalformed: true));
    } else {
      _controller.add(payload);
    }
  }

  void sendText(String text) {
    if (_closed) return;
    _sendFrame(0x1, utf8.encode(text));
  }

  Future<void> sendBinary(List<int> data) async {
    if (_closed) {
      throw const WebSocketException('WebREPL socket is closed');
    }
    _sendFrame(0x2, data);
    await _socket.flush();
  }

  void _sendFrame(int opcode, List<int> payload) {
    if (_closed) return;
    final frame = BytesBuilder(copy: false)..addByte(0x80 | opcode);
    final length = payload.length;
    if (length < 126) {
      frame.addByte(0x80 | length);
    } else if (length <= 0xffff) {
      frame
        ..addByte(0x80 | 126)
        ..addByte(length >> 8)
        ..addByte(length);
    } else {
      frame.addByte(0x80 | 127);
      for (var shift = 56; shift >= 0; shift -= 8) {
        frame.addByte(length >> shift);
      }
    }

    final mask = List<int>.generate(4, (_) => _random.nextInt(256));
    frame.add(mask);
    final masked = Uint8List(payload.length);
    for (var index = 0; index < payload.length; index++) {
      masked[index] = payload[index] ^ mask[index % 4];
    }
    frame.add(masked);
    _socket.add(frame.takeBytes());
  }

  Future<void> close() async {
    if (_closed) return;
    _sendFrame(0x8, const []);
    await _finish();
  }

  Future<void> _finish() async {
    if (_closed) return;
    _closed = true;
    try {
      await _iterator.cancel();
    } catch (_) {}
    try {
      await _socket.close();
    } catch (_) {}
    if (!_controller.isClosed) await _controller.close();
  }
}
