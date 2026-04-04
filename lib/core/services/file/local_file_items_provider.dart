import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/file.dart';
import 'package:pyrite_ide/core/services/file/workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:pyrite_ide/shared/toly_tree.dart';

class LocalFileItemsNotifier
    extends StateNotifier<List<TreeNode<LocalFileTreeItem>>> {
  final Ref ref;

  LocalFileItemsNotifier(this.ref) : super(const []);

  Future<List<TreeNode<LocalFileTreeItem>>> buildRootFileListItems() async {
    List<TreeNode<LocalFileTreeItem>> items = await local.buildFileListItems(
      await ref.read(workspaceProvider.notifier).getFilesList(),
    );
    state = items;

    return items;
  }

  void openFolder() async {
    await ref.read(workspaceProvider.notifier).getDirectory();
    buildRootFileListItems();
  }
}

final StateNotifierProvider<
  LocalFileItemsNotifier,
  List<TreeNode<LocalFileTreeItem>>
>
localFileItemsProvider = StateNotifierProvider(
  (ref) => LocalFileItemsNotifier(ref),
);
