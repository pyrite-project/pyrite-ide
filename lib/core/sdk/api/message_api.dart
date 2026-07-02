import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';

abstract class SdkMessageCommands {
  static const String show = 'sdk.message.show';
}

class SdkMessageApi extends StateNotifier<PluginRunManager?> {
  SdkMessageApi(this.ref) : super(null);

  final Ref ref;

  void bind(PluginRunManager runManager) {
    state = runManager;
    runManager.registerHandler(SdkMessageCommands.show, _handleShow);
  }

  void _respondOk(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond, {
    dynamic data,
  }) {
    respond({
      'version': '0.0',
      'id': '',
      'type': 'sdk.response.ok',
      'payload': {'data': data},
      'reply_to': envelope['id'],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _handleShow(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final type = payload['type']?.toString() ?? 'info';
    final message = payload['message']?.toString() ?? '';
    if (message.isEmpty) {
      _respondOk(envelope, respond, data: false);
      return;
    }

    final messageType = _parseType(type);
    ref.read(ideMessageProvider.notifier).show(message, type: messageType);
    _logFallback(type, message);
    _respondOk(envelope, respond, data: true);
  }

  IdeMessageType _parseType(String type) {
    return switch (type) {
      'success' => IdeMessageType.success,
      'warning' => IdeMessageType.warning,
      'error' => IdeMessageType.error,
      _ => IdeMessageType.info,
    };
  }

  void _logFallback(String type, String message) {
    ref.read(ideOutputLogProvider.notifier).add(
          IdeOutputSource.plugin,
          '[${state?.pluginId ?? 'plugin'}][$type] $message',
        );
  }

  @override
  void dispose() {
    state?.unregisterHandler(SdkMessageCommands.show);
    super.dispose();
  }
}

final StateNotifierProvider<SdkMessageApi, PluginRunManager?>
    sdkMessageApiProvider = StateNotifierProvider((ref) => SdkMessageApi(ref));
