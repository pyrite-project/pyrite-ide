import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'package:rfw/formats.dart' show DynamicMap, Missing;

enum LifecycleHooks {
  onInstall,
  onStart,
  onPause,
  onResume,
  onDispose,
  onUninstall,
}

class PluginRunManager {
  PluginRunManager({required this.port});
  final int port;
  WebSocketChannel? _channel;

  // 用于按顺序存储 Completer (解决请求与响应的匹配)
  final List<Completer<String>> _responseQueue = [];

  Future<void> connect() async {
    // 如果已经连接且未关闭，则直接返回
    if (_channel != null && _channel!.closeCode == null) return;

    _channel = WebSocketChannel.connect(Uri.parse('ws://localhost:$port'));
    await _channel!.ready;
    print("WebSocket Connected.");

    _channel!.stream.listen(
      (message) {
        final Map<String, dynamic> data = jsonDecode(message as String);

        final cmdStr = data['cmd']?.toString() ?? '';
        final hasManagerData =
            data['data'] != null && data['data']['pages'] != null;

        if (cmdStr.contains('Commands.Response') || hasManagerData) {
          if (_responseQueue.isNotEmpty) {
            // 取出最早的一个请求并完成它 (先进先出)
            final completer = _responseQueue.removeAt(0);
            if (!completer.isCompleted) {
              completer.complete(message);
            }
          }
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

  Future<void> sendCallback(
    String name,
    DynamicMap args,
    String manager,
  ) async {
    await connect();

    final String request = jsonEncode({
      'cmd': 'Commands.EventCallback',
      'data': {
        'manager': manager,
        'callback': {'event': name, 'args': _convertToSerializable(args)},
      },
    });

    send(request);
  }

  Future<void> sendLifecycleHooks(LifecycleHooks lifecycle) async {
    await connect();

    final String text = lifecycle.toString().replaceRange(15, 17, "On");
    final String request = jsonEncode({
      'cmd': 'Commands.LifecycleHooks',
      'data': {"lifecycleHook": text},
    });

    send(request);
  }

  Future<String> _getPages() async {
    final String request = jsonEncode({'cmd': 'Commands.GetPages', 'data': {}});
    return await requestWithResponse(request);
  }

  Future<Map<String, dynamic>> getPages() async {
    final String rawResponse = await _getPages();
    final Map data = jsonDecode(rawResponse) as Map;
    return data['data']['pages'];
  }
}
