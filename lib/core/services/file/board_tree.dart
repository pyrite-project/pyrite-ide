import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_backend.dart';
import 'package:pyrite_ide/core/services/file/board_provider.dart';
import 'package:pyrite_ide/core/services/file/file_rename.dart';
import 'package:pyrite_ide/core/services/file/file_sort.dart';
import 'package:pyrite_ide/core/services/logging/app_log.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/serial/active_device_provider.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/utils/display_path.dart';
import 'package:super_tree/super_tree.dart';

/// Directory every top-level row of the board pane hangs under.
const String _boardRootPath = '/';

// ---------------------------------------------------------------------------
// Board file items state
// ---------------------------------------------------------------------------

final boardFileListLoadingProvider = StateProvider<bool>((ref) => false);

/// Whether the root listing has been fetched successfully for the current
/// connection. An empty listing only means "the board has no files" once this
/// is true; otherwise it just means nothing was loaded yet.
final boardFileListLoadedProvider = StateProvider<bool>((ref) => false);

class BoardFileItemsNotifier
    extends StateNotifier<List<TreeNode<FileSystemItem>>> {
  final Ref ref;

  /// The reload currently in flight, and whether another pass is still owed.
  ///
  /// Uploads, downloads and moves each ask for a refresh as they land. Serving
  /// those literally would put one serial round trip per request in line with
  /// the transfer itself, so a request that arrives while a walk is running
  /// only sets [_reloadRequested]: the running loop repeats once more and every
  /// caller receives that trailing result.
  Future<List<TreeNode<FileSystemItem>>>? _reload;
  bool _reloadRequested = false;

  BoardFileItemsNotifier(this.ref) : super(const []) {
    // Re-read the board only when there is something to re-read: a sort change
    // while disconnected would otherwise wait on a port that is not there.
    ref.listen(fileSortModeProvider, (_, _) {
      if (ref.read(boardFileListLoadedProvider) &&
          ref.read(deviceConnectedProvider)) {
        buildRootFileListItems();
      }
    });
  }

  /// Re-reads the board's root listing and replaces the pane's contents.
  ///
  /// Overlapping requests are coalesced (see [_reload]); the returned future
  /// always completes after a listing that started after this call.
  Future<List<TreeNode<FileSystemItem>>> buildRootFileListItems() {
    _reloadRequested = true;
    return _reload ??= _drainReloads();
  }

  /// Asks for a reload without waiting for it, for loops that touch many paths.
  void requestReload() {
    unawaited(buildRootFileListItems());
  }

  Future<List<TreeNode<FileSystemItem>>> _drainReloads() async {
    ref.read(boardFileListLoadingProvider.notifier).state = true;
    try {
      var items = state;
      do {
        _reloadRequested = false;
        items = await _reloadFromDevice();
      } while (_reloadRequested);
      return items;
    } finally {
      ref.read(boardFileListLoadingProvider.notifier).state = false;
      _reload = null;
    }
  }

  Future<List<TreeNode<FileSystemItem>>> _reloadFromDevice() async {
    try {
      final entries = await ref.read(boardProvider).ops.getFileList();
      final items = await buildBoardFileListItems(
        entries,
        sortMode: ref.read(fileSortModeProvider),
      );
      state = items;
      ref.read(boardFileListLoadedProvider.notifier).state = true;
      await ref.read(boardFileTreeViewControllerProvider).replaceRoots(items);
      return items;
    } on DeviceNotReadyException catch (error) {
      debugPrint('[board-tree] refresh skipped: $error');
      return state;
    } on SerialCancelledException catch (error) {
      debugPrint('[board-tree] refresh cancelled: $error');
      return state;
    } on TimeoutException catch (error) {
      debugPrint('[board-tree] refresh timed out: $error');
      return state;
    } catch (error) {
      // Any other listing failure — the port went away mid-batch, the device
      // answered garbage — leaves the previous contents on screen instead of
      // throwing at a caller that only asked for a refresh.
      AppLog.d('file-tree', 'board tree reload failed', error: error);
      return state;
    }
  }

  /// Shows [addedPath] on the board without re-listing the device.
  ///
  /// An upload writes its paths one serial round trip apart, so re-reading the
  /// whole board after each of them would cost more than the transfer itself.
  /// The row is inserted under a folder that is already on screen; the caller's
  /// trailing reload still supplies the device's own names and ordering.
  ///
  /// Does nothing when the row already exists (an overwrite) or when its folder
  /// was never loaded, because there is nothing to hang it under.
  void notePathAdded(String addedPath, {required bool isFolder}) {
    final added = ref.read(boardProvider).ops.normalizeBoardPath(addedPath);
    final controller = ref.read(boardFileTreeViewControllerProvider);
    if (controller.findNodeById(added) != null) return;

    final name = BoardFileOps.boardPath.basename(added);
    final node = TreeNode<FileSystemItem>(
      id: added,
      canLoadChildren: isFolder,
      data: isFolder ? FolderItem(name) : FileItem(name),
    );

    final parentPath = BoardFileOps.boardPath.dirname(added);
    if (parentPath == _boardRootPath) {
      controller.addRoot(node);
      return;
    }
    final parent = controller.findNodeById(parentPath);
    if (parent == null) return;
    // Only a folder whose children are already loaded can take a row: inserting
    // into a folder that will still list itself on expand would make that
    // listing return an id the tree already holds, which is rejected as a
    // duplicate.
    if (parent.canLoadChildren == false) controller.addChild(parent, node);
  }

  void clear() {
    state = const [];
    ref.read(boardFileListLoadedProvider.notifier).state = false;
    unawaited(
      ref.read(boardFileTreeViewControllerProvider).replaceRoots(state),
    );
  }
}

final StateNotifierProvider<
  BoardFileItemsNotifier,
  List<TreeNode<FileSystemItem>>
>
boardFileItemsProvider = StateNotifierProvider(BoardFileItemsNotifier.new);

// ---------------------------------------------------------------------------
// Board tree controller
// ---------------------------------------------------------------------------

final Provider<TreeController<FileSystemItem>>
boardFileTreeViewControllerProvider = Provider((ref) {
  final controller = TreeController<FileSystemItem>(
    onNodeDeleted: (node) async {
      try {
        if (node.data is FolderItem) {
          await ref.read(boardProvider).ops.deleteFolder(node.id);
        } else {
          await ref.read(boardProvider).ops.deleteFile(node.id);
        }
      } on DeviceNotReadyException {
        // Error handled by UI layer
      }
    },
    onNodeRenamed: (node, newName) async {
      final oldPath = node.id;
      final newPath = renamedBoardSiblingPath(oldPath, newName);
      try {
        await ref.read(boardProvider).ops.rename(oldPath, newName);
        await ref
            .read(tabbedViewControllerProvider.notifier)
            .renameBoardOpenPath(oldPath, newPath);
        node.data.name = newName;
        await ref
            .read(boardFileItemsProvider.notifier)
            .buildRootFileListItems();
      } on FileRenameTargetExistsException catch (error) {
        ref
            .read(ideMessageProvider.notifier)
            .error(
              translateWithReplacements(
                ref,
                I18nKey.fileMessageRenameTargetExists,
                {'path': displayPathName(error.targetPath)},
              ),
            );
      } catch (error) {
        ref
            .read(ideMessageProvider.notifier)
            .error(
              translateWithReplacements(ref, I18nKey.fileMessageRenameFailed, {
                'error': error.toString(),
              }),
            );
      }
    },
    loadChildren: (node) async {
      if (node.canLoadChildren == true) {
        return await buildBoardFileListItems(
          await ref.read(boardProvider).ops.getFileList(path: node.id),
          sortMode: ref.read(fileSortModeProvider),
        );
      } else {
        return [];
      }
    },
  );
  // Rows inserted after the tree was built (an uploaded file or folder) have to
  // land where the current sort mode expects them, not at the end of the
  // folder.
  controller.sortComparator = (a, b) => compareFileTreeEntries(
    firstIsFolder: a.data is FolderItem,
    firstName: a.data.name,
    secondIsFolder: b.data is FolderItem,
    secondName: b.data.name,
    mode: ref.read(fileSortModeProvider),
  );
  return controller;
});

final boardEnableDragAndDrop = StateProvider((ref) => false);
