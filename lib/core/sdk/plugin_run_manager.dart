import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rfw/formats.dart' show DynamicMap, Missing;
import 'package:web_socket_channel/web_socket_channel.dart';

abstract class SdkCommands {
  static const String eventCallback = 'Commands.EventCallback';
  static const String response = 'Commands.Response';
  static const String errorResponse = 'Commands.ErrorResponse';
  static const String send = 'Commands.Send';
  static const String lifecycleHooks = 'Commands.LifecycleHooks';
}

typedef CommandHandler = void Function(
  Map<String, dynamic> data,
  void Function(Map<String, dynamic>) respond,
);

class PluginRunManager {
  PluginRunManager({required this.port, required this.assetsPath});

  final int port;
  final String assetsPath;
  WebSocketChannel? _channel;
  bool _connecting = false;
  final Map<String, String> pages = {};
  final Map<String, dynamic> vars = {};
  void Function()? onDataChanged;

  int _nextRequestId = 0;
  final Map<String, Completer<String>> _pendingRequests = {};

  final Map<String, CommandHandler> _handlers = {};

  void registerHandler(String cmd, CommandHandler handler) {
    _handlers[cmd] = handler;
  }

  void _initBuiltinHandlers() {
    registerHandler(SdkCommands.send, _handleSend);
    registerHandler(SdkCommands.response, _handleResponse);
    registerHandler(SdkCommands.errorResponse, _handleErrorResponse);
  }

  void _handleSend(
    Map<String, dynamic> data,
    void Function(Map<String, dynamic>) respond,
  ) {
    final pagesData = data['data']?['pages'];
    if (pagesData != null) {
      pages.clear();
      pages.addAll(Map<String, String>.from(pagesData));
    }

    final varName = data['data']?['varName'];
    if (varName != null) {
      vars[varName] = data['data']!['varValue'];
    }

    onDataChanged?.call();
  }

  void _handleResponse(
    Map<String, dynamic> data,
    void Function(Map<String, dynamic>) respond,
  ) {
    final pagesData = data['data']?['pages'];
    if (pagesData != null) {
      pages.clear();
      pages.addAll(Map<String, String>.from(pagesData));
    }

    onDataChanged?.call();
  }

  void _handleErrorResponse(
    Map<String, dynamic> data,
    void Function(Map<String, dynamic>) respond,
  ) {}

  Future<void> connect() async {
    if (_channel != null && _channel!.closeCode == null) return;
    if (_connecting) {
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return _connecting;
      });
      if (_channel != null && _channel!.closeCode == null) return;
    }

    _connecting = true;
    const maxRetries = 20;
    const retryDelay = Duration(milliseconds: 500);

    try {
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          _channel = WebSocketChannel.connect(
            Uri.parse('ws://localhost:$port'),
          );
          await _channel!.ready;
          _initBuiltinHandlers();
          _setupListener();
          break;
        } on SocketException {
          if (attempt < maxRetries) {
            await Future.delayed(retryDelay);
          } else {
            rethrow;
          }
        } on WebSocketChannelException {
          if (attempt < maxRetries) {
            await Future.delayed(retryDelay);
          } else {
            rethrow;
          }
        }
      }
    } finally {
      _connecting = false;
    }
  }

  void _setupListener() {
    _channel!.stream.listen(
      (message) {
        final Map<String, dynamic> data = jsonDecode(message as String);
        final cmdStr = data['cmd']?.toString() ?? '';

        final requestId = data['requestId']?.toString();
        if (requestId != null && _pendingRequests.containsKey(requestId)) {
          _pendingRequests.remove(requestId)!.complete(jsonEncode(data));
          return;
        }

        final handler = _handlers[cmdStr];
        if (handler != null) {
          handler(data, (response) => send(jsonEncode(response)));
          return;
        }
      },
      onError: (error) {
        _failAllPendingRequests(error);
        _channel = null;
      },
      onDone: () {
        _failAllPendingRequests('WebSocket channel closed');
        _channel = null;
      },
    );
  }

  void _failAllPendingRequests(dynamic error) {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingRequests.clear();
  }

  void send(String message) {
    if (_channel == null) {
      throw StateError('WebSocket is not connected');
    }
    _channel!.sink.add(message);
  }

  void sendJson(Map<String, dynamic> data) {
    send(jsonEncode(data));
  }

  Future<String> requestWithResponse(String requestJson) async {
    await connect();
    final requestId = 'req_${_nextRequestId++}';
    final data = jsonDecode(requestJson) as Map<String, dynamic>;
    data['requestId'] = requestId;
    final completer = Completer<String>();
    _pendingRequests[requestId] = completer;
    send(jsonEncode(data));
    return completer.future;
  }

  dynamic _convertToSerializable(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry(key, _convertToSerializable(val)),
      );
    }
    if (value is List) return value.map(_convertToSerializable).toList();
    if (value is String || value is num || value is bool) return value;
    if (value is Missing) return 'Missing';
    return value.toString();
  }

  Future<void> sendCallback(String name, DynamicMap args, String page) async {
    await connect();

    sendJson({
      'cmd': SdkCommands.eventCallback,
      'data': {
        'page': page,
        'callback': {'event': name, 'args': _convertToSerializable(args)},
      },
    });
  }

  Future<void> sendLifecycleHooks(String lifecycle) async {
    await connect();

    sendJson({
      'cmd': SdkCommands.lifecycleHooks,
      'data': {'lifecycleHook': lifecycle},
    });
  }

  void dispose() {
    _failAllPendingRequests('PluginRunManager disposed');
    _channel?.sink.close();
    _channel = null;
  }
}
