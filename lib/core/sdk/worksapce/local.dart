import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:pyrite_ide/core/services/file/local_workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend_provider.dart';

abstract class SdkLocalWorkspaceCommands {
  static const String getDirList = 'sdk.local_workspace.get_dir_list';
  static const String getRootDir = 'sdk.local_workspace.get_root_dir';
  static const String saveCurrentFile = 'sdk.local_workspace.save_current_file';
  static const String saveCurrentFileAs =
      'sdk.local_workspace.save_current_file_as';
  static const String createFile = 'sdk.local_workspace.create_file';
  static const String createFolder = 'sdk.local_workspace.create_folder';
  static const String getFocusFileNode =
      'sdk.local_workspace.get_focus_file_node';
  static const String getFocusFolderNode =
      'sdk.local_workspace.get_focus_folder_node';
  static const String openFile = 'sdk.local_workspace.open_file';
  static const String uploadSelectedLocalFileItem =
      'sdk.local_workspace.upload_selected_local_file_item';
  static const String rename = 'sdk.local_workspace.rename';
  static const String delete = 'sdk.local_workspace.delete';
  static const String openFolder = 'sdk.local_workspace.open_folder';
  static const String isFile = 'sdk.local_workspace.is_file';
  static const String isDirectory = 'sdk.local_workspace.is_directory';
  static const String readFile = 'sdk.local_workspace.read_file';
  static const String writeFile = 'sdk.local_workspace.write_file';
  static const String copyFile = 'sdk.local_workspace.copy_file';
  static const String moveFile = 'sdk.local_workspace.move_file';
  static const String exists = 'sdk.local_workspace.exists';
  static const String uploadFile = 'sdk.local_workspace.upload_file';
  static const String getUniqueName = 'sdk.local_workspace.get_unique_name';
}

class SdkLocalWorkspace extends StateNotifier<PluginRunManager?> {
  final Ref ref;
  SdkLocalWorkspace(this.ref) : super(null);

  void bind(PluginRunManager runManager) {
    state = runManager;
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.getDirList,
      _handleGetDirList,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.getRootDir,
      _handleGetRootDir,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.saveCurrentFile,
      _handleSaveCurrentFile,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.saveCurrentFileAs,
      _handleSaveCurrentFileAs,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.createFile,
      _handleCreateFile,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.createFolder,
      _handleCreateFolder,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.getFocusFileNode,
      _handleGetFocusFileNode,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.getFocusFolderNode,
      _handleGetFocusFolderNode,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.openFile,
      _handleOpenFile,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.uploadSelectedLocalFileItem,
      _handleUploadSelectedLocalFileItem,
    );
    runManager.registerHandler(SdkLocalWorkspaceCommands.rename, _handleRename);
    runManager.registerHandler(SdkLocalWorkspaceCommands.delete, _handleDelete);
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.openFolder,
      _handleOpenFolder,
    );
    runManager.registerHandler(SdkLocalWorkspaceCommands.isFile, _handleIsFile);
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.isDirectory,
      _handleIsDirectory,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.readFile,
      _handleReadFile,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.writeFile,
      _handleWriteFile,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.copyFile,
      _handleCopyFile,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.moveFile,
      _handleMoveFile,
    );
    runManager.registerHandler(SdkLocalWorkspaceCommands.exists, _handleExists);
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.uploadFile,
      _handleUploadFile,
    );
    runManager.registerHandler(
      SdkLocalWorkspaceCommands.getUniqueName,
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
    _respondOk(envelope, respond, data: ref.read(localWorkspaceProvider)?.path);
  }

  void _handleSaveCurrentFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    ref.read(localWorkspaceProvider.notifier).saveCurrentFile();
    _respondOk(envelope, respond);
  }

  void _handleSaveCurrentFileAs(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    ref.read(localWorkspaceProvider.notifier).saveCurrentFileAs();
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
        .read(localWorkspaceProvider.notifier)
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
        .read(localWorkspaceProvider.notifier)
        .createFolder(folderPath);
    _respondOk(envelope, respond, data: {'path': createdPath});
  }

  void _handleGetFocusFileNode(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final node = ref.read(localWorkspaceProvider.notifier).getFocusFileNode();
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
    final node = ref.read(localWorkspaceProvider.notifier).getFocusFolderNode();
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
          .read(localWorkspaceProvider.notifier)
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
          .read(localWorkspaceProvider.notifier)
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
        ref.read(localWorkspaceProvider.notifier).setDirectory(dir);
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
    state?.unregisterHandler(SdkLocalWorkspaceCommands.getDirList);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.getRootDir);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.saveCurrentFile);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.saveCurrentFileAs);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.createFile);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.createFolder);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.getFocusFileNode);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.getFocusFolderNode);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.openFile);
    state?.unregisterHandler(
      SdkLocalWorkspaceCommands.uploadSelectedLocalFileItem,
    );
    state?.unregisterHandler(SdkLocalWorkspaceCommands.rename);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.delete);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.openFolder);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.isFile);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.isDirectory);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.readFile);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.writeFile);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.copyFile);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.moveFile);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.exists);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.uploadFile);
    state?.unregisterHandler(SdkLocalWorkspaceCommands.getUniqueName);
    super.dispose();
  }
}

final StateNotifierProvider<SdkLocalWorkspace, PluginRunManager?>
sdkLocalWorkspaceProvider = StateNotifierProvider(
  (ref) => SdkLocalWorkspace(ref),
);
