import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/board_workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart' as board;
import 'package:super_tree/super_tree.dart';

final boardFileTreeViewControllerProvider = StateProvider(
  (ref) => TreeController(
    roots: ref.watch(boardFileItemsProvider),
    onNodeDeleted: (node) {
      if (node.data is FolderItem) {
        ref.read(boardWorkspaceProvider.notifier).deleteFolder(node.id);
      } else {
        ref.read(boardWorkspaceProvider.notifier).deleteFile(node.id);
      }
    },
    onNodeRenamed: (node, newName) {
      node.data.name = newName;
      if (node.data is FolderItem) {
        ref.read(boardWorkspaceProvider.notifier).rename(node.id, newName);
      } else {
        ref.read(boardWorkspaceProvider.notifier).rename(node.id, newName);
      }
      // ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
    },
    loadChildren: (node) async {
      // print(node.isExpanded);
      if (node.canLoadChildren == true) {
        return await board.buildFileListItems(
          await ref
              .read(boardFileItemsProvider.notifier)
              .getFilesList(path: node.id),
        );
      } else {
        return [];
      }
    },
  ),
);

final boardEnableDragAndDrop = StateProvider((ref) => false);
