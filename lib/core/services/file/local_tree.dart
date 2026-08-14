import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/file_rename.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_backend.dart' as local;
import 'package:pyrite_ide/core/services/message/ide_message.dart';
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
    await ref.read(localFileTreeViewControllerProvider).replaceRoots(items);
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

final Provider<TreeController<FileSystemItem>>
localFileTreeViewControllerProvider = Provider(
  (ref) => TreeController<FileSystemItem>(
    onNodeDeleted: (node) {
      if (node.data is FolderItem) {
        local.deleteDir(node.id);
      } else {
        local.deleteFile(node.id);
      }
    },
    onNodeRenamed: (node, newName) async {
      final oldPath = node.id;
      try {
        final newPath = node.data is FolderItem
            ? await local.renameDir(oldPath, newName)
            : await local.renameFile(oldPath, newName);
        ref
            .read(tabbedViewControllerProvider.notifier)
            .renameLocalOpenPath(oldPath, newPath);
        node.data.name = newName;
        await ref
            .read(localFileItemsProvider.notifier)
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
        return await local.buildFileListItems(await local.getFileList(node.id));
      } else {
        return [];
      }
    },
  ),
);

final localEnableDragAndDrop = StateProvider((ref) => false);
