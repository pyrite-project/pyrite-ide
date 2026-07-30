import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/board_backend.dart';
import 'package:pyrite_ide/core/services/file/board_provider.dart';
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
      node.data.name = newName;
      try {
        await ref.read(boardProvider).ops.rename(node.id, newName);
        ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
      } on DeviceNotReadyException {
        // Error handled by UI layer
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
