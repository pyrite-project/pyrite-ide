import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:rfw/formats.dart' show DynamicMap, Missing;
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// SDK message type constants (Python <-> Dart)
// ---------------------------------------------------------------------------

abstract class IdeCommands {
  static const String eventCallback = 'ide.event.callback';
  static const String lifecycleHook = 'ide.lifecycle.hook';
  static const String pageRefresh = 'ide.page.refresh';
  static const String responsePath = 'ide.response.path';
  static const String responseOk = 'ide.response.ok';
  static const String responseError = 'ide.response.error';
}

abstract class SdkCommands {
  static const String pagePush = 'sdk.page.push';
  static const String varSet = 'sdk.var.set';
  static const String pathRequest = 'sdk.path.request';
  static const String responseOk = 'sdk.response.ok';
  static const String responseError = 'sdk.response.error';
}

// ---------------------------------------------------------------------------
// Envelope helpers
// ---------------------------------------------------------------------------

String _newId() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Map<String, dynamic> makeEnvelope({
  required String type,
  Map<String, dynamic>? payload,
  dynamic data,
  String? replyTo,
}) {
  return {
    'version': '0.0',
    'id': _newId(),
    'type': type,
    'payload': payload ?? {},
    'data': data,
    'reply_to': replyTo,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
}

// ---------------------------------------------------------------------------
// Command handler type
// ---------------------------------------------------------------------------

typedef CommandHandler = void Function(
  Map<String, dynamic> envelope,
  void Function(Map<String, dynamic>) respond,
);

// ---------------------------------------------------------------------------
// PluginRunManager
// ---------------------------------------------------------------------------

class PluginRunManager {
  PluginRunManager({required this.port, required this.assetsPath});

  final int port;
  final String assetsPath;
  WebSocketChannel? _channel;
  bool _connecting = false;
  final Map<String, String> pages = {};
  final Map<String, dynamic> vars = {};
  void Function()? onDataChanged;
  void Function(String scope, String path)? onPathRequest;

  final Map<String, CommandHandler> _handlers = {};
  final Map<String, Completer<Map<String, dynamic>>> _pendingReplies = {};

  void registerHandler(String type, CommandHandler handler) {
    _handlers[type] = handler;
  }

  void unregisterHandler(String type) {
    _handlers.remove(type);
  }

  // -- Built-in handlers ----------------------------------------------------

  void _initBuiltinHandlers() {
    registerHandler(SdkCommands.pagePush, _handlePagePush);
    registerHandler(SdkCommands.varSet, _handleVarSet);
    registerHandler(SdkCommands.pathRequest, _handlePathRequest);
  }

  void _handlePagePush(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final pagesData = payload['pages'];
    if (pagesData != null) {
      pages.clear();
      pages.addAll(Map<String, String>.from(pagesData));
    }
    respond(makeEnvelope(
      type: SdkCommands.responseOk,
      payload: {'data': null},
      replyTo: envelope['id'],
    ));
    onDataChanged?.call();
  }

  void _handleVarSet(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final varName = payload['name']?.toString();
    final varValue = payload['value'];
    if (varName != null) {
      vars[varName] = varValue;
    }
    respond(makeEnvelope(
      type: SdkCommands.responseOk,
      payload: {'data': null},
      replyTo: envelope['id'],
    ));
    onDataChanged?.call();
  }

  void _handlePathRequest(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final scope = payload['scope']?.toString() ?? 'assets';

    respond(makeEnvelope(
      type: IdeCommands.responsePath,
      payload: {
        'scope': scope,
        'path': assetsPath,
      },
      replyTo: envelope['id'],
    ));
  }

  // -- Connection ------------------------------------------------------------

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
        final Map<String, dynamic> envelope = jsonDecode(message as String);
        final type = envelope['type']?.toString() ?? '';

        // Check if this is a reply to a pending request
        final replyTo = envelope['reply_to']?.toString();
        if (replyTo != null && _pendingReplies.containsKey(replyTo)) {
          _pendingReplies.remove(replyTo)!.complete(envelope);
          return;
        }

        // Dispatch to registered handler
        final handler = _handlers[type];
        if (handler != null) {
          handler(envelope, (response) => send(jsonEncode(response)));
          return;
        }
      },
      onError: (error) {
        _failAllPendingReplies(error);
        _channel = null;
      },
      onDone: () {
        _failAllPendingReplies('WebSocket channel closed');
        _channel = null;
      },
    );
  }

  void _failAllPendingReplies(dynamic error) {
    for (final completer in _pendingReplies.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingReplies.clear();
  }

  // -- Sending ---------------------------------------------------------------

  void send(String message) {
    if (_channel == null) {
      throw StateError('WebSocket is not connected');
    }
    _channel!.sink.add(message);
  }

  void sendJson(Map<String, dynamic> envelope) {
    send(jsonEncode(envelope));
  }

  Future<Map<String, dynamic>> sendAndWaitReply(
    Map<String, dynamic> envelope,
  ) async {
    await connect();
    final id = envelope['id'] as String;
    final completer = Completer<Map<String, dynamic>>();
    _pendingReplies[id] = completer;
    send(jsonEncode(envelope));
    return completer.future;
  }

  // -- IDE -> SDK commands ---------------------------------------------------

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
    sendJson(makeEnvelope(
      type: IdeCommands.eventCallback,
      payload: {
        'page': page,
        'name': name,
        'args': _convertToSerializable(args),
      },
    ));
  }

  Future<void> sendLifecycleHook(String hook) async {
    await connect();
    sendJson(makeEnvelope(
      type: IdeCommands.lifecycleHook,
      payload: {'hook': hook},
    ));
  }

  Future<void> sendPageRefresh() async {
    await connect();
    sendJson(makeEnvelope(type: IdeCommands.pageRefresh));
  }

  // -- Cleanup ---------------------------------------------------------------

  void dispose() {
    _failAllPendingReplies('PluginRunManager disposed');
    _channel?.sink.close();
    _channel = null;
  }
}
