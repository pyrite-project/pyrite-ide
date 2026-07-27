import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/settings.dart';

enum WebReplState { disconnected, waitingPassword, connected, error }

class WebReplInfo {
  final WebReplState state;
  final String? errorMessage;

  const WebReplInfo({this.state = WebReplState.disconnected, this.errorMessage});

  WebReplInfo copyWith({WebReplState? state, String? errorMessage}) {
    return WebReplInfo(
      state: state ?? this.state,
      errorMessage: errorMessage,
    );
  }
}

class WebReplNotifier extends StateNotifier<WebReplInfo> {
  final Ref ref;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
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
                ref, I18nKey.webReplConnectFailed, {'error': '$error'}),
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
            ref, I18nKey.webReplConnectFailed, {'error': '$e'}),
      );
      _cleanup();
    }
  }

  void _handleMessage(String text) {
    if (state.state == WebReplState.waitingPassword) {
      if (text.contains('Password') || text.contains('password')) {
        _channel?.sink.add('$_password\n');
      } else if (text.contains('>>>') || text.contains('OK')) {
        state = state.copyWith(state: WebReplState.connected);
        repl.write(text);
      } else {
        repl.write(text);
      }
    } else if (state.state == WebReplState.connected) {
      repl.write(text);
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

  Future<void> disconnect() async {
    state = const WebReplInfo(state: WebReplState.disconnected);
    _cleanup();
  }

  void _cleanup() {
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

final webReplProvider =
    StateNotifierProvider<WebReplNotifier, WebReplInfo>((ref) {
  return WebReplNotifier(ref);
});
