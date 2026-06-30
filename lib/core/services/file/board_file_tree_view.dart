import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/board_provider.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart' as board;
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:super_tree/super_tree.dart';

final boardFileTreeViewControllerProvider = StateProvider(
  (ref) => TreeController(
    roots: ref.watch(boardFileItemsProvider),
    onNodeDeleted: (node) async {
      try {
        if (node.data is FolderItem) {
          await ref.read(boardProvider.notifier).deleteFolder(node.id);
        } else {
          await ref.read(boardProvider.notifier).deleteFile(node.id);
        }
      } on DeviceNotReadyException {
        // Error handled by UI layer
      }
    },
    onNodeRenamed: (node, newName) async {
      node.data.name = newName;
      try {
        await ref.read(boardProvider.notifier).rename(node.id, newName);
      } on DeviceNotReadyException {
        // Error handled by UI layer
      }
    },
    loadChildren: (node) async {
      if (node.canLoadChildren == true) {
        return await board.buildFileListItems(
          await ref
              .read(boardProvider.notifier)
              .getFileList(path: node.id),
        );
      } else {
        return [];
      }
    },
  ),
);

final boardEnableDragAndDrop = StateProvider((ref) => false);
