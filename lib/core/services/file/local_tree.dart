import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_backend.dart' as local;
import 'package:super_tree/super_tree.dart';

// ---------------------------------------------------------------------------
// Local file items state
// ---------------------------------------------------------------------------

class LocalFileItemsNotifier
    extends StateNotifier<List<TreeNode<FileSystemItem>>> {
  final Ref ref;

  LocalFileItemsNotifier(this.ref) : super(const []);

  Future<List<TreeNode<FileSystemItem>>> buildRootFileListItems() async {
    final items = await local.buildFileListItems(
      await ref.read(fileProvider.notifier).getFileList(),
    );
    state = items;
    return items;
  }

  void openFolder() async {
    await ref.read(fileProvider.notifier).getDirectory();
    buildRootFileListItems();
  }
}

final StateNotifierProvider<
  LocalFileItemsNotifier,
  List<TreeNode<FileSystemItem>>
>
localFileItemsProvider = StateNotifierProvider(
  (ref) => LocalFileItemsNotifier(ref),
);

// ---------------------------------------------------------------------------
// Local tree controller
// ---------------------------------------------------------------------------

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
      ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
    },
    loadChildren: (node) async {
      if (node.canLoadChildren == true) {
        return await local.buildFileListItems(await local.getFileList(node.id));
      } else {
        return [];
      }
    },
  ),
);

final localEnableDragAndDrop = StateProvider((ref) => false);
