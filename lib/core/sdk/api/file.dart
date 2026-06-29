import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend_provider.dart';

abstract class SdkFileCommands {
  static const String getDirList = 'sdk.file.get_dir_list';
  static const String getRootDir = 'sdk.file.get_root_dir';
  static const String saveCurrentFile = 'sdk.file.save_current_file';
  static const String saveCurrentFileAs =
      'sdk.file.save_current_file_as';
  static const String createFile = 'sdk.file.create_file';
  static const String createFolder = 'sdk.file.create_folder';
  static const String getFocusFileNode =
      'sdk.file.get_focus_file_node';
  static const String getFocusFolderNode =
      'sdk.file.get_focus_folder_node';
  static const String openFile = 'sdk.file.open_file';
  static const String uploadSelectedLocalFileItem =
      'sdk.file.upload_selected_local_file_item';
  static const String rename = 'sdk.file.rename';
  static const String delete = 'sdk.file.delete';
  static const String openFolder = 'sdk.file.open_folder';
  static const String isFile = 'sdk.file.is_file';
  static const String isDirectory = 'sdk.file.is_directory';
  static const String readFile = 'sdk.file.read_file';
  static const String writeFile = 'sdk.file.write_file';
  static const String copyFile = 'sdk.file.copy_file';
  static const String moveFile = 'sdk.file.move_file';
  static const String exists = 'sdk.file.exists';
  static const String uploadFile = 'sdk.file.upload_file';
  static const String getUniqueName = 'sdk.file.get_unique_name';
}

class SdkFile extends StateNotifier<PluginRunManager?> {
  final Ref ref;
  SdkFile(this.ref) : super(null);

  void bind(PluginRunManager runManager) {
    state = runManager;
    runManager.registerHandler(
      SdkFileCommands.getDirList,
      _handleGetDirList,
    );
    runManager.registerHandler(
      SdkFileCommands.getRootDir,
      _handleGetRootDir,
    );
    runManager.registerHandler(
      SdkFileCommands.saveCurrentFile,
      _handleSaveCurrentFile,
    );
    runManager.registerHandler(
      SdkFileCommands.saveCurrentFileAs,
      _handleSaveCurrentFileAs,
    );
    runManager.registerHandler(
      SdkFileCommands.createFile,
      _handleCreateFile,
    );
    runManager.registerHandler(
      SdkFileCommands.createFolder,
      _handleCreateFolder,
    );
    runManager.registerHandler(
      SdkFileCommands.getFocusFileNode,
      _handleGetFocusFileNode,
    );
    runManager.registerHandler(
      SdkFileCommands.getFocusFolderNode,
      _handleGetFocusFolderNode,
    );
    runManager.registerHandler(
      SdkFileCommands.openFile,
      _handleOpenFile,
    );
    runManager.registerHandler(
      SdkFileCommands.uploadSelectedLocalFileItem,
      _handleUploadSelectedLocalFileItem,
    );
    runManager.registerHandler(SdkFileCommands.rename, _handleRename);
    runManager.registerHandler(SdkFileCommands.delete, _handleDelete);
    runManager.registerHandler(
      SdkFileCommands.openFolder,
      _handleOpenFolder,
    );
    runManager.registerHandler(SdkFileCommands.isFile, _handleIsFile);
    runManager.registerHandler(
      SdkFileCommands.isDirectory,
      _handleIsDirectory,
    );
    runManager.registerHandler(
      SdkFileCommands.readFile,
      _handleReadFile,
    );
    runManager.registerHandler(
      SdkFileCommands.writeFile,
      _handleWriteFile,
    );
    runManager.registerHandler(
      SdkFileCommands.copyFile,
      _handleCopyFile,
    );
    runManager.registerHandler(
      SdkFileCommands.moveFile,
      _handleMoveFile,
    );
    runManager.registerHandler(SdkFileCommands.exists, _handleExists);
    runManager.registerHandler(
      SdkFileCommands.uploadFile,
      _handleUploadFile,
    );
    runManager.registerHandler(
      SdkFileCommands.getUniqueName,
      _handleGetUniqueName,
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

  void _handleGetDirList(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final String? dirPath = envelope['data']?.toString();
    final List<String> entries = [];
    if (dirPath != null) {
      try {
        final dir = Directory(dirPath);
        if (dir.existsSync()) {
          for (final entity in dir.listSync()) {
            entries.add(entity.path);
          }
        }
      } catch (_) {}
    }

    _respondOk(envelope, respond, data: entries);
  }

  void _handleGetRootDir(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    _respondOk(envelope, respond, data: ref.read(fileProvider)?.path);
  }

  void _handleSaveCurrentFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    ref.read(fileProvider.notifier).saveCurrentFile();
    _respondOk(envelope, respond);
  }

  void _handleSaveCurrentFileAs(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    ref.read(fileProvider.notifier).saveCurrentFileAs();
    _respondOk(envelope, respond);
  }

  Future<void> _handleCreateFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();

    if (filePath == null) {
      _respondOk(envelope, respond, data: null);
      return;
    }

    final createdPath = await ref
        .read(fileProvider.notifier)
        .createFile(filePath);
    _respondOk(envelope, respond, data: {'path': createdPath});
  }

  Future<void> _handleCreateFolder(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final folderPath = payload['path']?.toString();

    if (folderPath == null) {
      _respondOk(envelope, respond, data: null);
      return;
    }

    final createdPath = await ref
        .read(fileProvider.notifier)
        .createFolder(folderPath);
    _respondOk(envelope, respond, data: {'path': createdPath});
  }

  void _handleGetFocusFileNode(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final node = ref.read(fileProvider.notifier).getFocusFileNode();
    _respondOk(
      envelope,
      respond,
      data: node != null ? {'path': node.id, 'name': node.data.name} : null,
    );
  }

  void _handleGetFocusFolderNode(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final node = ref.read(fileProvider.notifier).getFocusFolderNode();
    _respondOk(
      envelope,
      respond,
      data: node != null ? {'path': node.id, 'name': node.data.name} : null,
    );
  }

  Future<void> _handleOpenFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();
    if (filePath == null) {
      _respondOk(envelope, respond);
      return;
    }

    final file = File(filePath);
    if (file.existsSync()) {
      ref
          .read(fileProvider.notifier)
          .setDirectory(Directory(p.dirname(filePath)));

      final context = appContext;
      if (context != null && context.mounted) {
        await ref
            .read(tabbedViewControllerProvider.notifier)
            .openFile(context, file: file);
      }
    }
    _respondOk(envelope, respond);
  }

  Future<void> _handleUploadSelectedLocalFileItem(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final context = appContext;
    if (context != null && context.mounted) {
      await ref
          .read(fileProvider.notifier)
          .uploadSelectedLocalFileItem(context);
    }
    _respondOk(envelope, respond);
  }

  Future<void> _handleRename(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();
    final newName = payload['new_name']?.toString();

    if (filePath != null && newName != null) {
      final isDir = FileSystemEntity.isDirectorySync(filePath);
      if (isDir) {
        await local.renameDir(filePath, newName);
      } else {
        await local.renameFile(filePath, newName);
      }
    }
    _respondOk(envelope, respond);
  }

  Future<void> _handleDelete(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();

    if (filePath != null) {
      final isDir = FileSystemEntity.isDirectorySync(filePath);
      if (isDir) {
        await local.deleteDir(filePath);
      } else {
        await local.deleteFile(filePath);
      }
    }
    _respondOk(envelope, respond);
  }

  void _handleOpenFolder(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final folderPath = payload['path']?.toString();

    if (folderPath != null) {
      final dir = Directory(folderPath);
      if (dir.existsSync()) {
        ref.read(fileProvider.notifier).setDirectory(dir);
        ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
      }
    }
    _respondOk(envelope, respond);
  }

  void _handleIsDirectory(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();

    if (filePath != null) {
      final isDir = FileSystemEntity.isDirectorySync(filePath);
      _respondOk(envelope, respond, data: isDir);
    } else {
      _respondOk(envelope, respond, data: false);
    }
  }

  void _handleIsFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();

    if (filePath != null) {
      final isFile = FileSystemEntity.isFileSync(filePath);
      _respondOk(envelope, respond, data: isFile);
    } else {
      _respondOk(envelope, respond, data: false);
    }
  }

  Future<void> _handleReadFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();

    if (filePath != null) {
      try {
        final content = await File(filePath).readAsString();
        _respondOk(envelope, respond, data: content);
      } catch (e) {
        _respondOk(envelope, respond, data: null);
      }
    } else {
      _respondOk(envelope, respond, data: null);
    }
  }

  Future<void> _handleWriteFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();
    final content = payload['content']?.toString();

    if (filePath != null && content != null) {
      try {
        await File(filePath).writeAsString(content);
        _respondOk(envelope, respond, data: true);
      } catch (e) {
        _respondOk(envelope, respond, data: false);
      }
    } else {
      _respondOk(envelope, respond, data: false);
    }
  }

  Future<void> _handleCopyFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final src = payload['src']?.toString();
    final dst = payload['dst']?.toString();

    if (src != null && dst != null) {
      try {
        await File(src).copy(dst);
        _respondOk(envelope, respond, data: true);
      } catch (e) {
        _respondOk(envelope, respond, data: false);
      }
    } else {
      _respondOk(envelope, respond, data: false);
    }
  }

  Future<void> _handleMoveFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final src = payload['src']?.toString();
    final dst = payload['dst']?.toString();

    if (src != null && dst != null) {
      try {
        await File(src).rename(dst);
        _respondOk(envelope, respond, data: true);
      } catch (e) {
        _respondOk(envelope, respond, data: false);
      }
    } else {
      _respondOk(envelope, respond, data: false);
    }
  }

  void _handleExists(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();

    if (filePath != null) {
      final exists = File(filePath).existsSync();
      _respondOk(envelope, respond, data: exists);
    } else {
      _respondOk(envelope, respond, data: false);
    }
  }

  Future<void> _handleUploadFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final localPath = payload['local_path']?.toString();
    final boardPath = payload['board_path']?.toString();

    if (localPath != null && boardPath != null) {
      try {
        final bytes = await File(localPath).readAsBytes();
        await ref
            .read(boardFileBackendProvider)
            .writeFileBytes(boardPath, bytes);
        _respondOk(envelope, respond, data: true);
      } catch (e) {
        _respondOk(envelope, respond, data: false);
      }
    } else {
      _respondOk(envelope, respond, data: false);
    }
  }

  Future<void> _handleGetUniqueName(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final name = payload['name']?.toString();
    final isFolder = payload['is_folder'] == true;

    if (name == null) {
      _respondOk(envelope, respond, data: null);
      return;
    }

    try {
      String uniqueName;
      if (isFolder) {
        uniqueName = await local.getUniqueFolderPath(name);
      } else {
        uniqueName = await local.getUniqueFilePath(name);
      }
      _respondOk(envelope, respond, data: uniqueName);
    } catch (e) {
      _respondOk(envelope, respond, data: null);
    }
  }

  @override
  void dispose() {
    state?.unregisterHandler(SdkFileCommands.getDirList);
    state?.unregisterHandler(SdkFileCommands.getRootDir);
    state?.unregisterHandler(SdkFileCommands.saveCurrentFile);
    state?.unregisterHandler(SdkFileCommands.saveCurrentFileAs);
    state?.unregisterHandler(SdkFileCommands.createFile);
    state?.unregisterHandler(SdkFileCommands.createFolder);
    state?.unregisterHandler(SdkFileCommands.getFocusFileNode);
    state?.unregisterHandler(SdkFileCommands.getFocusFolderNode);
    state?.unregisterHandler(SdkFileCommands.openFile);
    state?.unregisterHandler(
      SdkFileCommands.uploadSelectedLocalFileItem,
    );
    state?.unregisterHandler(SdkFileCommands.rename);
    state?.unregisterHandler(SdkFileCommands.delete);
    state?.unregisterHandler(SdkFileCommands.openFolder);
    state?.unregisterHandler(SdkFileCommands.isFile);
    state?.unregisterHandler(SdkFileCommands.isDirectory);
    state?.unregisterHandler(SdkFileCommands.readFile);
    state?.unregisterHandler(SdkFileCommands.writeFile);
    state?.unregisterHandler(SdkFileCommands.copyFile);
    state?.unregisterHandler(SdkFileCommands.moveFile);
    state?.unregisterHandler(SdkFileCommands.exists);
    state?.unregisterHandler(SdkFileCommands.uploadFile);
    state?.unregisterHandler(SdkFileCommands.getUniqueName);
    super.dispose();
  }
}

final StateNotifierProvider<SdkFile, PluginRunManager?>
sdkFileProvider = StateNotifierProvider(
  (ref) => SdkFile(ref),
);
