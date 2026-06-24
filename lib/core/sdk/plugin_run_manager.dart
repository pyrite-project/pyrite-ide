import 'dart:async';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'package:rfw/formats.dart' show DynamicMap, Missing;

class PluginRunManager {
  PluginRunManager({required this.port, required this.assetsPath});
  final int port;
  final String assetsPath;
  WebSocketChannel? _channel;
  Map<String, String> pages = {};
  void Function()? onRefresh;
  Map<String, dynamic> vars = {};
  void Function()? onSetVar;

  // 用于按顺序存储 Completer (解决请求与响应的匹配)
  final List<Completer<String>> _responseQueue = [];

  Future<void> connect() async {
    if (_channel != null && _channel!.closeCode == null) return;

    const maxRetries = 20;
    const retryDelay = Duration(milliseconds: 500);

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print("try to connect to ws://localhost:$port (attempt $attempt)");
        _channel = WebSocketChannel.connect(Uri.parse('ws://localhost:$port'));
        await _channel!.ready;
        print("WebSocket Connected.");
        break;
      } on SocketException catch (e) {
        print("SocketException in PluginRunManager: $e");
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
        } else {
          rethrow;
        }
      } on WebSocketChannelException catch (e) {
        print("WebSocketChannelException in PluginRunManager: $e");
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
        } else {
          rethrow;
        }
      }
    }

    _channel!.stream.listen(
      (message) {
        final Map<String, dynamic> data = jsonDecode(message as String);

        final cmdStr = data['cmd']?.toString() ?? '';
        final hasPagesData =
            data['data'] != null && data['data']['pages'] != null;
        final hasPathTypeData =
            data['data'] != null && data['data']['pathType'] != null;
        final hasVarData =
            data['data'] != null && data['data']['varName'] != null && data['data']['varValue'] != null;

        if (cmdStr.contains('Commands.SDK.Request.GetPath') && hasPathTypeData) {
          final String request = jsonEncode({
            'cmd': 'Commands.IDE.Response.GetPath',
            'data': {
              'pathType': data['data']['pathType'],
              'path': {
                "PathType.Assets": assetsPath
              }[data['data']['pathType']],
            },
          });
          send(request);
        } else if (cmdStr.contains('Commands.SDK.Request.Refresh') && hasPagesData) {
          _handleRefresh(data);
        } else if (cmdStr.contains('Commands.SDK.Request.SetVar') && hasVarData) {
          _handleSetVar(data);
        } else {
          print("Received push notification from server: $data");
        }
      },
      onError: (error) {
        print("WebSocket Error: $error");
        _failAllCompleters(error);
        _channel = null;
      },
      onDone: () {
        print("WebSocket connection closed by server.");
        _failAllCompleters('WebSocket channel closed');
        _channel = null;
      },
    );
  }

  void _failAllCompleters(dynamic error) {
    for (var completer in _responseQueue) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _responseQueue.clear();
  }

  void send(String message) {
    print("send message $message");
    if (_channel != null) {
      _channel!.sink.add(message);
    }
  }

  Future<String> requestWithResponse(String requestJson) async {
    await connect();
    final completer = Completer<String>();
    _responseQueue.add(completer);
    send(requestJson);
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

    final String request = jsonEncode({
      'cmd': 'Commands.IDE.Request.EventCallback',
      'data': {
        'page': page,
        'callback': {'event': name, 'args': _convertToSerializable(args)},
      },
    });

    send(request);
  }

  Future<void> sendLifecycleHooks(String lifecycle) async {
    await connect();

    final String request = jsonEncode({
      'cmd': 'Commands.IDE.Request.LifecycleHooks',
      'data': {"lifecycleHook": lifecycle},
    });

    send(request);
  }

  void _handleRefresh(Map<String, dynamic> data) {
    final rawPages = data['data']!['pages'];
    print("Refresh received, pages data: $rawPages");
    pages = Map<String, String>.from(rawPages ?? {});
    onRefresh?.call();
  }

  void _handleSetVar(Map<String, dynamic> data) {
    final varName = data['data']!['varName'];
    final varValue = data['data']!['varValue'];
    print("SetVar received, varName: $varName, varValue: $varValue");
    vars = {...vars, varName: varValue};
    onSetVar?.call();
  }
}
