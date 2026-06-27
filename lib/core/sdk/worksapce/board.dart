import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/board_manager/utils.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend_provider.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart' as board;
import 'package:pyrite_ide/core/services/file/board_workspace_provider.dart';

abstract class SdkBoardWorkspaceCommands {
  static const String getDirList = 'sdk.board_workspace.get_dir_list';
  static const String getRootDir = 'sdk.board_workspace.get_root_dir';
  static const String getFocusFileNode =
      'sdk.board_workspace.get_focus_file_node';
  static const String getFocusFolderNode =
      'sdk.board_workspace.get_focus_folder_node';
  static const String openFile = 'sdk.board_workspace.open_file';
  static const String downloadSelectedBoardItem =
      'sdk.board_workspace.download_selected_board_item';
  static const String rename = 'sdk.board_workspace.rename';
  static const String deleteFile = 'sdk.board_workspace.delete_file';
  static const String deleteFolder = 'sdk.board_workspace.delete_folder';
  static const String isFile = 'sdk.board_workspace.is_file';
  static const String isDirectory = 'sdk.board_workspace.is_directory';
  static const String getCorrespondingFilePath =
      'sdk.board_workspace.get_corresponding_file_path';
  static const String readFile = 'sdk.board_workspace.read_file';
  static const String writeFile = 'sdk.board_workspace.write_file';
  static const String exists = 'sdk.board_workspace.exists';
  static const String downloadFile = 'sdk.board_workspace.download_file';
}

class SdkBoardWorkspace extends StateNotifier<PluginRunManager?> {
  final Ref ref;
  SdkBoardWorkspace(this.ref) : super(null);

  void bind(PluginRunManager runManager) {
    state = runManager;
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.getDirList,
      _handleGetDirList,
    );
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.getRootDir,
      _handleGetRootDir,
    );
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.getFocusFileNode,
      _handleGetFocusFileNode,
    );
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.getFocusFolderNode,
      _handleGetFocusFolderNode,
    );
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.openFile,
      _handleOpenFile,
    );
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.downloadSelectedBoardItem,
      _handleDownloadSelectedBoardItem,
    );
    runManager.registerHandler(SdkBoardWorkspaceCommands.rename, _handleRename);
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.deleteFile,
      _handleDeleteFile,
    );
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.deleteFolder,
      _handleDeleteFolder,
    );
    runManager.registerHandler(SdkBoardWorkspaceCommands.isFile, _handleIsFile);
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.isDirectory,
      _handleIsDirectory,
    );
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.getCorrespondingFilePath,
      _handleGetCorrespondingFilePath,
    );
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.readFile,
      _handleReadFile,
    );
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.writeFile,
      _handleWriteFile,
    );
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.exists,
      _handleExists,
    );
    runManager.registerHandler(
      SdkBoardWorkspaceCommands.downloadFile,
      _handleDownloadFile,
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

  bool _isConnected() {
    final serialProvider = getUsbSerialProvider();
    final serialState = ref.read(serialProvider);
    return serialState.isConnected == true;
  }

  Future<void> _handleGetDirList(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (!_isConnected()) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final String? dirPath = envelope['data']?.toString();
    final List<String> entries = [];
    if (dirPath != null) {
      final List<BoardFileEntry> entries0 = (await ref
          .read(boardFileBackendProvider)
          .listDirectory(path: dirPath));
      for (BoardFileEntry entry in entries0) {
        entries.add(entry.path);
      }
    }

    _respondOk(envelope, respond, data: entries);
  }

  void _handleGetRootDir(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    _respondOk(envelope, respond, data: "/");
  }

  void _handleGetFocusFileNode(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final node = ref.read(boardWorkspaceProvider.notifier).getFocusFileNode();
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
    final node = ref.read(boardWorkspaceProvider.notifier).getFocusFolderNode();
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
    if (!_isConnected()) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();
    if (filePath == null) {
      _respondOk(envelope, respond);
      return;
    }

    final context = appContext;
    if (context != null && context.mounted) {
      await ref
          .read(boardWorkspaceProvider.notifier)
          .openFile(context, filePath);
    }

    _respondOk(envelope, respond);
  }

  Future<void> _handleDownloadSelectedBoardItem(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (!_isConnected()) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final context = appContext;
    if (context != null && context.mounted) {
      await ref
          .read(boardWorkspaceProvider.notifier)
          .downloadSelectedBoardItem(context);
    }
    _respondOk(envelope, respond);
  }

  Future<void> _handleRename(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (!_isConnected()) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();
    final newName = payload['new_name']?.toString();

    if (filePath != null && newName != null) {
      await ref.read(boardWorkspaceProvider.notifier).rename(filePath, newName);
    }
    _respondOk(envelope, respond);
  }

  Future<void> _handleDeleteFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (!_isConnected()) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();

    if (filePath != null) {
      await ref.read(boardWorkspaceProvider.notifier).deleteFile(filePath);
    }
    _respondOk(envelope, respond);
  }

  Future<void> _handleDeleteFolder(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (!_isConnected()) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();

    if (filePath != null) {
      await ref.read(boardWorkspaceProvider.notifier).deleteFolder(filePath);
    }
    _respondOk(envelope, respond);
  }

  Future<void> _handleIsDirectory(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (!_isConnected()) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();

    if (filePath != null) {
      final entries = await ref
          .read(boardFileBackendProvider)
          .listDirectory(path: p.dirname(filePath));
      for (final entry in entries) {
        if (filePath == entry.path) {
          _respondOk(envelope, respond, data: entry.isFolder);
          return;
        }
      }
      _respondOk(envelope, respond, data: false);
    } else {
      _respondOk(envelope, respond, data: false);
    }
  }

  Future<void> _handleIsFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (!_isConnected()) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();

    if (filePath != null) {
      final entries = await ref
          .read(boardFileBackendProvider)
          .listDirectory(path: p.dirname(filePath));
      for (final entry in entries) {
        if (filePath == entry.path) {
          _respondOk(envelope, respond, data: !entry.isFolder);
          return;
        }
      }
      _respondOk(envelope, respond, data: false);
    } else {
      _respondOk(envelope, respond, data: false);
    }
  }

  Future<void> _handleGetCorrespondingFilePath(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();

    if (filePath != null) {
      final correspondingFilePath = board.getLocalFile(filePath);
      _respondOk(envelope, respond, data: correspondingFilePath);
    } else {
      _respondOk(envelope, respond, data: null);
    }
  }

  Future<void> _handleReadFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (!_isConnected()) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();

    if (filePath != null) {
      try {
        final content =
            await ref.read(boardFileBackendProvider).readTextFile(filePath);
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
    if (!_isConnected()) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();
    final content = payload['content']?.toString();

    if (filePath != null && content != null) {
      try {
        await ref
            .read(boardFileBackendProvider)
            .writeTextFile(filePath, content);
        _respondOk(envelope, respond, data: true);
      } catch (e) {
        _respondOk(envelope, respond, data: false);
      }
    } else {
      _respondOk(envelope, respond, data: false);
    }
  }

  Future<void> _handleExists(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (!_isConnected()) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();

    if (filePath != null) {
      try {
        final entries = await ref
            .read(boardFileBackendProvider)
            .listDirectory(path: p.dirname(filePath));
        for (final entry in entries) {
          if (entry.path == filePath) {
            _respondOk(envelope, respond, data: true);
            return;
          }
        }
        _respondOk(envelope, respond, data: false);
      } catch (e) {
        _respondOk(envelope, respond, data: false);
      }
    } else {
      _respondOk(envelope, respond, data: false);
    }
  }

  Future<void> _handleDownloadFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (!_isConnected()) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final boardPath = payload['board_path']?.toString();
    final localPath = payload['local_path']?.toString();

    if (boardPath != null && localPath != null) {
      try {
        final bytes =
            await ref.read(boardFileBackendProvider).readFileBytes(boardPath);
        await File(localPath).writeAsBytes(bytes);
        _respondOk(envelope, respond, data: true);
      } catch (e) {
        _respondOk(envelope, respond, data: false);
      }
    } else {
      _respondOk(envelope, respond, data: false);
    }
  }

  @override
  void dispose() {
    state?.unregisterHandler(SdkBoardWorkspaceCommands.getDirList);
    state?.unregisterHandler(SdkBoardWorkspaceCommands.getRootDir);
    state?.unregisterHandler(SdkBoardWorkspaceCommands.getFocusFileNode);
    state?.unregisterHandler(SdkBoardWorkspaceCommands.getFocusFolderNode);
    state?.unregisterHandler(SdkBoardWorkspaceCommands.openFile);
    state?.unregisterHandler(
      SdkBoardWorkspaceCommands.downloadSelectedBoardItem,
    );
    state?.unregisterHandler(SdkBoardWorkspaceCommands.rename);
    state?.unregisterHandler(SdkBoardWorkspaceCommands.deleteFile);
    state?.unregisterHandler(SdkBoardWorkspaceCommands.deleteFolder);
    state?.unregisterHandler(SdkBoardWorkspaceCommands.isFile);
    state?.unregisterHandler(SdkBoardWorkspaceCommands.isDirectory);
    state?.unregisterHandler(
      SdkBoardWorkspaceCommands.getCorrespondingFilePath,
    );
    state?.unregisterHandler(SdkBoardWorkspaceCommands.readFile);
    state?.unregisterHandler(SdkBoardWorkspaceCommands.writeFile);
    state?.unregisterHandler(SdkBoardWorkspaceCommands.exists);
    state?.unregisterHandler(SdkBoardWorkspaceCommands.downloadFile);
    super.dispose();
  }
}

final StateNotifierProvider<SdkBoardWorkspace, PluginRunManager?>
sdkBoardWorkspaceProvider = StateNotifierProvider(
  (ref) => SdkBoardWorkspace(ref),
);
