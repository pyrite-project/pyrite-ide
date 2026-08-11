import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';

abstract interface class SdkDialogFilePicker {
  Future<String?> pickFolder({
    required String title,
    required String? initialDirectory,
  });

  Future<List<String?>?> pickFiles({
    required String title,
    required String? initialDirectory,
    required bool allowMultiple,
  });
}

class PlatformSdkDialogFilePicker implements SdkDialogFilePicker {
  const PlatformSdkDialogFilePicker();

  @override
  Future<String?> pickFolder({
    required String title,
    required String? initialDirectory,
  }) {
    return FilePicker.getDirectoryPath(
      dialogTitle: title,
      initialDirectory: initialDirectory,
      lockParentWindow: true,
    );
  }

  @override
  Future<List<String?>?> pickFiles({
    required String title,
    required String? initialDirectory,
    required bool allowMultiple,
  }) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: title,
      initialDirectory: initialDirectory,
      lockParentWindow: true,
      allowMultiple: allowMultiple,
    );
    return result?.paths;
  }
}

abstract class SdkDialogCommands {
  // File selection
  static const String openFolder = 'sdk.dialog.open_folder';
  static const String openFile = 'sdk.dialog.open_file';
  static const String openFiles = 'sdk.dialog.open_files';
}

class SdkDialog {
  final Ref ref;
  SdkDialog(this.ref);

  void bind(PluginRunManager runManager) {
    // File selection
    runManager.registerHandler(SdkDialogCommands.openFolder, _handleOpenFolder);
    runManager.registerHandler(SdkDialogCommands.openFile, _handleOpenFile);
    runManager.registerHandler(SdkDialogCommands.openFiles, _handleOpenFiles);
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
    final title =
        _stringOrNull(payload['title']) ??
        translate(ref, I18nKey.sdkDefaultOpenFolderTitle);
    final initialDirectory =
        _stringOrNull(payload['initial_directory']) ??
        _stringOrNull(payload['initialDirectory']) ??
        ref.read(fileProvider)?.path;

    try {
      final selectedPath = await ref
          .read(sdkDialogFilePickerProvider)
          .pickFolder(title: title, initialDirectory: initialDirectory);
      _respondOk(envelope, respond, data: selectedPath);
    } catch (error) {
      _respondError(envelope, respond, 'Cannot open file picker: $error');
    }
  }

  Future<void> _handleOpenFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final title =
        _stringOrNull(payload['title']) ??
        translate(ref, I18nKey.sdkDefaultOpenFileTitle);
    final initialDirectory =
        _stringOrNull(payload['initial_directory']) ??
        _stringOrNull(payload['initialDirectory']) ??
        ref.read(fileProvider)?.path;

    try {
      final selectedFiles = await ref
          .read(sdkDialogFilePickerProvider)
          .pickFiles(
            title: title,
            initialDirectory: initialDirectory,
            allowMultiple: false,
          );
      final selectedPath = selectedFiles?.whereType<String>().firstOrNull;
      _respondOk(envelope, respond, data: selectedPath);
    } catch (error) {
      _respondError(envelope, respond, 'Cannot open file picker: $error');
    }
  }

  Future<void> _handleOpenFiles(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final title =
        _stringOrNull(payload['title']) ??
        translate(ref, I18nKey.sdkDefaultOpenFilesTitle);
    final initialDirectory =
        _stringOrNull(payload['initial_directory']) ??
        _stringOrNull(payload['initialDirectory']) ??
        ref.read(fileProvider)?.path;

    try {
      final selectedFiles = await ref
          .read(sdkDialogFilePickerProvider)
          .pickFiles(
            title: title,
            initialDirectory: initialDirectory,
            allowMultiple: true,
          );
      final selectedPaths = selectedFiles?.whereType<String>().toList();
      _respondOk(envelope, respond, data: selectedPaths);
    } catch (error) {
      _respondError(envelope, respond, 'Cannot open file picker: $error');
    }
  }

  String? _stringOrNull(Object? value) {
    final string = value?.toString();
    if (string == null || string.isEmpty) return null;
    return string;
  }
}

final Provider<SdkDialog> sdkDialogProvider = Provider(SdkDialog.new);

final Provider<SdkDialogFilePicker> sdkDialogFilePickerProvider = Provider(
  (ref) => const PlatformSdkDialogFilePicker(),
);
