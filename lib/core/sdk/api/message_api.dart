import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';

abstract class SdkMessageCommands {
  static const String show = 'sdk.message.show';
}

class SdkMessageApi {
  SdkMessageApi(this.ref);

  final Ref ref;

  void bind(PluginRunManager runManager) {
    runManager.registerHandler(
      SdkMessageCommands.show,
      (envelope, respond) => _handleShow(runManager, envelope, respond),
    );
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
    PluginRunManager runManager,
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
    _logFallback(runManager.pluginId, type, message);
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

  void _logFallback(String pluginId, String type, String message) {
    ref
        .read(ideOutputLogProvider.notifier)
        .add(IdeOutputSource.plugin, '[$pluginId][$type] $message');
  }
}

final Provider<SdkMessageApi> sdkMessageApiProvider = Provider(
  SdkMessageApi.new,
);
