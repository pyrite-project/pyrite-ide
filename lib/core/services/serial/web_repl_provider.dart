import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';
import 'package:pyrite_ide/core/services/settings.dart';

enum WebReplState { disconnected, waitingPassword, connected, error }

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
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  SerialByteQueue? _executionQueue;
  String _password = '';

  WebReplNotifier(this.ref) : super(const WebReplInfo());

  bool get isConnected => state.state == WebReplState.connected;

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
      final uri = Uri.parse('ws://$host:$port');
      _channel = WebSocketChannel.connect(uri);
      state = state.copyWith(state: WebReplState.waitingPassword);

      _subscription = _channel!.stream.listen(
        (data) {
          final text = data is String ? data : utf8.decode(data);
          _handleMessage(text);
        },
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

  void _handleMessage(String text) {
    final executionQueue = _executionQueue;
    if (executionQueue != null) {
      executionQueue.add(Uint8List.fromList(utf8.encode(text)));
      return;
    }
    if (state.state == WebReplState.waitingPassword) {
      if (text.contains('Password') || text.contains('password')) {
        _channel?.sink.add('$_password\n');
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
    _channel!.sink.add(command);
  }

  void sendText(String text) {
    if (!isConnected || _channel == null) return;
    _channel!.sink.add(text);
  }

  Future<void> executeStreaming(
    String source, {
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
      channel.sink.add(utf8.decode(bytes, allowMalformed: true));
    }

    final session = DeviceSession(queue: queue, writeBytes: writeBytes);
    final mode = ref.read(replModeProvider);
    var enteredRepl = false;
    try {
      writeBytes(const [0x03, 0x03]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await session.enterRepl(mode);
      enteredRepl = true;
      await session.executeStreaming(
        source,
        mode: mode,
        onStarted: onStarted,
        onStdout: onStdout,
        onStderr: onStderr,
      );
    } finally {
      if (enteredRepl && !queue.isCancelled) {
        try {
          await session.exitRepl(mode);
          if (mode == ReplMode.rawRepl) {
            queue.clear();
            writeBytes(const [0x02]);
            try {
              await queue.readUntil(
                utf8.encode('>>>'),
                const Duration(seconds: 2),
              );
            } catch (_) {}
          }
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
    _executionQueue?.cancel();
    _executionQueue = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}

final webReplProvider = StateNotifierProvider<WebReplNotifier, WebReplInfo>((
  ref,
) {
  return WebReplNotifier(ref);
});
