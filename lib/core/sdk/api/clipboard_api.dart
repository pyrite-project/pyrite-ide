import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';

abstract class SdkClipboardCommands {
  static const String setText = 'sdk.clipboard.set_text';
}

class SdkClipboardApi {
  SdkClipboardApi(this.ref);

  final Ref ref;

  void bind(PluginRunManager runManager) {
    runManager.registerHandler(
      SdkClipboardCommands.setText,
      (envelope, respond) => _handleSetText(envelope, respond),
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

  void _handleSetText(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final text = payload['text']?.toString() ?? '';
    if (text.isEmpty) {
      _respondOk(envelope, respond, data: false);
      return;
    }
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      _respondOk(envelope, respond, data: true);
    });
  }
}

final Provider<SdkClipboardApi> sdkClipboardApiProvider = Provider(
  SdkClipboardApi.new,
);
