import 'dart:async';
import 'dart:convert';
import 'dart:io';

void _debugLog(String message) {
  // ignore: avoid_print
  print(message);
}

Future<LspClient> connectToLspServer() async {
  _debugLog('[LSP] Connecting to Python LSP Server at ws://127.0.0.1:2026...');

  const maxAttempts = 20;
  const delay = Duration(milliseconds: 200);
  WebSocket? socket;

  for (int i = 0; i < maxAttempts; i++) {
    try {
      socket = await WebSocket.connect('ws://127.0.0.1:2025');
      break;
    } catch (_) {
      await Future.delayed(delay);
    }
  }

  if (socket == null) {
    throw StateError(
      'Failed to connect to LSP WebSocket server on port 2026 after ${maxAttempts * delay.inMilliseconds}ms.\n'
      'Please ensure the Python LSP server is running and port 2026 is accessible.',
    );
  }

  _debugLog('[LSP] WebSocket connected.');
  return LspClient.fromWebSocket(socket);
}

/// LSP 客户端，基于 WebSocket 实现，保持与原有 stdio 版本完全一致的接口和行为
class LspClient {
  final WebSocket _socket;
  final StreamController<Map<String, dynamic>> _notificationsController =
      StreamController.broadcast();

  // 用于存储挂起的请求，以便匹配响应
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  int _id = 0;
  bool _isListening = false;
  bool _closed = false;
  StreamSubscription<dynamic>? _incomingSubscription;
  Timer? _heartbeatTimer;
  DateTime _lastMessageTime = DateTime.now();
  DateTime _lastPingTime = DateTime.now();

  int _textDocumentSyncChange = 1;
  bool get supportsIncrementalSync => _textDocumentSyncChange == 2;

  List<String> _semanticTokenTypes = const [];
  List<String> _semanticTokenModifiers = const [];
  bool get supportsSemanticTokens => _semanticTokenTypes.isNotEmpty;
  List<String> get semanticTokenTypes => _semanticTokenTypes;
  List<String> get semanticTokenModifiers => _semanticTokenModifiers;

  LspClient.fromWebSocket(this._socket) {
    _startListening();
  }

  void _startListening() {
    _isListening = true;
    _lastMessageTime = DateTime.now();
    _lastPingTime = DateTime.now();

    // 启动心跳检测
    _heartbeatTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (_closed) {
        _debugLog('Heartbeat: Client is closed, stopping timer');
        timer.cancel();
        return;
      }

      final timeSinceLastMessage = DateTime.now().difference(_lastMessageTime);
      final timeSinceLastPing = DateTime.now().difference(_lastPingTime);

      _debugLog(
        'Heartbeat check: last message ${timeSinceLastMessage.inSeconds} seconds ago, '
        'last ping ${timeSinceLastPing.inSeconds} seconds ago',
      );

      // 如果 30 秒内没有收到任何消息，发送 ping
      if (timeSinceLastMessage > Duration(seconds: 30)) {
        _debugLog('No message received for 30 seconds, connection may be dead');
        _debugLog('Attempting to send ping to verify connection');

        try {
          _lastPingTime = DateTime.now();
          // 发送一个简单的请求来测试连接是否仍然活跃
          sendRequest('textDocument/documentSymbol', {
                'textDocument': {'uri': 'file:///test.py'},
              })
              .timeout(
                Duration(seconds: 5),
                onTimeout: () {
                  _debugLog('Ping request timed out, closing connection');
                  _closeInternal();
                },
              )
              .catchError((error) {
                _debugLog('Ping request failed: $error');
                _closeInternal();
              });
        } catch (e) {
          _debugLog('Failed to send ping: $e');
          _closeInternal();
        }
      }
    });

    _incomingSubscription = _socket.listen(
      (dynamic data) {
        _lastMessageTime = DateTime.now();
        final String jsonString;
        if (data is String) {
          jsonString = data;
        } else if (data is List<int>) {
          jsonString = utf8.decode(data, allowMalformed: true);
        } else {
          _debugLog('[LSP Client] Unexpected data type: ${data.runtimeType}');
          return;
        }

        try {
          final message = jsonDecode(jsonString) as Map<String, dynamic>;
          _handleIncomingMessage(message);
        } catch (e) {
          _debugLog('[LSP Client] Failed to parse JSON: $e');
        }
      },
      onError: (error) {
        _debugLog('[LSP Client] WebSocket error: $error');
        _debugLog('[LSP Client] Error stack trace: ${StackTrace.current}');
        _closeInternal();
      },
      onDone: () {
        _debugLog('[LSP Client] WebSocket closed unexpectedly');
        _debugLog(
          '[LSP Client] Client state at close: closed=$_closed, listening=$_isListening',
        );
        _debugLog('[LSP Client] Pending requests: ${_pendingRequests.length}');
        _debugLog('[LSP Client] Close stack trace: ${StackTrace.current}');
        _closeInternal();
      },
      cancelOnError: false,
    );
  }

  void _applyServerCapabilities(dynamic initializeResult) {
    if (initializeResult is! Map) return;
    final capabilities = initializeResult['capabilities'];
    if (capabilities is! Map) return;
    final textDocumentSync = capabilities['textDocumentSync'];
    if (textDocumentSync is int) {
      _textDocumentSyncChange = textDocumentSync;
      return;
    }
    if (textDocumentSync is Map) {
      final change = textDocumentSync['change'];
      if (change is int) _textDocumentSyncChange = change;
    }

    final semanticTokensProvider = capabilities['semanticTokensProvider'];
    if (semanticTokensProvider is Map) {
      final legend = semanticTokensProvider['legend'];
      if (legend is Map) {
        final types = legend['tokenTypes'];
        final modifiers = legend['tokenModifiers'];
        if (types is List) {
          _semanticTokenTypes = types.whereType<String>().toList(
            growable: false,
          );
        }
        if (modifiers is List) {
          _semanticTokenModifiers = modifiers.whereType<String>().toList(
            growable: false,
          );
        }
      }
    }
  }

  /// 初始化 LSP 客户端
  Future<void> initialize({String? rootUri}) async {
    _debugLog('[LSP] Starting initialization...');

    try {
      _debugLog('[LSP] Sending initialize request...');
      final result =
          await sendRequest('initialize', {
            'processId': pid,
            'rootUri': rootUri,
            'initializationOptions': {}, // 添加初始化选项
            'capabilities': {
              'textDocument': {
                'hover': {
                  'contentFormat': ['markdown', 'plaintext'],
                },
                'completion': {
                  'completionItem': {
                    'snippetSupport': true,
                    'resolveSupport': {
                      'properties': [
                        'documentation',
                        'detail',
                        'additionalTextEdits',
                      ],
                    },
                  },
                },
                'documentHighlight': {},
                'semanticTokens': {
                  'dynamicRegistration': false,
                  'requests': {
                    'range': true,
                    'full': {'delta': true},
                  },
                  'tokenTypes': _kSemanticTokenTypes,
                  'tokenModifiers': _kSemanticTokenModifiers,
                  'formats': ['relative'],
                  'multilineTokenSupport': true,
                  'overlappingTokenSupport': false,
                },
                'synchronization': {
                  'dynamicRegistration': false,
                  'didSave': true,
                },
              },
              'workspace': {
                'workspaceFolders': {
                  'supported': true,
                  'changeNotifications': true,
                },
              },
            },
          }).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException('LSP server initialization timed out.');
            },
          );

      _debugLog('[LSP] Initialize response received');

      _applyServerCapabilities(result);
      _debugLog('[LSP] Server capabilities applied');

      sendNotification('initialized', {});
      _debugLog('[LSP] Initialized notification sent');

      await Future.delayed(Duration(milliseconds: 200));
      _debugLog('[LSP] Initialization completed successfully');
    } catch (e) {
      _debugLog('[LSP] Initialization failed: $e');
      await close();
      rethrow;
    }
  }

  void _handleIncomingMessage(Map<String, dynamic> message) {
    if (message.containsKey('id')) {
      final idValue = message['id'];
      _debugLog('[LSP] Received response for id: $idValue');
      if (message.containsKey('result')) {
        _debugLog(
          '[LSP] Response result type: ${message['result'].runtimeType}',
        );
      }
      if (idValue is int) {
        final completer = _pendingRequests.remove(idValue);
        if (completer != null) {
          _debugLog('[LSP] Completer found for id: $idValue, completing...');
          if (message.containsKey('result')) {
            completer.complete(message['result']);
          } else if (message.containsKey('error')) {
            completer.completeError(message['error']);
          }
        } else {
          _debugLog('[LSP] No completer found for id: $idValue');
        }
      }
    } else if (message.containsKey('method')) {
      final method = message['method'] as String;
      _debugLog('[LSP] Received notification: $method');
      _notificationsController.add(message);
    }
  }

  /// 发送请求并等待响应
  Future<dynamic> sendRequest(String method, [dynamic params]) async {
    if (_closed || !_isListening) {
      throw StateError('Client not initialized');
    }

    final id = ++_id;
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;

    try {
      // 构造请求消息
      final request = {
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
      };

      // 直接发送 JSON 字符串
      _socket.add(jsonEncode(request));

      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _debugLog('[LSP Client] Request timed out: $method');
          _debugLog('[LSP Client] Pending requests: ${_pendingRequests.keys}');
          _debugLog(
            '[LSP Client] Client state: closed=$_closed, listening=$_isListening',
          );
          throw TimeoutException('LSP request timed out: $method');
        },
      );
    } catch (e) {
      _pendingRequests.remove(id);
      rethrow;
    }
  }

  /// 发送通知（不等待响应）
  void sendNotification(String method, [dynamic params]) {
    if (_closed || !_isListening) {
      throw StateError('Client not initialized');
    }

    // 构造通知消息
    final notification = {
      'jsonrpc': '2.0',
      'method': method,
      'params': ?params,
    };

    try {
      // 直接发送 JSON 字符串
      _socket.add(jsonEncode(notification));
    } catch (e) {
      _debugLog('[LSP Client] Failed to send notification: $method, error: $e');
    }
  }

  /// 监听来自服务器的通知
  Stream<Map<String, dynamic>> get notifications =>
      _notificationsController.stream;

  /// 关闭客户端
  Future<void> close() async {
    _debugLog('[LSP Client] Closing LSP client');
    _debugLog('[LSP Client] Close called from: ${StackTrace.current}');

    if (_closed) return;
    _closed = true;
    _isListening = false;

    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('LSP client closed'));
      }
    }
    _pendingRequests.clear();

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    await _incomingSubscription?.cancel();
    await _notificationsController.close();
    await _socket.close();
  }

  void _closeInternal() {
    _debugLog('[LSP Client] Internal close called');
    _debugLog('[LSP Client] Close called from: ${StackTrace.current}');

    if (_closed) return;
    _closed = true;
    _isListening = false;

    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('LSP client closed'));
      }
    }
    _pendingRequests.clear();

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _incomingSubscription?.cancel();
    _notificationsController.close();
    _socket.close();
  }
}

// 以下常量与原始代码完全相同，保留
const List<String> _kSemanticTokenTypes = [
  'namespace',
  'type',
  'class',
  'enum',
  'interface',
  'struct',
  'typeParameter',
  'parameter',
  'variable',
  'property',
  'enumMember',
  'event',
  'function',
  'method',
  'macro',
  'keyword',
  'modifier',
  'comment',
  'string',
  'number',
  'regexp',
  'operator',
  'decorator',
];

const List<String> _kSemanticTokenModifiers = [
  'declaration',
  'definition',
  'readonly',
  'static',
  'deprecated',
  'abstract',
  'async',
  'modification',
  'documentation',
  'defaultLibrary',
];
