import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:super_tree/super_tree.dart';

final localFileTreeViewControllerProvider = StateProvider(
  (ref) => TreeController(
    roots: ref.watch(localFileItemsProvider),
    onNodeDeleted: (node) {
      if (node.data is FolderItem) {
        local.deleteDir(node.id);
      } else {
        local.deleteFile(node.id);
      }
    },
    onNodeRenamed: (node, newName) {
      node.data.name = newName;
      if (node.data is FolderItem) {
        local.renameDir(node.id, newName);
      } else {
        local.renameFile(node.id, newName);
      }
      // ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
    },
    loadChildren: (node) async {
      // print(node.isExpanded);
      if (node.canLoadChildren == true) {
        return await local.buildFileListItems(
          await local.getFilesList(node.id),
        );
      } else {
        return [];
      }
    },
  ),
);

final localEnableDragAndDrop = StateProvider((ref) => false);
