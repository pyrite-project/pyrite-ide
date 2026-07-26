import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_ops.dart';
import 'package:pyrite_ide/core/services/file/file_transfer_progress.dart';

/// Folder upload/download orchestration — no BuildContext dependency.
class BoardTransfer {
  static final _boardPath = path.Context(style: path.Style.posix);

  final Ref ref;
  final BoardFileOps _ops;

  BoardTransfer(this.ref, this._ops);

  Future<void> uploadFolder(String localPath, String remotePath) async {
    final dir = io.Directory(localPath);
    final entities = await dir.list(recursive: true).toList();
    final files = entities.whereType<io.File>().toList(growable: false);
    final createdDirs = <String>{};
    ref
        .read(fileTransferProgressProvider.notifier)
        .start(
          direction: FileTransferDirection.upload,
          scope: FileTransferScope.folder,
          totalFiles: files.length,
          message: translateWithReplacements(ref,I18nKey.fileTransferPrepareUploadFolder),
        );

    await _ensureBoardFolder(remotePath, createdDirs);

    for (final entity in entities) {
      final relativePath = path
          .relative(entity.path, from: localPath)
          .replaceAll('\\', '/');
      final remoteEntityPath = _boardPath.join(remotePath, relativePath);

      if (entity is io.Directory) {
        debugPrint('[BoardWS] Creating remote dir: $remoteEntityPath');
        await _ensureBoardFolder(remoteEntityPath, createdDirs);
      }
    }

    for (var i = 0; i < files.length; i++) {
      final entity = files[i];
      final relativePath = path
          .relative(entity.path, from: localPath)
          .replaceAll('\\', '/');
      final remoteEntityPath = _boardPath.join(remotePath, relativePath);
      final parentDir = _boardPath.dirname(remoteEntityPath);
      if (!createdDirs.contains(parentDir)) {
        debugPrint('[BoardWS] Creating parent dir: $parentDir');
        await _ensureBoardFolder(parentDir, createdDirs);
      }
      debugPrint('[BoardWS] Uploading file: $remoteEntityPath');
      await _ops.writeFileBytesWithProgress(
        remoteEntityPath,
        await entity.readAsBytes(),
        currentFile: entity.path,
        index: i + 1,
        totalFiles: files.length,
      );
      debugPrint('[BoardWS] Uploaded: $remoteEntityPath');
    }
  }

  Future<void> _ensureBoardFolder(
    String folderPath,
    Set<String> createdDirs,
  ) async {
    final normalized = _ops.normalizeBoardPath(folderPath);
    if (normalized == '/') return;

    var current = '/';
    for (final part in _boardPath.split(normalized)) {
      if (part.isEmpty || part == '/') continue;
      current = current == '/'
          ? _boardPath.join('/', part)
          : _boardPath.join(current, part);
      if (createdDirs.contains(current)) continue;

      try {
        await _ops.createFolder(current);
      } catch (error) {
        if (!await _ops.boardFolderExists(current)) {
          debugPrint('[BoardWS] Failed to create dir: $current: $error');
          rethrow;
        }
      }
      createdDirs.add(current);
    }
  }

  Future<void> downloadFolder(String remotePath, String localPath) async {
    final items = await _ops.lisFolderRecursive(path: remotePath);
    final folders = items
        .where((item) => item.isFolder)
        .toList(growable: false);
    final files = items
        .where((item) => !item.isFolder)
        .toList(growable: false);
    ref
        .read(fileTransferProgressProvider.notifier)
        .start(
          direction: FileTransferDirection.download,
          scope: FileTransferScope.folder,
          totalFiles: files.length,
          message: translateWithReplacements(ref,I18nKey.fileTransferPrepareDownloadFolder),
        );

    final localDir = io.Directory(localPath);
    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }

    for (final item in folders) {
      final relativePath = _boardPath
          .relative(item.path, from: remotePath)
          .replaceAll('\\', '/');
      final localItemPath = path.join(localPath, relativePath);
      await io.Directory(localItemPath).create(recursive: true);
    }

    for (var i = 0; i < files.length; i++) {
      final item = files[i];
      final relativePath = _boardPath
          .relative(item.path, from: remotePath)
          .replaceAll('\\', '/');
      final localItemPath = path.join(localPath, relativePath);
      debugPrint('[BoardWS] Downloading: ${item.path}');
      final bytes = await _ops.getFileBytesWithProgress(
        item.path,
        currentFile: item.path,
        index: i + 1,
        totalFiles: files.length,
      );
      final file = io.File(localItemPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      debugPrint('[BoardWS] Downloaded: $localItemPath');
    }
  }
}
