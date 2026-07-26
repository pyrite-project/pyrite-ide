import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/file/board_file_backend.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend_provider.dart';
import 'package:pyrite_ide/core/services/file/file_transfer_progress.dart';

/// Pure board file I/O operations — no BuildContext dependency.
class BoardFileOps {
  static final boardPath = path.Context(style: path.Style.posix);

  final Ref ref;

  BoardFileOps(this.ref);

  String normalizeBoardPath(String filePath) {
    final normalized = boardPath.normalize(filePath.replaceAll('\\', '/'));
    if (normalized == '.' || normalized.isEmpty) return '/';
    return normalized.startsWith('/') ? normalized : '/$normalized';
  }

  bool isBoardPathInside(String childPath, String parentPath) {
    final child = normalizeBoardPath(childPath);
    final parent = normalizeBoardPath(parentPath);
    return child == parent || boardPath.isWithin(parent, child);
  }

  Future<List<BoardFileEntry>> getFileList({String path = "/"}) async {
    return ref.read(boardFileBackendProvider).listDirectory(path: path);
  }

  Future<String> getFileContent(String path) async {
    return ref.read(boardFileBackendProvider).readTextFile(path);
  }

  Future<Uint8List> getFileBytes(String path) async {
    return ref.read(boardFileBackendProvider).readFileBytes(path);
  }

  Future<Uint8List> getFileBytesWithProgress(
    String sourcePath, {
    required String currentFile,
    required int index,
    required int totalFiles,
  }) async {
    final backend = ref.read(boardFileBackendProvider);
    final progress = ref.read(fileTransferProgressProvider.notifier);
    final size = await backend.getFileSize(sourcePath);
    progress.startFile(
      file: currentFile,
      index: index,
      totalFiles: totalFiles,
      bytesTotal: size,
    );
    if (size == 0) return Uint8List(0);
    final bytes = await backend.readFileBytes(sourcePath);
    progress.updateBytes(bytes.length, bytes.length);
    return bytes;
  }

  Future<void> writeFile(String targetPath, String content) async {
    await ref.read(boardFileBackendProvider).writeTextFile(targetPath, content);
  }

  Future<void> writeFileBytes(
    String targetPath,
    List<int> bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    await ref
        .read(boardFileBackendProvider)
        .writeFileBytes(targetPath, bytes, onProgress: onProgress);
  }

  Future<void> writeFileBytesWithProgress(
    String targetPath,
    List<int> bytes, {
    required String currentFile,
    required int index,
    required int totalFiles,
  }) async {
    final backend = ref.read(boardFileBackendProvider);
    final progress = ref.read(fileTransferProgressProvider.notifier);
    progress.startFile(
      file: currentFile,
      index: index,
      totalFiles: totalFiles,
      bytesTotal: bytes.length,
    );
    await backend.writeFileBytes(
      targetPath,
      bytes,
      onProgress: progress.updateBytes,
    );
    progress.updateBytes(bytes.length, bytes.length);
  }

  Future<void> deleteFile(String path) async {
    await ref.read(boardFileBackendProvider).deleteFile(path);
  }

  Future<void> deleteFolder(String path) async {
    await ref.read(boardFileBackendProvider).deleteFolder(path);
  }

  Future<void> rename(String path, String newName) async {
    await ref.read(boardFileBackendProvider).rename(path, newName);
  }

  Future<void> move(String oldPath, String newPath) async {
    await ref.read(boardFileBackendProvider).move(oldPath, newPath);
  }

  Future<void> createFolder(String path) async {
    await ref.read(boardFileBackendProvider).createFolder(path);
  }

  Future<List<BoardFileEntry>> lisFolderRecursive({
    String path = "/",
  }) async {
    return ref.read(boardFileBackendProvider).listTree(path: path);
  }

  Future<bool> boardFolderExists(String folderPath) async {
    try {
      await getFileList(path: folderPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> boardPathExistsAny(String targetPath) async {
    try {
      await ref.read(boardFileBackendProvider).pathExists(targetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteBoardPathAny(String targetPath) async {
    final exists = await boardPathExistsAny(targetPath);
    if (!exists) return;
    try {
      await deleteFolder(targetPath);
    } catch (_) {
      await deleteFile(targetPath);
    }
  }
}
