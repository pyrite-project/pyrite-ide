import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_backend.dart';
import 'package:pyrite_ide/core/services/file/board_provider.dart';
import 'package:pyrite_ide/core/services/file/file_rename.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';
import 'package:super_tree/super_tree.dart';

// ---------------------------------------------------------------------------
// Board file items state
// ---------------------------------------------------------------------------

final boardFileListLoadingProvider = StateProvider<bool>((ref) => false);

class BoardFileItemsNotifier
    extends StateNotifier<List<TreeNode<FileSystemItem>>> {
  final Ref ref;

  BoardFileItemsNotifier(this.ref) : super(const []);

  Future<List<TreeNode<FileSystemItem>>> buildRootFileListItems() async {
    ref.read(boardFileListLoadingProvider.notifier).state = true;
    try {
      final entries = await ref.read(boardProvider).ops.getFileList();
      final items = await buildBoardFileListItems(entries);
      state = items;
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
    } finally {
      ref.read(boardFileListLoadingProvider.notifier).state = false;
    }
  }

  void clear() {
    state = const [];
  }
}

final StateNotifierProvider<
  BoardFileItemsNotifier,
  List<TreeNode<FileSystemItem>>
>
boardFileItemsProvider = StateNotifierProvider(
  (ref) => BoardFileItemsNotifier(ref),
);

// ---------------------------------------------------------------------------
// Board tree controller
// ---------------------------------------------------------------------------

final boardFileTreeViewControllerProvider = StateProvider(
  (ref) => TreeController(
    roots: ref.watch(boardFileItemsProvider),
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
                {'path': error.targetPath},
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
        );
      } else {
        return [];
      }
    },
  ),
);

final boardEnableDragAndDrop = StateProvider((ref) => false);
