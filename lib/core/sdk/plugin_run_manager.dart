import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:pyrite_ide/core/sdk/permission_log.dart';
import 'package:pyrite_ide/core/sdk/permissions.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:rfw/formats.dart' show DynamicMap, Missing;
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// SDK message type constants (Python <-> Dart)
// ---------------------------------------------------------------------------

abstract class IdeCommands {
  static const String eventCallback = 'ide.event.callback';
  static const String lifecycleHook = 'ide.lifecycle.hook';
  static const String pageRefresh = 'ide.page.refresh';
  static const String routerSync = 'ide.router.sync';
  static const String responsePath = 'ide.response.path';
  static const String responseOk = 'ide.response.ok';
  static const String responseError = 'ide.response.error';
}

abstract class SdkCommands {
  static const String outputAppend = 'sdk.output.append';
  static const String pagePush = 'sdk.page.push';
  static const String varSet = 'sdk.var.set';
  static const String pathRequest = 'sdk.path.request';
  static const String routerPush = 'sdk.router.push';
  static const String routerPop = 'sdk.router.pop';
  static const String routerReplace = 'sdk.router.replace';
  static const String routerGoto = 'sdk.router.goto';
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

typedef CommandHandler =
    void Function(
      Map<String, dynamic> envelope,
      void Function(Map<String, dynamic>) respond,
    );

// ---------------------------------------------------------------------------
// PluginRunManager
// ---------------------------------------------------------------------------

class PluginRunManager {
  PluginRunManager({
    required this.port,
    required this.assetsPath,
    this.pluginId = '',
    this.pluginType = 'ui',
    this.pluginPermissions = const {},
    this.permissionLog,
    this.onOutput,
  }) : dataPath = '$assetsPath/data';

  final int port;
  final String assetsPath;
  final String dataPath;
  final String pluginId;
  final String pluginType;
  final Map<String, List<String>> pluginPermissions;
  final PermissionLogService? permissionLog;
  final void Function(String message)? onOutput;
  WebSocketChannel? _channel;
  bool _connecting = false;
  final Map<String, String> pages = {};
  final Map<String, dynamic> vars = {};
  void Function()? onDataChanged;
  void Function(String scope, String path)? onPathRequest;
  void Function(String currentRoute, List<String> routeStack)? onRouteChanged;

  final List<String> routeStack = [];
  String currentRoute = 'home';

  final Map<String, CommandHandler> _handlers = {};
  final Map<String, Completer<Map<String, dynamic>>> _pendingReplies = {};

  void registerHandler(String type, CommandHandler handler) {
    final required = Permissions.getRequirement(type);
    if (required != null && pluginPermissions.isNotEmpty) {
      _handlers[type] = (envelope, respond) {
        final granted = Permissions.check(pluginPermissions, required);
        permissionLog?.add(
          PermissionLogEntry(
            pluginId: pluginId,
            command: type,
            required: required,
            granted: granted,
          ),
        );
        if (!granted) {
          respond(
            makeEnvelope(
              type: IdeCommands.responseError,
              payload: {'message': 'Permission denied: $required'},
              replyTo: envelope['id'],
            ),
          );
          return;
        }
        handler(envelope, respond);
      };
    } else {
      _handlers[type] = handler;
    }
  }

  void unregisterHandler(String type) {
    _handlers.remove(type);
  }

  // -- Built-in handlers ----------------------------------------------------

  void _initBuiltinHandlers() {
    registerHandler(SdkCommands.outputAppend, _handleOutputAppend);
    registerHandler(SdkCommands.pagePush, _handlePagePush);
    registerHandler(SdkCommands.varSet, _handleVarSet);
    registerHandler(SdkCommands.pathRequest, _handlePathRequest);
    registerHandler(SdkCommands.routerPush, _handleRouterPush);
    registerHandler(SdkCommands.routerPop, _handleRouterPop);
    registerHandler(SdkCommands.routerReplace, _handleRouterReplace);
    registerHandler(SdkCommands.routerGoto, _handleRouterGoto);
  }

  void _handlePagePush(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final pagesData = payload['pages'];
    if (pagesData != null) {
      pages.addAll(Map<String, String>.from(pagesData));
    }
    respond(
      makeEnvelope(
        type: SdkCommands.responseOk,
        payload: {'data': null},
        replyTo: envelope['id'],
      ),
    );
    onDataChanged?.call();
  }

  void _handleRouterPush(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final page = payload['page']?.toString() ?? 'home';
    routeStack.add(currentRoute);
    currentRoute = page;
    _syncRouteToPython();
    respond(
      makeEnvelope(
        type: SdkCommands.responseOk,
        payload: {'data': null},
        replyTo: envelope['id'],
      ),
    );
    onRouteChanged?.call(currentRoute, routeStack);
  }

  void _handleRouterPop(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    popRoute();
    respond(
      makeEnvelope(
        type: SdkCommands.responseOk,
        payload: {'data': null},
        replyTo: envelope['id'],
      ),
    );
  }

  void popRoute() {
    if (routeStack.isNotEmpty) {
      currentRoute = routeStack.removeLast();
    }
    _syncRouteToPython();
    onRouteChanged?.call(currentRoute, routeStack);
  }

  void _handleRouterReplace(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final page = payload['page']?.toString() ?? 'home';
    currentRoute = page;
    _syncRouteToPython();
    respond(
      makeEnvelope(
        type: SdkCommands.responseOk,
        payload: {'data': null},
        replyTo: envelope['id'],
      ),
    );
    onRouteChanged?.call(currentRoute, routeStack);
  }

  void _handleRouterGoto(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final page = payload['page']?.toString() ?? 'home';
    routeStack.clear();
    routeStack.add('home');
    currentRoute = page;
    _syncRouteToPython();
    respond(
      makeEnvelope(
        type: SdkCommands.responseOk,
        payload: {'data': null},
        replyTo: envelope['id'],
      ),
    );
    onRouteChanged?.call(currentRoute, routeStack);
  }

  void _syncRouteToPython() {
    sendJson(
      makeEnvelope(
        type: IdeCommands.routerSync,
        payload: {'page': currentRoute, 'stack': routeStack},
      ),
    );
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
    respond(
      makeEnvelope(
        type: SdkCommands.responseOk,
        payload: {'data': null},
        replyTo: envelope['id'],
      ),
    );
    onDataChanged?.call();
  }

  void _handlePathRequest(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final scope = payload['scope']?.toString() ?? 'assets';

    String resolvedPath;
    switch (scope) {
      case 'plugin':
      case 'assets':
        resolvedPath = assetsPath;
      case 'data':
        resolvedPath = dataPath;
      case 'cache':
        resolvedPath = '$assetsPath/cache';
      case 'temp':
        resolvedPath = Directory.systemTemp.path;
      default:
        resolvedPath = assetsPath;
    }

    onOutput?.call(
      '[$pluginId] path request scope=$scope resolved=$resolvedPath',
    );

    respond(
      makeEnvelope(
        type: IdeCommands.responsePath,
        payload: {'scope': scope, 'path': resolvedPath, 'plugin_id': pluginId},
        replyTo: envelope['id'],
      ),
    );
  }

  // -- Connection ------------------------------------------------------------

  Future<void> connect() async {
    if (_stopped) return;
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
          onOutput?.call('[$pluginId] connected on port $port');
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
        } on Exception {
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

  Future<void> runOnce() async {
    await connect();
    await sendLifecycleHook(LifecycleHook.start.value);
    await stop();
  }

  void _setupListener() {
    _channel!.stream.listen(
      (message) {
        final Map<String, dynamic> envelope = jsonDecode(message as String);
        final type = envelope['type']?.toString() ?? '';
        if (type != SdkCommands.outputAppend) {
          onOutput?.call('[$pluginId] <- $message');
        }
        if (type == IdeCommands.responseError || type == SdkCommands.responseError) {
          final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
          final details = payload['details']?.toString();
          if (details != null && details.isNotEmpty && details != 'null') {
            onOutput?.call('[$pluginId] error details:\n$details');
          }
        }

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
        onOutput?.call('[$pluginId] websocket error: $error');
        _failAllPendingReplies(error);
        _channel = null;
      },
      onDone: () {
        onOutput?.call('[$pluginId] websocket closed');
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
    if (!_isRoutineAck(message)) {
      onOutput?.call('[$pluginId] -> $message');
    }
    _channel!.sink.add(message);
  }

  bool _isRoutineAck(String message) {
    try {
      final envelope = jsonDecode(message) as Map<String, dynamic>;
      return envelope['type'] == SdkCommands.responseOk &&
          envelope['payload'] is Map &&
          (envelope['payload'] as Map)['data'] == null;
    } catch (_) {
      return false;
    }
  }

  void _handleOutputAppend(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final stream = payload['stream']?.toString() ?? 'stdout';
    final text = payload['text']?.toString() ?? '';
    final sourcePluginId = payload['plugin_id']?.toString() ?? pluginId;
    if (text.isNotEmpty) {
      onOutput?.call('[$sourcePluginId][$stream] $text');
    }
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
    sendJson(
      makeEnvelope(
        type: IdeCommands.eventCallback,
        payload: {
          'page': page,
          'name': name,
          'args': _convertToSerializable(args),
        },
      ),
    );
  }

  Future<void> sendLifecycleHook(String hook) async {
    await connect();
    sendJson(
      makeEnvelope(type: IdeCommands.lifecycleHook, payload: {'hook': hook}),
    );
  }

  Future<void> sendPageRefresh() async {
    await connect();
    sendJson(makeEnvelope(type: IdeCommands.pageRefresh));
  }

  // -- Cleanup ---------------------------------------------------------------

  bool _stopped = false;

  Future<void> stop() async {
    _stopped = true;
    onOutput?.call('[$pluginId] stopped');
    _failAllPendingReplies('PluginRunManager stopped');
    _channel?.sink.close();
    _channel = null;
    pages.clear();
    vars.clear();
    routeStack.clear();
    currentRoute = 'home';
    _handlers.clear();
  }

  void dispose() {
    _failAllPendingReplies('PluginRunManager disposed');
    _channel?.sink.close();
    _channel = null;
  }
}
