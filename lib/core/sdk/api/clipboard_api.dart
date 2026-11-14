import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/api/sdk_response.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';

abstract class SdkClipboardCommands {
  static const String setText = 'sdk.clipboard.set_text';
}

class SdkClipboardApi {
  SdkClipboardApi(this.ref);

  final Ref ref;

  void bind(PluginRunManager runManager) {
    runManager.registerHandler(SdkClipboardCommands.setText, _handleSetText);
  }

  void _handleSetText(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final text = payload['text']?.toString() ?? '';
    if (text.isEmpty) {
      respondOk(envelope, respond, data: false);
      return;
    }
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      respondOk(envelope, respond, data: true);
    });
  }
}

final Provider<SdkClipboardApi> sdkClipboardApiProvider = Provider(
  SdkClipboardApi.new,
);
