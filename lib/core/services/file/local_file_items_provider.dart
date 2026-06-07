import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/local_workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:super_tree/super_tree.dart';

class LocalFileItemsNotifier
    extends StateNotifier<List<TreeNode<FileSystemItem>>> {
  final Ref ref;

  LocalFileItemsNotifier(this.ref) : super(const []);

  Future<List<TreeNode<FileSystemItem>>> buildRootFileListItems() async {
    List<TreeNode<FileSystemItem>> items = await local.buildFileListItems(
      await ref.read(localWorkspaceProvider.notifier).getFilesList(),
    );
    state = items;

    return items;
  }

  void openFolder() async {
    await ref.read(localWorkspaceProvider.notifier).getDirectory();
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
