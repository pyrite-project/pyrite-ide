import 'dart:io' as io;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart' as board;
import 'package:pyrite_ide/core/services/file/file_transfer_progress.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/ui_utils.dart';
import 'package:pyrite_ide/core/services/file/upload_and_download_diff.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:super_tree/super_tree.dart';
import 'package:tabbed_view/tabbed_view.dart';

class BoardNotifier extends StateNotifier<List<TreeNode<FileSystemItem>>> {
  static final _boardPath = path.Context(style: path.Style.posix);
  static const int _transferChunkSize = 768;

  final Ref ref;

  BoardNotifier(this.ref) : super(const []);

  String _tr(I18nKey key, [Map<String, String> replacements = const {}]) {
    var value = translate(ref, key);
    for (final entry in replacements.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value);
    }
    return value;
  }

  Future<List<Map<String, String>>> getFileList({String path = "/"}) async {
    final entries = await ref
        .read(boardFileBackendProvider)
        .listDirectory(path: path);
    return entries.map((entry) => entry.toLegacyMap()).toList();
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

    final builder = BytesBuilder(copy: false);
    var offset = 0;
    while (offset < size) {
      final length = (size - offset) < _transferChunkSize
          ? size - offset
          : _transferChunkSize;
      final chunk = await backend.readFileChunk(sourcePath, offset, length);
      builder.add(chunk);
      offset += chunk.length;
      progress.updateBytes(offset, size);
      if (chunk.isEmpty && length > 0) break;
    }
    return builder.takeBytes();
  }

  Future<String> writeFile(String targetPath, String content) async {
    await ref.read(boardFileBackendProvider).writeTextFile(targetPath, content);
    return 'SaveFileSuccessfully';
  }

  Future<String> writeFileBytes(
    String targetPath,
    List<int> bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    await ref
        .read(boardFileBackendProvider)
        .writeFileBytes(targetPath, bytes, onProgress: onProgress);
    return 'SaveFileSuccessfully';
  }

  Future<String> writeFileBytesWithProgress(
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
    return 'SaveFileSuccessfully';
  }

  Future<String> deleteFile(String path) async {
    await ref.read(boardFileBackendProvider).deleteFile(path);
    return 'DeleteFileSuccessfully';
  }

  Future<String> deleteFolder(String path) async {
    await ref.read(boardFileBackendProvider).deleteFolder(path);
    return 'DeleteDirSuccessfully';
  }

  Future<String> rename(String path, String newName) async {
    await ref.read(boardFileBackendProvider).rename(path, newName);
    return 'RenameSuccessfully';
  }

  Future<void> move(String oldPath, String newPath) async {
    await ref.read(boardFileBackendProvider).move(oldPath, newPath);
  }

  Future<void> createFolder(String path) async {
    await ref.read(boardFileBackendProvider).createFolder(path);
  }

  Future<List<Map<String, String>>> lisFolderRecursive({
    String path = "/",
  }) async {
    final entries = await ref
        .read(boardFileBackendProvider)
        .listTree(path: path);
    return entries.map((entry) => entry.toLegacyMap()).toList();
  }

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
          message: _tr(I18nKey.fileTransferPrepareUploadFolder),
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
      await writeFileBytesWithProgress(
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
    final normalized = _normalizeBoardFolderPath(folderPath);
    if (normalized == '/') return;

    var current = '/';
    for (final part in _boardPath.split(normalized)) {
      if (part.isEmpty || part == '/') continue;
      current = current == '/'
          ? _boardPath.join('/', part)
          : _boardPath.join(current, part);
      if (createdDirs.contains(current)) continue;

      try {
        await createFolder(current);
      } catch (error) {
        if (!await _boardFolderExists(current)) {
          debugPrint('[BoardWS] Failed to create dir: $current: $error');
          rethrow;
        }
      }
      createdDirs.add(current);
    }
  }

  String _normalizeBoardFolderPath(String folderPath) {
    final normalized = _boardPath.normalize(folderPath.replaceAll('\\', '/'));
    if (normalized == '.' || normalized.isEmpty) return '/';
    return normalized.startsWith('/') ? normalized : '/$normalized';
  }

  String _normalizeBoardPath(String filePath) {
    final normalized = _boardPath.normalize(filePath.replaceAll('\\', '/'));
    if (normalized == '.' || normalized.isEmpty) return '/';
    return normalized.startsWith('/') ? normalized : '/$normalized';
  }

  bool _isBoardPathInside(String childPath, String parentPath) {
    final child = _normalizeBoardPath(childPath);
    final parent = _normalizeBoardPath(parentPath);
    return child == parent || _boardPath.isWithin(parent, child);
  }

  Future<bool> _boardFolderExists(String folderPath) async {
    try {
      await getFileList(path: folderPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _boardPathExistsAny(String targetPath) async {
    if (await _boardFolderExists(targetPath)) return true;
    try {
      await getFileBytes(targetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteBoardPathAny(String targetPath) async {
    if (await _boardFolderExists(targetPath)) {
      await deleteFolder(targetPath);
      return;
    }
    await deleteFile(targetPath);
  }

  Future<void> downloadFolder(String remotePath, String localPath) async {
    final items = await lisFolderRecursive(path: remotePath);
    final folders = items
        .where((item) => item['type'] == 'folder')
        .toList(growable: false);
    final files = items
        .where((item) => item['type'] != 'folder')
        .toList(growable: false);
    ref
        .read(fileTransferProgressProvider.notifier)
        .start(
          direction: FileTransferDirection.download,
          scope: FileTransferScope.folder,
          totalFiles: files.length,
          message: _tr(I18nKey.fileTransferPrepareDownloadFolder),
        );

    final localDir = io.Directory(localPath);
    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }

    for (final item in folders) {
      final relativePath = _boardPath
          .relative(item['path']!, from: remotePath)
          .replaceAll('\\', '/');
      final localItemPath = path.join(localPath, relativePath);
      await io.Directory(localItemPath).create(recursive: true);
    }

    for (var i = 0; i < files.length; i++) {
      final item = files[i];
      final relativePath = _boardPath
          .relative(item['path']!, from: remotePath)
          .replaceAll('\\', '/');
      final localItemPath = path.join(localPath, relativePath);
      debugPrint('[BoardWS] Downloading: ${item['path']}');
      final bytes = await getFileBytesWithProgress(
        item['path']!,
        currentFile: item['path']!,
        index: i + 1,
        totalFiles: files.length,
      );
      final file = io.File(localItemPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      debugPrint('[BoardWS] Downloaded: $localItemPath');
    }
  }

  TreeNode<FileSystemItem>? getFocusFileNode() {
    String focusNodeId =
        ref.read(boardFileTreeViewControllerProvider).selectedNodeId ?? "/";
    TreeNode<FileSystemItem>? focusNode = ref
        .read(boardFileTreeViewControllerProvider)
        .findNodeById(focusNodeId);
    if (focusNode?.data is FileItem) {
      return focusNode;
    } else {
      return null;
    }
  }

  TreeNode<FileSystemItem>? getFocusFolderNode() {
    String focusNodeId =
        ref.read(boardFileTreeViewControllerProvider).selectedNodeId ?? "/";
    TreeNode<FileSystemItem>? focusNode = ref
        .read(boardFileTreeViewControllerProvider)
        .findNodeById(focusNodeId);
    if (focusNode?.data is FolderItem) {
      return focusNode;
    } else {
      return ref
          .read(boardFileTreeViewControllerProvider)
          .findNodeById(_boardPath.dirname(focusNodeId));
    }
  }

  List<TreeNode<FileSystemItem>> getSelectedNodes({bool topLevelOnly = true}) {
    final controller = ref.read(boardFileTreeViewControllerProvider);
    final selected = controller.getSelectedNodesInVisibleOrder(
      topLevelOnly: topLevelOnly,
    );
    if (selected.isNotEmpty) return selected;

    final focusNodeId = controller.selectedNodeId;
    final focusNode = focusNodeId == null
        ? null
        : controller.findNodeById(focusNodeId);
    return focusNode == null ? const [] : [focusNode];
  }

  Future<void> deleteSelectedBoardItems(BuildContext context) async {
    final nodes = getSelectedNodes();
    if (nodes.isEmpty) {
      showEditorSnackBar(context, _tr(I18nKey.fileMessageSelectBoardItem));
      return;
    }

    for (final node in nodes) {
      if (node.data is FolderItem) {
        await deleteFolder(node.id);
      } else {
        await deleteFile(node.id);
      }
    }
    ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
    showEditorSnackBar(
      context,
      _tr(I18nKey.fileMessageDeletedBoardItems, {'count': '${nodes.length}'}),
    );
  }

  Future<void> moveBoardNodes(
    BuildContext context,
    List<TreeNode<FileSystemItem>> nodes,
    String targetFolder,
  ) async {
    final normalizedTargetFolder = _normalizeBoardFolderPath(targetFolder);
    final movableNodes = nodes
        .where(
          (node) =>
              _normalizeBoardPath(_boardPath.dirname(node.id)) !=
              normalizedTargetFolder,
        )
        .toList(growable: false);
    if (movableNodes.isEmpty) return;
    FileConflictAction? conflictPolicy;
    var moved = 0;
    var skipped = 0;
    ref
        .read(fileTransferProgressProvider.notifier)
        .start(
          direction: FileTransferDirection.move,
          scope: movableNodes.any((node) => node.data is FolderItem)
              ? FileTransferScope.folder
              : FileTransferScope.file,
          totalFiles: movableNodes.length,
          message: _tr(I18nKey.fileTransferPrepareMoveBoardFile),
        );

    try {
      for (var i = 0; i < movableNodes.length; i++) {
        final node = movableNodes[i];
        final sourcePath = _normalizeBoardPath(node.id);
        final targetPath = normalizedTargetFolder == '/'
            ? '/${_boardPath.basename(sourcePath)}'
            : _boardPath.join(
                normalizedTargetFolder,
                _boardPath.basename(sourcePath),
              );
        if (sourcePath == targetPath) {
          skipped++;
          continue;
        }
        if (node.data is FolderItem &&
            _isBoardPathInside(normalizedTargetFolder, sourcePath)) {
          showEditorSnackBar(
            context,
            _tr(I18nKey.fileMessageCannotMoveFolderIntoSelf),
          );
          skipped++;
          continue;
        }

        final targetExists = await _boardPathExistsAny(targetPath);
        if (targetExists) {
          final action = await _resolveConflict(
            context,
            policy: conflictPolicy,
            sourcePath: sourcePath,
            targetPath: targetPath,
            isUpload: true,
          );
          switch (action) {
            case FileConflictAction.cancel:
              showEditorSnackBar(context, _tr(I18nKey.fileMessageCanceledMove));
              return;
            case FileConflictAction.showDiff:
              showEditorSnackBar(
                context,
                _tr(I18nKey.fileMessageCannotShowMoveDiff),
              );
              return;
            case FileConflictAction.skip:
              skipped++;
              continue;
            case FileConflictAction.skipAll:
              conflictPolicy = FileConflictAction.skipAll;
              skipped++;
              continue;
            case FileConflictAction.overwriteAll:
              conflictPolicy = FileConflictAction.overwriteAll;
              break;
            case FileConflictAction.overwrite:
              break;
          }
          await _deleteBoardPathAny(targetPath);
        }

        ref
            .read(fileTransferProgressProvider.notifier)
            .startFile(
              file: sourcePath,
              index: i + 1,
              totalFiles: movableNodes.length,
              bytesTotal: 0,
            );
        await move(sourcePath, targetPath);
        moved++;
      }

      ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
      ref
          .read(fileTransferProgressProvider.notifier)
          .complete(
            message: _tr(I18nKey.fileMessageMoveComplete, {
              'done': '$moved',
              'skipped': '$skipped',
            }),
          );
      showEditorSnackBar(
        context,
        _tr(I18nKey.fileMessageMoveComplete, {
          'done': '$moved',
          'skipped': '$skipped',
        }),
      );
    } catch (error) {
      ref
          .read(fileTransferProgressProvider.notifier)
          .fail(_tr(I18nKey.fileMessageMoveFailed, {'error': '$error'}));
      rethrow;
    }
  }

  Future<void> downloadSelectedBoardItems(
    BuildContext context, {
    String? localFolderPath,
  }) async {
    final nodes = getSelectedNodes();
    if (nodes.isEmpty) {
      showEditorSnackBar(context, _tr(I18nKey.fileMessageSelectBoardItem));
      return;
    }

    final localWorkspace = ref.read(fileProvider);
    if (localWorkspace == null) {
      showEditorSnackBar(context, _tr(I18nKey.fileMessageOpenLocalProject));
      return;
    }

    final localFolderTarget =
        localFolderPath ??
        ref.read(fileProvider.notifier).getFocusFolderNode()?.id;
    final targetFolder = localFolderTarget ?? localWorkspace.path;
    FileConflictAction? conflictPolicy;
    var downloaded = 0;
    var skipped = 0;

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final targetPath = path.join(targetFolder, _boardPath.basename(node.id));
      final exists = node.data is FolderItem
          ? await Directory(targetPath).exists()
          : await File(targetPath).exists();
      if (exists) {
        final canShowDiff = node.data is! FolderItem;
        final action = await _resolveConflict(
          context,
          policy: conflictPolicy,
          sourcePath: node.id,
          targetPath: targetPath,
          isUpload: false,
          canShowDiff: canShowDiff,
        );
        switch (action) {
          case FileConflictAction.cancel:
            showEditorSnackBar(
              context,
              _tr(I18nKey.fileMessageCanceledDownload),
            );
            return;
          case FileConflictAction.showDiff:
            if (!canShowDiff) {
              showEditorSnackBar(
                context,
                _tr(I18nKey.fileMessageCannotShowFolderDiff),
              );
              return;
            }
            final shown = await _showDownloadDiff(
              context,
              boardPath: node.id,
              localPath: targetPath,
            );
            if (!shown) {
              showEditorSnackBar(
                context,
                _tr(I18nKey.fileMessageCannotShowDiff),
              );
            }
            return;
          case FileConflictAction.skip:
            skipped++;
            continue;
          case FileConflictAction.skipAll:
            conflictPolicy = FileConflictAction.skipAll;
            skipped++;
            continue;
          case FileConflictAction.overwriteAll:
            conflictPolicy = FileConflictAction.overwriteAll;
            break;
          case FileConflictAction.overwrite:
            break;
        }
      }

      if (node.data is FolderItem) {
        await downloadFolder(node.id, targetPath);
      } else {
        ref
            .read(fileTransferProgressProvider.notifier)
            .start(
              direction: FileTransferDirection.download,
              scope: FileTransferScope.file,
              totalFiles: nodes.length,
              message: _tr(I18nKey.fileTransferPrepareDownloadFile),
            );
        final bytes = await getFileBytesWithProgress(
          node.id,
          currentFile: node.id,
          index: i + 1,
          totalFiles: nodes.length,
        );
        final file = File(targetPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }
      downloaded++;
    }

    ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
    ref
        .read(fileTransferProgressProvider.notifier)
        .complete(
          message: _tr(I18nKey.fileMessageDownloadComplete, {
            'done': '$downloaded',
            'skipped': '$skipped',
          }),
        );
    showEditorSnackBar(
      context,
      _tr(I18nKey.fileMessageDownloadComplete, {
        'done': '$downloaded',
        'skipped': '$skipped',
      }),
    );
  }

  Future<FileConflictAction> _resolveConflict(
    BuildContext context, {
    required FileConflictAction? policy,
    required String sourcePath,
    required String targetPath,
    required bool isUpload,
    bool canShowDiff = false,
  }) {
    if (policy == FileConflictAction.overwriteAll) {
      return Future.value(FileConflictAction.overwrite);
    }
    if (policy == FileConflictAction.skipAll) {
      return Future.value(FileConflictAction.skip);
    }
    return showFileConflictDialog(
      context,
      sourcePath: sourcePath,
      targetPath: targetPath,
      isUpload: isUpload,
      canShowDiff: canShowDiff,
    );
  }

  Future<bool> _showDownloadDiff(
    BuildContext context, {
    required String boardPath,
    required String localPath,
  }) async {
    late final String content;
    late final String originContent;
    try {
      content = await getFileContent(boardPath);
      originContent = await File(localPath).readAsString();
    } catch (_) {
      return false;
    }
    if (originContent == content) return false;

    final diff = computeDiff(originContent, content);
    if (!context.mounted) return false;
    final correspondingFile = await openFile(context, boardPath);
    if (correspondingFile == null) return false;

    final controller = ref
        .read(editorControllerMapProvider.notifier)
        .getSelectedController();
    controller?.setGitDiffDecorations(
      addedRanges: diff.addedRanges,
      removedRanges: diff.removedRanges,
    );

    final correspondingFilePath = (await board.getLocalFile(boardPath)).path;
    final provider = pendingDownloadProviderMap.putIfAbsent(
      correspondingFilePath,
      () => StateProvider<PendingDownload?>((ref) => null),
    );
    ref.read(provider.notifier).state = PendingDownload(
      diff: diff,
      boardPath: boardPath,
      localPath: localPath,
      correspondingPath: correspondingFile.path,
      content: content,
    );

    if (context.mounted && !ResponsiveBreakpoints.of(context).isDesktop) {
      context.go('/editor');
    }
    return true;
  }

  Future<File?> openFile(BuildContext context, String id) async {
    ref.read(boardFileTreeViewControllerProvider).setSelectedNodeId(id);
    final node = ref.read(boardFileTreeViewControllerProvider).findNodeById(id);
    if (node == null || node.data is! FileItem) return null;
    final file = await board.getLocalFile(node.id);
    final content = await ref.read(boardProvider.notifier).getFileContent(id);
    await file.writeAsString(content);
    if (context.mounted) {
      await ref
          .read(tabbedViewControllerProvider.notifier)
          .openFile(context, file: file, isBoardFile: true, boardFilePath: id);
    }
    return file;
  }

  Future<void> saveFile() async {
    final TabData? nowTab = ref.read(tabbedViewControllerProvider).selectedTab;
    final value = nowTab?.value;
    if (value is TabDataValue && value.type == "file") {
      if (value.isBoardFile == true && value.boardFilePath != null) {
        await ref
            .read(boardProvider.notifier)
            .writeFile(value.boardFilePath!, value.editorController!.text);
        ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
      } else {
        await value.file!.writeAsString(value.editorController!.text);
      }
      ref.read(tabbedViewControllerProvider.notifier).afterFileSave();
    }
  }

  Future<void> _downloadSelectedBoardItem(
    BuildContext context, {
    TabData? selectedTab,
  }) async {
    TreeNode<FileSystemItem>? selectedFile = getFocusFileNode();
    TreeNode<FileSystemItem>? selectedFolder = getFocusFolderNode();
    if (selectedTab == null) {
      selectedFile = getFocusFileNode();
      selectedFolder = getFocusFolderNode();
    }
    final selected = selectedFile ?? selectedFolder;
    final localWorkspace = ref.read(fileProvider);
    if (selected == null && selectedTab == null) {
      showEditorSnackBar(context, _tr(I18nKey.fileMessageSelectBoardItem));
      return;
    }
    if (localWorkspace == null) {
      showEditorSnackBar(context, _tr(I18nKey.fileMessageOpenLocalProject));
      return;
    }

    final localFolderTarget = ref
        .read(fileProvider.notifier)
        .getFocusFolderNode();
    final targetPath = localFolderTarget?.id != null
        ? path.join(
            localFolderTarget!.id,
            _boardPath.basename(
              (selected?.id ?? selectedTab?.value.filePath).toString(),
            ),
          )
        : path.join(
            localWorkspace.path,
            _boardPath.basename(
              (selected?.id ?? selectedTab?.value.filePath).toString(),
            ),
          );

    if (selected?.data is FileItem || selectedTab != null) {
      final content = await getFileContent(
        selected?.id ?? selectedTab?.value.filePath,
      );

      String? originContent;
      if (await File(targetPath).exists()) {
        try {
          originContent = await File(targetPath).readAsString();
        } catch (_) {}
      }
      if (originContent != null && originContent != content) {
        final diff = computeDiff(originContent, content);

        if (ref.read(uploadConfirmStyleProvider) == 'dialog') {
          final confirmed = await showDiffConfirmDialog(
            context,
            diff: diff,
            targetPath: targetPath,
            isUpload: false,
          );
          if (!confirmed) {
            showEditorSnackBar(
              context,
              _tr(I18nKey.fileMessageCanceledDownload),
            );
            return;
          }
        } else {
          await _showDownloadDiff(
            context,
            boardPath: selected?.id ?? selectedTab!.value.filePath,
            localPath: targetPath,
          );
          return;
        }
      }

      ref
          .read(fileTransferProgressProvider.notifier)
          .start(
            direction: FileTransferDirection.download,
            scope: FileTransferScope.file,
            totalFiles: 1,
            message: _tr(I18nKey.fileTransferPrepareDownloadFile),
          );
      final bytes = await getFileBytesWithProgress(
        selected?.id ?? selectedTab?.value.filePath,
        currentFile: selected?.id ?? selectedTab?.value.filePath,
        index: 1,
        totalFiles: 1,
      );
      final file = File(targetPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      ref
          .read(fileTransferProgressProvider.notifier)
          .complete(
            message: _tr(I18nKey.fileMessageDownloadedToLocal, {
              'path': targetPath,
            }),
          );

      showEditorSnackBar(
        context,
        _tr(I18nKey.fileMessageDownloadedToLocal, {'path': targetPath}),
      );
    } else {
      try {
        await ref
            .read(boardProvider.notifier)
            .downloadFolder(
              selected?.id ?? selectedTab?.value.filePath,
              targetPath,
            );
        ref
            .read(fileTransferProgressProvider.notifier)
            .complete(
              message: _tr(I18nKey.fileMessageDownloadedFolderToLocal, {
                'path': targetPath,
              }),
            );
      } catch (error) {
        ref
            .read(fileTransferProgressProvider.notifier)
            .fail(_tr(I18nKey.fileMessageDownloadFailed, {'error': '$error'}));
        rethrow;
      }

      showEditorSnackBar(
        context,
        _tr(I18nKey.fileMessageDownloadedFolderToLocal, {'path': targetPath}),
      );
    }

    ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
  }

  Future<void> downloadSelectedBoardItem(
    BuildContext context, {
    TabData? selectedTab,
  }) async {
    TreeNode<FileSystemItem>? selectedFile = getFocusFileNode();
    TreeNode<FileSystemItem>? selectedFolder = getFocusFolderNode();
    if (selectedTab == null) {
      selectedFile = getFocusFileNode();
      selectedFolder = getFocusFolderNode();
    }

    final selected = selectedFile ?? selectedFolder;
    final localWorkspace = ref.read(fileProvider);
    if (selected == null && selectedTab == null) {
      showEditorSnackBar(context, _tr(I18nKey.fileMessageSelectBoardItem));
      return;
    }
    if (localWorkspace == null) {
      showEditorSnackBar(context, _tr(I18nKey.fileMessageOpenLocalProject));
      return;
    }

    if (selected?.data is FileItem || selectedTab != null) {
      final content = await getFileContent(
        selected?.id ?? selectedTab?.value.filePath,
      );

      final correspondingFilePath = (await board.getLocalFile(
        selected?.id ?? selectedTab?.value.filePath,
      )).path;

      if ((ref.read(editorControllerMapProvider)[correspondingFilePath]?.text !=
              null) &&
          (content !=
              ref
                  .read(editorControllerMapProvider)[correspondingFilePath]!
                  .text)) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.file_download_outlined),
            title: const UseText(I18nKey.dialogBoardContentMismatchTitle),
            content: Text(
              translate(ref, I18nKey.dialogContentMismatchMessage).replaceAll(
                '{path}',
                selected?.id ?? selectedTab?.value.filePath ?? '',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(false),
                child: const UseText(I18nKey.dialogCancelUpload),
              ),
              TextButton(
                onPressed: () {
                  saveFile();
                  _downloadSelectedBoardItem(context, selectedTab: selectedTab);
                  context.pop();
                },
                child: const UseText(I18nKey.dialogEditorContent),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () {
                  ref
                          .read(
                            editorControllerMapProvider,
                          )[correspondingFilePath]
                          ?.text =
                      content;
                  saveFile();
                  _downloadSelectedBoardItem(context, selectedTab: selectedTab);
                  context.pop();
                },
                child: const UseText(I18nKey.dialogActualContent),
              ),
            ],
          ),
        );
      } else {
        _downloadSelectedBoardItem(context, selectedTab: selectedTab);
      }
    } else {
      _downloadSelectedBoardItem(context, selectedTab: selectedTab);
    }
  }

  void clear() {
    state = const [];
  }
}

final StateNotifierProvider<BoardNotifier, List<TreeNode<FileSystemItem>>>
boardProvider = StateNotifierProvider((ref) => BoardNotifier(ref));
