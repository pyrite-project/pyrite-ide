import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:file_picker/file_picker.dart';

abstract class SdkDialogCommands {
  // File selection
  static const String openFolder = 'sdk.dialog.open_folder';
}

class SdkDialog extends StateNotifier<PluginRunManager?> {
  final Ref ref;
  SdkDialog(this.ref) : super(null);

  void bind(PluginRunManager runManager) {
    state = runManager;

    // File selection
    runManager.registerHandler(SdkDialogCommands.openFolder, _handleOpenFolder);
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

  void _respondError(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    String message,
  ) {
    respond({
      'version': '0.0',
      'id': '',
      'type': 'sdk.response.error',
      'payload': {'message': message},
      'reply_to': envelope['id'],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── File selection ──

  Future<void> _handleOpenFolder(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final title = _stringOrNull(payload['title']) ?? '选择文件夹';
    final initialDirectory =
        _stringOrNull(payload['initial_directory']) ??
        _stringOrNull(payload['initialDirectory']) ??
        ref.read(fileProvider)?.path;

    try {
      final selectedPath = await FilePicker.getDirectoryPath(
        dialogTitle: title,
        initialDirectory: initialDirectory,
        lockParentWindow: true,
      );
      _respondOk(envelope, respond, data: selectedPath);
    } catch (error) {
      _respondError(envelope, respond, '打开文件夹选择器失败：$error');
    }
  }

  String? _stringOrNull(Object? value) {
    final string = value?.toString();
    if (string == null || string.isEmpty) return null;
    return string;
  }

  @override
  void dispose() {
    // Text Content
    state?.unregisterHandler(SdkDialogCommands.openFolder);
    super.dispose();
  }
}

final StateNotifierProvider<SdkDialog, PluginRunManager?> sdkDialogProvider =
    StateNotifierProvider((ref) => SdkDialog(ref));
