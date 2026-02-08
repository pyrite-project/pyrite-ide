import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:pyrite_ide/core/services/android_env_deployer/core.dart';
import 'package:pyrite_ide/core/services/pylsp/protocol.dart';

void _debugLog(String message) {
  assert(() {
    // ignore: avoid_print
    print(message);
    return true;
  }());
}

typedef _LspLaunch = ({String executable, List<String> arguments});

List<_LspLaunch> _lspLaunchCandidates() {
  final envPylsp = Platform.environment['PYRITE_IDE_PYLSP']?.trim();
  final envPython = Platform.environment['PYRITE_IDE_PYTHON']?.trim();

  final candidates = <_LspLaunch>[
    if (envPylsp != null && envPylsp.isNotEmpty)
      (executable: envPylsp, arguments: const []),
    (executable: 'pylsp', arguments: const []),
  ];

  if (Platform.isMacOS) {
    candidates.addAll([
      (executable: '/opt/homebrew/bin/pylsp', arguments: const []),
      (executable: '/usr/local/bin/pylsp', arguments: const []),
    ]);
  }

  if (envPython != null && envPython.isNotEmpty) {
    candidates.add((executable: envPython, arguments: const ['-m', 'pylsp']));
  }

  if (Platform.isWindows) {
    candidates.addAll([
      (executable: 'py', arguments: const ['-m', 'pylsp']),
      (executable: 'python', arguments: const ['-m', 'pylsp']),
      (executable: 'python3', arguments: const ['-m', 'pylsp']),
    ]);
  } else {
    candidates.addAll([
      (executable: 'python3', arguments: const ['-m', 'pylsp']),
      (executable: 'python', arguments: const ['-m', 'pylsp']),
    ]);

    if (Platform.isMacOS) {
      candidates.addAll([
        (executable: '/usr/bin/python3', arguments: const ['-m', 'pylsp']),
        (
          executable: '/opt/homebrew/bin/python3',
          arguments: const ['-m', 'pylsp'],
        ),
        (
          executable: '/usr/local/bin/python3',
          arguments: const ['-m', 'pylsp'],
        ),
      ]);
    }
    if (Platform.isAndroid) {
      candidates.add((
        executable: pythonDeployer.pythonExecutable.path,
        arguments: const ['-m', 'pylsp'],
      ));
    }
  }

  final seen = <String>{};
  final deduped = <_LspLaunch>[];
  for (final candidate in candidates) {
    final key =
        '${candidate.executable}\u0000${candidate.arguments.join('\u0001')}';
    if (seen.add(key)) deduped.add(candidate);
  }

  return deduped;
}

Future<Process> startLspServer() async {
  _debugLog('[LSP] Starting Python LSP Server...');

  final errors = <String>[];
  for (final candidate in _lspLaunchCandidates()) {
    final printableArgs = candidate.arguments
        .map((a) => a.contains(' ') ? '"$a"' : a)
        .join(' ');
    final printableCommand = [
      candidate.executable.contains(' ')
          ? '"${candidate.executable}"'
          : candidate.executable,
      if (printableArgs.isNotEmpty) printableArgs,
    ].join(' ');

    try {
      final Process process;
      if (Platform.isAndroid) {
        process = await Process.start(
          candidate.executable,
          candidate.arguments,
          environment: pythonDeployer.env,
        );
      } else {
        process = await Process.start(
          candidate.executable,
          candidate.arguments,
        );
      }
      _debugLog('[LSP] Started using: $printableCommand (PID: ${process.pid})');

      // 监听服务器的标准错误输出，这对于调试至关重要
      process.stderr.listen((data) {
        assert(() {
          final text = utf8.decode(data, allowMalformed: true);
          _debugLog('[LSP Server stderr]: $text');
          return true;
        }());
      });

      return process;
    } catch (e) {
      errors.add('- $printableCommand: $e');
    }
  }

  throw StateError(
    'Unable to start Python LSP Server (pylsp).\n'
    'Tried:\n${errors.join('\n')}\n\n'
    'Fix:\n'
    '- Install Python 3 and python-lsp-server (pylsp), or\n'
    "- Set env vars 'PYRITE_IDE_PYTHON' or 'PYRITE_IDE_PYLSP' to an absolute path.",
  );
}

class LspClient {
  final Process _process;
  final StreamController<Map<String, dynamic>> _notificationsController =
      StreamController.broadcast();

  // 用于存储挂起的请求，以便匹配响应
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  int _id = 0;
  bool _isListening = false;
  bool _closed = false;
  StreamSubscription<Map<String, dynamic>>? _incomingSubscription;

  int _textDocumentSyncChange = 1;
  bool get supportsIncrementalSync => _textDocumentSyncChange == 2;

  List<String> _semanticTokenTypes = const [];
  List<String> _semanticTokenModifiers = const [];
  bool get supportsSemanticTokens => _semanticTokenTypes.isNotEmpty;
  List<String> get semanticTokenTypes => _semanticTokenTypes;
  List<String> get semanticTokenModifiers => _semanticTokenModifiers;

  LspClient(this._process);

  void _writeLspMessage(Map<String, dynamic> message) {
    _process.stdin.add(encodeLspMessage(message));
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
    if (_closed) {
      throw StateError('Client is closed');
    }

    try {
      // 【关键修改】我们不再使用 json_rpc.Peer，而是直接监听流
      _isListening = true;

      // 监听来自服务器的消息
      _incomingSubscription = _createIncomingStream().listen(
        _handleIncomingMessage,
        onError: (Object error, StackTrace stackTrace) {
          _debugLog('[LSP Client] Stream error: $error');
        },
        onDone: () {
          _debugLog('[LSP Client] Stream done.');
          _isListening = false;
        },
        cancelOnError: false,
      );

      // 发送初始化请求
      final result =
          await sendRequest('initialize', {
            'processId': pid,
            'rootUri': rootUri,
            'capabilities': {
              'textDocument': {
                'hover': {
                  'contentFormat': ['markdown', 'plaintext'],
                },
                'completion': {
                  'completionItem': {'snippetSupport': true},
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
            },
          }).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException('LSP server initialization timed out.');
            },
          );

      _applyServerCapabilities(result);

      // 初始化完成后，发送 initialized 通知
      sendNotification('initialized');
    } catch (e) {
      // 发生错误时关闭客户端，防止资源泄漏
      await close();
      rethrow; // 重新抛出错误，让调用者处理
    }
  }

  /// 处理来自服务器的消息
  void _handleIncomingMessage(Map<String, dynamic> message) {
    // 检查是否是响应
    if (message.containsKey('id')) {
      final idValue = message['id'];
      if (idValue is int) {
        final completer = _pendingRequests[idValue];
        if (completer != null) {
          _pendingRequests.remove(idValue);
          if (message.containsKey('result')) {
            completer.complete(message['result']);
          } else if (message.containsKey('error')) {
            completer.completeError(message['error']);
          }
        }
      }
    }
    // 否则是通知
    else if (message.containsKey('method')) {
      final method = message['method'] as String;
      final params = message['params'];

      // 将通知转发到通知流
      _notificationsController.add({'method': method, 'params': params});
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
        if (params != null) 'params': params,
      };

      // 通过 LSP framing 发送（Content-Length 必须按 UTF-8 字节数计算）
      _writeLspMessage(request);

      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
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
      if (params != null) 'params': params,
    };

    // 通过 LSP framing 发送（Content-Length 必须按 UTF-8 字节数计算）
    _writeLspMessage(notification);
  }

  /// 监听来自服务器的通知
  Stream<Map<String, dynamic>> get notifications =>
      _notificationsController.stream;

  /// 关闭客户端
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _isListening = false;

    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('LSP client closed'));
      }
    }
    _pendingRequests.clear();

    await _incomingSubscription?.cancel();
    await _notificationsController.close();
    _process.kill();
  }

  /// 来自服务器 stdout 的 LSP 消息流
  Stream<Map<String, dynamic>> _createIncomingStream() {
    return _process.stdout
        .transform(const _ByteLspMessageTransformer())
        .transform(utf8.decoder)
        .transform(const _JsonDecoder())
        .where((data) => data.isNotEmpty);
  }
}

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

/// 用于处理 LSP 协议消息的字节流转换器
class _ByteLspMessageTransformer
    extends StreamTransformerBase<List<int>, List<int>> {
  const _ByteLspMessageTransformer();

  @override
  Stream<List<int>> bind(Stream<List<int>> stream) {
    final controller = StreamController<List<int>>();

    // 使用 List<int> 作为缓冲区 + 读指针，避免频繁 removeRange 导致的 O(n) 拷贝。
    var buffer = <int>[];
    var readIndex = 0;
    var contentLength = 0;
    var readingHeader = true;

    void compactBufferIfNeeded() {
      if (readIndex == 0) return;
      if (readIndex >= buffer.length) {
        buffer = <int>[];
        readIndex = 0;
        return;
      }
      // 避免缓冲区无限增长
      if (readIndex > 8 * 1024 && readIndex > buffer.length ~/ 2) {
        buffer = buffer.sublist(readIndex);
        readIndex = 0;
      }
    }

    int indexOfHeaderEnd() {
      for (var i = readIndex; i <= buffer.length - 4; i++) {
        if (buffer[i] == 13 &&
            buffer[i + 1] == 10 &&
            buffer[i + 2] == 13 &&
            buffer[i + 3] == 10) {
          return i;
        }
      }
      return -1;
    }

    stream.listen(
      (data) {
        // 将新数据追加到缓冲区
        buffer.addAll(data);

        while (true) {
          if (readingHeader) {
            // 查找头部结束标记 \r\n\r\n (字节值为 13, 10, 13, 10)
            final headerEnd = indexOfHeaderEnd();

            if (headerEnd == -1) {
              compactBufferIfNeeded();
              break;
            }

            // 解析 Content-Length
            // 将头部字节转换为字符串以便解析
            final headerStr = ascii.decode(
              buffer.sublist(readIndex, headerEnd),
              allowInvalid: true,
            );

            final lengthMatch = RegExp(
              r'Content-Length: (\d+)',
            ).firstMatch(headerStr);

            if (lengthMatch == null) {
              controller.addError(
                'Invalid LSP message: missing Content-Length',
              );
              return;
            }

            contentLength = int.parse(lengthMatch.group(1)!);

            // 移动读指针越过 header（包括 \r\n\r\n）
            readIndex = headerEnd + 4;

            readingHeader = false;
          } else {
            // 检查缓冲区中的字节数是否足够
            if (buffer.length - readIndex < contentLength) {
              compactBufferIfNeeded();
              break;
            }

            // 提取消息体
            final endIndex = readIndex + contentLength;
            final messageBytes = buffer.sublist(readIndex, endIndex);

            controller.add(messageBytes);

            // 移动读指针
            readIndex = endIndex;

            readingHeader = true;
            compactBufferIfNeeded();
          }

          if (buffer.isEmpty) break;
        }
      },
      onError: controller.addError,
      onDone: controller.close,
      cancelOnError: true,
    );

    return controller.stream;
  }
}

/// 将 JSON 字符串流解码为 Map<String, dynamic> 对象流的转换器
class _JsonDecoder extends StreamTransformerBase<String, Map<String, dynamic>> {
  const _JsonDecoder();

  @override
  Stream<Map<String, dynamic>> bind(Stream<String> stream) {
    return stream.map((jsonString) {
      try {
        return jsonDecode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        _debugLog(
          '[LSP Client] Failed to decode JSON (len=${jsonString.length}): $e',
        );
        rethrow;
      }
    });
  }
}
