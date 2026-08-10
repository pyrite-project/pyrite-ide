import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_file_protocol.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_socket.dart';
import 'package:pyrite_ide/core/services/settings.dart';

enum WebReplState { disconnected, waitingPassword, connected, error }

Uri buildWebReplUri(String host, int defaultPort) {
  final value = host.trim();
  if (value.isEmpty) throw const FormatException('WebREPL host is empty');

  final parsed = value.contains('://')
      ? Uri.parse(value)
      : Uri.parse('ws://$value');
  if (parsed.host.isEmpty) {
    throw FormatException('Invalid WebREPL host: $host');
  }

  // WebREPL normally uses an unencrypted websocket, even when the host was
  // copied from an HTTP(S) device page.
  return Uri(
    scheme: 'ws',
    host: parsed.host,
    port: parsed.hasPort ? parsed.port : defaultPort,
    path: parsed.path.isEmpty || parsed.path == '/' ? '/' : parsed.path,
  );
}

class WebReplInfo {
  final WebReplState state;
  final String? errorMessage;

  const WebReplInfo({
    this.state = WebReplState.disconnected,
    this.errorMessage,
  });

  WebReplInfo copyWith({WebReplState? state, String? errorMessage}) {
    return WebReplInfo(state: state ?? this.state, errorMessage: errorMessage);
  }
}

class WebReplNotifier extends StateNotifier<WebReplInfo> {
  final Ref ref;
  WebReplSocket? _channel;
  StreamSubscription? _subscription;
  ProviderSubscription<SerialProviderState>? _serialSubscription;
  SerialByteQueue? _executionQueue;
  SerialByteQueue? _fileTransferQueue;
  String _password = '';
  bool _serialDisconnectInProgress = false;

  WebReplNotifier(this.ref) : super(const WebReplInfo()) {
    _serialSubscription = ref.listen<SerialProviderState>(serialProvider, (
      _,
      next,
    ) {
      if (isActive && next.isConnected) {
        unawaited(_disableSerialTransport());
      }
    });
  }

  bool get isConnected => state.state == WebReplState.connected;

  bool get isActive =>
      state.state == WebReplState.waitingPassword || isConnected;

  Future<void> _disableSerialTransport() async {
    if (_serialDisconnectInProgress) return;
    _serialDisconnectInProgress = true;
    try {
      final serialNotifier = ref.read(serialProvider.notifier);
      serialNotifier.cancelReconnect();
      if (ref.read(serialProvider).isConnected) {
        await serialNotifier.disconnectPort();
      }
    } finally {
      _serialDisconnectInProgress = false;
    }
  }

  Future<void> connect() async {
    if (_channel != null) await disconnect();

    final host = ref.read(webReplHost);
    final port = ref.read(webReplPort);
    _password = ref.read(webReplPassword);

    if (host.isEmpty) {
      state = WebReplInfo(
        state: WebReplState.error,
        errorMessage: translate(ref, I18nKey.webReplEmptyHost),
      );
      return;
    }

    try {
      await _disableSerialTransport();
      final uri = buildWebReplUri(host, port);
      state = state.copyWith(state: WebReplState.waitingPassword);
      final channel = await WebReplSocket.connect(uri);
      if (state.state == WebReplState.disconnected) {
        await channel.close();
        return;
      }
      _channel = channel;
      if (!identical(_channel, channel) ||
          state.state == WebReplState.disconnected) {
        return;
      }

      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (error) {
          state = WebReplInfo(
            state: WebReplState.error,
            errorMessage: translateWithReplacements(
              ref,
              I18nKey.webReplConnectFailed,
              {'error': '$error'},
            ),
          );
          _cleanup();
        },
        onDone: () {
          if (state.state != WebReplState.disconnected) {
            state = WebReplInfo(
              state: WebReplState.error,
              errorMessage: translate(ref, I18nKey.webReplDisconnected),
            );
          }
          _cleanup();
        },
      );
    } catch (e) {
      if (state.state == WebReplState.disconnected) return;
      state = WebReplInfo(
        state: WebReplState.error,
        errorMessage: translateWithReplacements(
          ref,
          I18nKey.webReplConnectFailed,
          {'error': '$e'},
        ),
      );
      _cleanup();
    }
  }

  void _handleMessage(Object data) {
    final isBinaryFrame = data is! String;
    final bytes = data is String
        ? Uint8List.fromList(utf8.encode(data))
        : Uint8List.fromList(data as List<int>);
    final fileTransferQueue = _fileTransferQueue;
    if (fileTransferQueue != null) {
      fileTransferQueue.add(bytes);
      return;
    }
    final executionQueue = _executionQueue;
    if (executionQueue != null) {
      executionQueue.add(bytes);
      return;
    }
    // Binary frames are reserved for the WebREPL file protocol. If a failed
    // transfer is still draining, never render its WB header/file bytes as
    // user-facing REPL output.
    if (isBinaryFrame) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    if (state.state == WebReplState.waitingPassword) {
      if (text.contains('Password') || text.contains('password')) {
        _channel?.sendText('$_password\n');
      } else if (text.contains('>>>') || text.contains('OK')) {
        state = state.copyWith(state: WebReplState.connected);
        writeReplOutput(text);
        sendText('\x03');
      } else {
        writeReplOutput(text);
      }
    } else if (state.state == WebReplState.connected) {
      writeReplOutput(text);
    }
  }

  void sendCommand(String command) {
    if (!isConnected || _channel == null) return;
    _channel!.sendText(command);
  }

  void sendText(String text) {
    if (!isConnected || _channel == null) return;
    _channel!.sendText(text);
  }

  Future<void> putFile(
    String path,
    Uint8List data, {
    void Function(int sent, int total)? onProgress,
  }) {
    return _runFileTransfer((channel, queue) async {
      final request = buildWebReplFileRequest(
        operation: WebReplFileOperation.put,
        path: path,
        fileSize: data.length,
      );
      await channel.sendBinary(request.sublist(0, 10));
      await channel.sendBinary(request.sublist(10));
      await _expectFileResponse(queue);

      onProgress?.call(0, data.length);
      var offset = 0;
      while (offset < data.length) {
        final end = offset + 1024 < data.length ? offset + 1024 : data.length;
        await channel.sendBinary(data.sublist(offset, end));
        offset = end;
        onProgress?.call(offset, data.length);
      }
      await _expectFileResponse(queue);
    });
  }

  Future<Uint8List> getFile(
    String path, {
    int? expectedSize,
    void Function(int received, int total)? onProgress,
  }) {
    return _runFileTransfer((channel, queue) async {
      final request = buildWebReplFileRequest(
        operation: WebReplFileOperation.get,
        path: path,
        fileSize: 0,
      );
      await channel.sendBinary(request);
      await _expectFileResponse(queue);

      final result = BytesBuilder(copy: false);
      var received = 0;
      onProgress?.call(0, expectedSize ?? 0);
      while (true) {
        await channel.sendBinary(const [0]);
        final sizeBytes = await queue.readBytes(2, const Duration(seconds: 60));
        final blockSize = ByteData.sublistView(
          sizeBytes,
        ).getUint16(0, Endian.little);
        if (blockSize == 0) break;
        final block = await queue.readBytes(
          blockSize,
          const Duration(seconds: 60),
        );
        result.add(block);
        received += block.length;
        onProgress?.call(received, expectedSize ?? received);
      }
      await _expectFileResponse(queue);
      final bytes = result.takeBytes();
      if (expectedSize != null && bytes.length != expectedSize) {
        throw WebReplFileProtocolException(
          'Downloaded ${bytes.length} bytes, expected $expectedSize.',
        );
      }
      return bytes;
    });
  }

  Future<T> _runFileTransfer<T>(
    Future<T> Function(WebReplSocket channel, SerialByteQueue queue) action,
  ) {
    return ref.read(replMutexProvider).runExclusive(() async {
      final channel = _channel;
      if (!isConnected || channel == null) {
        throw StateError('WebREPL is not connected.');
      }

      final queue = SerialByteQueue();
      _fileTransferQueue = queue;
      try {
        channel.sendText('\x03\x02\x03');
        await queue.readUntil(utf8.encode('>>>'), const Duration(seconds: 5));
        // A prompt can arrive before trailing echo/output from the interrupt
        // handshake. Let the socket drain it before issuing a binary request.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        queue.clear();
        return await action(channel, queue);
      } finally {
        if (identical(_fileTransferQueue, queue)) _fileTransferQueue = null;
        queue.cancel();
        if (isConnected) channel.sendText('\x03');
      }
    });
  }

  Future<void> _expectFileResponse(SerialByteQueue queue) async {
    final response = await queue.readBytes(4, const Duration(seconds: 60));
    int status;
    try {
      status = parseWebReplFileResponse(response);
    } on WebReplFileProtocolException catch (error) {
      final hex = response
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      throw WebReplFileProtocolException('$error Received bytes: $hex.');
    }
    if (status != 0) {
      throw WebReplFileProtocolException(
        'WebREPL file operation failed with status $status.',
      );
    }
  }

  Future<void> executeStreaming(
    String source, {
    Duration timeout = const Duration(seconds: 20),
    required void Function() onStarted,
    required void Function(Uint8List data) onStdout,
    required void Function(Uint8List data) onStderr,
  }) {
    return ref
        .read(replMutexProvider)
        .runExclusive(
          () => _executeStreaming(
            source,
            timeout: timeout,
            onStarted: onStarted,
            onStdout: onStdout,
            onStderr: onStderr,
          ),
        );
  }

  Future<void> _executeStreaming(
    String source, {
    required Duration timeout,
    required void Function() onStarted,
    required void Function(Uint8List data) onStdout,
    required void Function(Uint8List data) onStderr,
  }) async {
    final channel = _channel;
    if (!isConnected || channel == null) {
      throw StateError('WebREPL is not connected.');
    }
    if (_executionQueue != null) {
      throw StateError('A WebREPL execution is already active.');
    }

    final queue = SerialByteQueue();
    _executionQueue = queue;
    void writeBytes(List<int> bytes) {
      channel.sendText(utf8.decode(bytes, allowMalformed: true));
    }

    final session = DeviceSession(
      queue: queue,
      writeBytes: writeBytes,
      waitForPasteEcho: true,
    );
    // Thonny also forces normal paste mode for WebREPL. Raw REPL over Wi-Fi is
    // unreliable on ESP-class boards unless every write is heavily delayed.
    const mode = ReplMode.paste;
    var enteredRepl = false;
    var completed = false;
    try {
      writeBytes(const [0x03, 0x02, 0x03]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await session.enterRepl(mode);
      enteredRepl = true;
      await session.executeStreaming(
        source,
        timeout: timeout,
        mode: mode,
        onStarted: onStarted,
        onStdout: onStdout,
        onStderr: onStderr,
      );
      completed = true;
    } finally {
      if (enteredRepl && !completed && !queue.isCancelled) {
        try {
          await session.exitRepl(mode);
        } catch (_) {}
      }
      if (identical(_executionQueue, queue)) _executionQueue = null;
      queue.cancel();
    }
  }

  Future<void> disconnect() async {
    state = const WebReplInfo(state: WebReplState.disconnected);
    _cleanup();
  }

  void _cleanup() {
    _fileTransferQueue?.cancel();
    _fileTransferQueue = null;
    _executionQueue?.cancel();
    _executionQueue = null;
    _subscription?.cancel();
    _subscription = null;
    unawaited(_channel?.close());
    _channel = null;
  }

  @override
  void dispose() {
    _serialSubscription?.close();
    _serialSubscription = null;
    _cleanup();
    super.dispose();
  }
}

final webReplProvider = StateNotifierProvider<WebReplNotifier, WebReplInfo>((
  ref,
) {
  return WebReplNotifier(ref);
});
