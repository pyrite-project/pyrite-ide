import 'dart:async';
import 'dart:typed_data';

import 'package:pyrite_ide/core/platform/pyrite_io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket transport for the MicroPython WebREPL protocol.
///
/// Uses `package:web_socket_channel`, which connects over the browser's
/// WebSocket on Flutter Web and over dart:io sockets on native platforms, so
/// the same transport works everywhere. Text frames surface as [String] and
/// binary frames as [Uint8List] on both platforms.
class WebReplSocket {
  WebReplSocket._(this._channel);

  final WebSocketChannel _channel;
  bool _closed = false;

  /// Opens a WebREPL connection to [uri].
  ///
  /// Throws when the socket cannot be established within [timeout].
  static Future<WebReplSocket> connect(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final channel = WebSocketChannel.connect(uri);
    try {
      await channel.ready.timeout(timeout);
    } catch (_) {
      unawaited(channel.sink.close());
      rethrow;
    }
    return WebReplSocket._(channel);
  }

  /// Incoming frames: [String] for text, [Uint8List] for binary.
  Stream<Object> get stream => _channel.stream.map((dynamic frame) {
        if (frame is String) return frame;
        if (frame is Uint8List) return frame;
        if (frame is ByteBuffer) return frame.asUint8List();
        if (frame is List<int>) return Uint8List.fromList(frame);
        return frame as Object;
      });

  /// Sends a text frame.
  void sendText(String text) => _channel.sink.add(text);

  /// Sends a binary frame; throws [WebSocketException] when closed.
  Future<void> sendBinary(List<int> data) async {
    if (_closed) {
      throw WebSocketException('WebREPL socket is closed');
    }
    _channel.sink.add(data is Uint8List ? data : Uint8List.fromList(data));
  }

  /// Closes the connection gracefully.
  Future<void> close() {
    _closed = true;
    return _channel.sink.close();
  }
}
