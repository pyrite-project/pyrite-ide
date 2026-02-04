import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/pylsp/protocol.dart';
import 'package:stream_channel/stream_channel.dart';

Future<Process> startLspServer() async {
  print('[LSP] Starting Python LSP Server...');
  final process = await Process.start('python', ['-m', 'pylsp']);

  print('[LSP] Process started with PID: ${process.pid}');

  // 监听服务器的标准错误输出，这对于调试至关重要
  process.stderr.transform(utf8.decoder).listen((data) {
    print('[LSP Server stderr]: $data');
  });

  return process;
}

class LspClient {
  final Process _process;
  final StreamController<Map<String, dynamic>> _notificationsController =
      StreamController.broadcast();

  // 用于存储挂起的请求，以便匹配响应
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  int _id = 0;
  bool _isListening = false;

  LspClient(this._process);

  void _writeLspMessage(Map<String, dynamic> message) {
    _process.stdin.add(encodeLspMessage(message));
  }

  /// 初始化 LSP 客户端
  Future<void> initialize() async {
    try {
      // 创建用于通信的 StreamChannel
      final channel = _createStreamChannel();

      // 【关键修改】我们不再使用 json_rpc.Peer，而是直接监听流
      _isListening = true;

      // 监听来自服务器的消息
      channel.stream.listen(
        (message) {
          print('[LSP Client] Received message: $message');
          _handleIncomingMessage(message);
        },
        onError: (error) {
          print('[LSP Client] Stream error: $error');
        },
        onDone: () {
          print('[LSP Client] Stream done.');
          _isListening = false;
        },
        cancelOnError: false,
      );

      // 发送初始化请求
      final result =
          await sendRequest('initialize', {
            'processId': pid,
            'rootUri': null,
            'capabilities': {
              'textDocument': {
                'hover': {
                  'contentFormat': ['markdown', 'plaintext'],
                },
                'completion': {
                  'completionItem': {'snippetSupport': true},
                },
                "textDocumentSync": {
                  "change": 1,
                  "save": {"includeText": true},
                  "openClose": true,
                },
              },
            },
          }).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException('LSP server initialization timed out.');
            },
          );

      // 初始化完成后，发送 initialized 通知
      sendNotification('initialized');

      return result;
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
      final id = message['id'] as int;
      final completer = _pendingRequests[id];
      if (completer != null) {
        _pendingRequests.remove(id);
        if (message.containsKey('result')) {
          completer.complete(message['result']);
        } else if (message.containsKey('error')) {
          completer.completeError(message['error']);
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
    if (!_isListening) {
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

      print('[LSP Client] Sending request: $request');

      // 通过 LSP framing 发送（Content-Length 必须按 UTF-8 字节数计算）
      _writeLspMessage(request);
      print('[LSP Client] Request sent successfully.');

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
    if (!_isListening) {
      throw StateError('Client not initialized');
    }

    // 构造通知消息
    final notification = {
      'jsonrpc': '2.0',
      'method': method,
      if (params != null) 'params': params,
    };

    print('[LSP Client] Sending notification: $notification');

    // 通过 LSP framing 发送（Content-Length 必须按 UTF-8 字节数计算）
    _writeLspMessage(notification);
    print('[LSP Client] Notification sent successfully.');
  }

  /// 监听来自服务器的通知
  Stream<Map<String, dynamic>> get notifications =>
      _notificationsController.stream;

  /// 关闭客户端
  Future<void> close() async {
    _isListening = false;
    _process.kill();
  }

  /// 创建用于进程间通信的 StreamChannel
  StreamChannel<Map<String, dynamic>> _createStreamChannel() {
    // 输入流：从服务器的 stdout 读取数据
    final inputStream = _process.stdout
        .transform(const _ByteLspMessageTransformer())
        .transform(utf8.decoder)
        .transform(const _JsonDecoder())
        .where((data) => data.isNotEmpty);

    // 【修改】输出流：创建一个中间的 StreamController，类型为 Map<String, dynamic>
    final outputStreamController = StreamController<Map<String, dynamic>>();

    // 监听中间控制器的流，将数据转发给服务器的 stdin
    outputStreamController.stream.listen(
      (data) {
        print('[LSP Client] Sending to server: $data');
        // 将 Map<String, dynamic> 以 LSP framing 发送给服务器
        _writeLspMessage(data);
        print('[LSP Client] Sent successfully.');
      },
      onDone: () {
        print('[LSP Client] Output stream done, closing stdin...');
        _process.stdin.close();
      },
      onError: (error) {
        print('[LSP Client] Output stream error: $error');
        _process.stdin.addError(error);
      },
      cancelOnError: false,
    );

    // 返回 StreamChannel，使用中间控制器的 sink
    return StreamChannel<Map<String, dynamic>>(
      inputStream,
      outputStreamController.sink,
    );
  }
}

/// 用于处理 LSP 协议消息的字节流转换器
class _ByteLspMessageTransformer
    extends StreamTransformerBase<List<int>, List<int>> {
  const _ByteLspMessageTransformer();

  @override
  Stream<List<int>> bind(Stream<List<int>> stream) {
    final controller = StreamController<List<int>>();

    // 使用 List<int> 作为缓冲区，手动管理索引
    List<int> buffer = [];
    int contentLength = 0;
    bool readingHeader = true;

    stream.listen(
      (data) {
        print('[LSP Client] Received ${data.length} bytes from server.');

        // 将新数据追加到缓冲区
        buffer.addAll(data);

        while (buffer.isNotEmpty) {
          if (readingHeader) {
            // 查找头部结束标记 \r\n\r\n (字节值为 13, 10, 13, 10)
            int headerEnd = -1;
            for (int i = 0; i <= buffer.length - 4; i++) {
              if (buffer[i] == 13 &&
                  buffer[i + 1] == 10 &&
                  buffer[i + 2] == 13 &&
                  buffer[i + 3] == 10) {
                headerEnd = i;
                break;
              }
            }

            if (headerEnd == -1) {
              // 头部还未完整接收，跳出循环等待更多数据
              print('[LSP Client] Header incomplete, waiting for more data...');
              return;
            }

            // 解析 Content-Length
            // 将头部字节转换为字符串以便解析
            final headerStr = ascii.decode(
              buffer.sublist(0, headerEnd),
              allowInvalid: true,
            );
            print('[LSP Client] Parsed header: $headerStr');

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
            print('[LSP Client] Content-Length: $contentLength');

            // 直接修改原列表，移除已处理的头部（包括 \r\n\r\n）
            buffer.removeRange(0, headerEnd + 4);

            readingHeader = false;
          } else {
            // 检查缓冲区中的字节数是否足够
            if (buffer.length < contentLength) {
              // 数据还未完整接收，跳出循环等待更多数据
              print(
                '[LSP Client] Body incomplete (${buffer.length}/$contentLength), waiting...',
              );
              return;
            }

            // 提取消息体，并直接修改原列表移除已处理部分
            final messageBytes = buffer.sublist(0, contentLength);
            print('[LSP Client] Received complete message ($contentLength bytes).');

            controller.add(messageBytes);

            // 移除已处理的消息体
            buffer.removeRange(0, contentLength);

            readingHeader = true;
          }
        }
      },
      onError: controller.addError,
      onDone: controller.close,
      cancelOnError: true,
    );

    return controller.stream;
  }
}

/// 将 IOSink 适配为 StreamSink<String> 的包装器
class _IOSinkWrapper implements StreamSink<String> {
  final IOSink _ioSink;
  bool _closed = false;

  _IOSinkWrapper(this._ioSink);

  @override
  void add(String data) {
    if (_closed) {
      print('[LSP Client] Warning: Attempting to write to closed sink.');
      return;
    }
    print('[LSP Client] Sending to server: $data');
    // 将字符串编码为字节并写入 IOSink
    _ioSink.add(utf8.encode(data));
    print('[LSP Client] Sent successfully.');
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_closed) return;
    print('[LSP Client] Sink error: $error');
    _ioSink.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<String> stream) {
    if (_closed) return Future.value();
    return stream.forEach(add);
  }

  @override
  Future<void> close() {
    if (_closed) return Future.value();
    _closed = true;
    print('[LSP Client] Closing sink...');
    return _ioSink.close();
  }

  @override
  Future<void> get done => _ioSink.done;
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
        print('[LSP Client] Failed to decode JSON: $jsonString, Error: $e');
        rethrow;
      }
    });
  }
}
