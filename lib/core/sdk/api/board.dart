import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend_provider.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart' as board;
import 'package:pyrite_ide/core/services/file/board_provider.dart';
import 'package:pyrite_ide/core/services/file/file_transfer_progress.dart';

abstract class SdkBoardCommands {
  static const String getDirList = 'sdk.board.get_dir_list';
  static const String getRootDir = 'sdk.board.get_root_dir';
  static const String getFocusFileNode = 'sdk.board.get_focus_file_node';
  static const String getFocusFolderNode = 'sdk.board.get_focus_folder_node';
  static const String openFile = 'sdk.board.open_file';
  static const String downloadSelectedBoardItem =
      'sdk.board.download_selected_board_item';
  static const String rename = 'sdk.board.rename';
  static const String deleteFile = 'sdk.board.delete_file';
  static const String deleteFolder = 'sdk.board.delete_folder';
  static const String isFile = 'sdk.board.is_file';
  static const String isDirectory = 'sdk.board.is_directory';
  static const String getCorrespondingFilePath =
      'sdk.board.get_corresponding_file_path';
  static const String readFile = 'sdk.board.read_file';
  static const String writeFile = 'sdk.board.write_file';
  static const String exists = 'sdk.board.exists';
  static const String downloadFile = 'sdk.board.download_file';
}

class SdkBoard extends StateNotifier<PluginRunManager?> {
  final Ref ref;
  SdkBoard(this.ref) : super(null);

  void bind(PluginRunManager runManager) {
    state = runManager;
    runManager.registerHandler(SdkBoardCommands.getDirList, _handleGetDirList);
    runManager.registerHandler(SdkBoardCommands.getRootDir, _handleGetRootDir);
    runManager.registerHandler(
      SdkBoardCommands.getFocusFileNode,
      _handleGetFocusFileNode,
    );
    runManager.registerHandler(
      SdkBoardCommands.getFocusFolderNode,
      _handleGetFocusFolderNode,
    );
    runManager.registerHandler(SdkBoardCommands.openFile, _handleOpenFile);
    runManager.registerHandler(
      SdkBoardCommands.downloadSelectedBoardItem,
      _handleDownloadSelectedBoardItem,
    );
    runManager.registerHandler(SdkBoardCommands.rename, _handleRename);
    runManager.registerHandler(SdkBoardCommands.deleteFile, _handleDeleteFile);
    runManager.registerHandler(
      SdkBoardCommands.deleteFolder,
      _handleDeleteFolder,
    );
    runManager.registerHandler(SdkBoardCommands.isFile, _handleIsFile);
    runManager.registerHandler(
      SdkBoardCommands.isDirectory,
      _handleIsDirectory,
    );
    runManager.registerHandler(
      SdkBoardCommands.getCorrespondingFilePath,
      _handleGetCorrespondingFilePath,
    );
    runManager.registerHandler(SdkBoardCommands.readFile, _handleReadFile);
    runManager.registerHandler(SdkBoardCommands.writeFile, _handleWriteFile);
    runManager.registerHandler(SdkBoardCommands.exists, _handleExists);
    runManager.registerHandler(
      SdkBoardCommands.downloadFile,
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
    final node = ref.read(boardProvider.notifier).getFocusFileNode();
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
    final node = ref.read(boardProvider.notifier).getFocusFolderNode();
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
      await ref.read(boardProvider.notifier).openFile(context, filePath);
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
      await ref.read(boardProvider.notifier).downloadSelectedBoardItem(context);
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
      await ref.read(boardProvider.notifier).rename(filePath, newName);
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
      await ref.read(boardProvider.notifier).deleteFile(filePath);
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
      await ref.read(boardProvider.notifier).deleteFolder(filePath);
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
        final content = await ref
            .read(boardFileBackendProvider)
            .readTextFile(filePath);
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
        final backend = ref.read(boardFileBackendProvider);
        ref
            .read(fileTransferProgressProvider.notifier)
            .start(
              direction: FileTransferDirection.download,
              scope: FileTransferScope.file,
              totalFiles: 1,
              message: '准备下载文件',
            );
        final size = await backend.getFileSize(boardPath);
        ref
            .read(fileTransferProgressProvider.notifier)
            .startFile(
              file: boardPath,
              index: 1,
              totalFiles: 1,
              bytesTotal: size,
            );
        final builder = BytesBuilder(copy: false);
        var offset = 0;
        while (offset < size) {
          final length = (size - offset) < 768 ? size - offset : 768;
          final chunk = await backend.readFileChunk(boardPath, offset, length);
          builder.add(chunk);
          offset += chunk.length;
          ref
              .read(fileTransferProgressProvider.notifier)
              .updateBytes(offset, size);
          if (chunk.isEmpty && length > 0) break;
        }
        final bytes = builder.takeBytes();
        final file = File(localPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        ref
            .read(fileTransferProgressProvider.notifier)
            .complete(message: '已下载到本地：$localPath');
        _respondOk(envelope, respond, data: true);
      } catch (e) {
        ref.read(fileTransferProgressProvider.notifier).fail('下载失败：$e');
        _respondOk(envelope, respond, data: false);
      }
    } else {
      _respondOk(envelope, respond, data: false);
    }
  }

  @override
  void dispose() {
    state?.unregisterHandler(SdkBoardCommands.getDirList);
    state?.unregisterHandler(SdkBoardCommands.getRootDir);
    state?.unregisterHandler(SdkBoardCommands.getFocusFileNode);
    state?.unregisterHandler(SdkBoardCommands.getFocusFolderNode);
    state?.unregisterHandler(SdkBoardCommands.openFile);
    state?.unregisterHandler(SdkBoardCommands.downloadSelectedBoardItem);
    state?.unregisterHandler(SdkBoardCommands.rename);
    state?.unregisterHandler(SdkBoardCommands.deleteFile);
    state?.unregisterHandler(SdkBoardCommands.deleteFolder);
    state?.unregisterHandler(SdkBoardCommands.isFile);
    state?.unregisterHandler(SdkBoardCommands.isDirectory);
    state?.unregisterHandler(SdkBoardCommands.getCorrespondingFilePath);
    state?.unregisterHandler(SdkBoardCommands.readFile);
    state?.unregisterHandler(SdkBoardCommands.writeFile);
    state?.unregisterHandler(SdkBoardCommands.exists);
    state?.unregisterHandler(SdkBoardCommands.downloadFile);
    super.dispose();
  }
}

final StateNotifierProvider<SdkBoard, PluginRunManager?> sdkBoardProvider =
    StateNotifierProvider((ref) => SdkBoard(ref));
