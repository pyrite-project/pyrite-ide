import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/file_rename.dart';
import 'package:pyrite_ide/core/services/file/file_sort.dart';
import 'package:pyrite_ide/core/services/file/local_backend.dart' as local;
import 'package:pyrite_ide/core/services/logging/app_log.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/utils/display_path.dart';
import 'package:super_tree/super_tree.dart';

// ---------------------------------------------------------------------------
// Local file items state
// ---------------------------------------------------------------------------

class LocalFileItemsNotifier
    extends StateNotifier<List<TreeNode<FileSystemItem>>> {
  final Ref ref;

  /// The reload currently in flight, and whether another pass is still owed.
  ///
  /// Every write into the workspace — a download, an import, a move, a saved
  /// `.gitignore` — asks for the pane to be re-read. Serving those literally
  /// would start one directory walk per path and let the walks race each
  /// other, so a request that arrives while a walk is running only sets
  /// [_reloadRequested]: the running loop repeats once more and every caller
  /// receives that trailing result.
  Future<List<TreeNode<FileSystemItem>>>? _reload;
  bool _reloadRequested = false;

  LocalFileItemsNotifier(this.ref) : super(const []) {
    // A sort change re-reads the open folder so the new order also reaches the
    // folders that are already expanded, not just the next one opened.
    ref.listen(fileSortModeProvider, (_, _) {
      if (ref.read(fileProvider) != null) buildRootFileListItems();
    });
  }

  /// Re-reads the open workspace and replaces the pane's contents.
  ///
  /// Overlapping requests are coalesced (see [_reload]); the returned future
  /// always completes after a walk that started after this call, so a caller
  /// that awaits it can treat the pane as up to date.
  Future<List<TreeNode<FileSystemItem>>> buildRootFileListItems() {
    _reloadRequested = true;
    return _reload ??= _drainReloads();
  }

  /// Asks for a reload without waiting for it.
  ///
  /// For a loop that touches many paths at once: the coalescing above turns
  /// them into a single walk without the caller awaiting every one.
  void requestReload() {
    unawaited(buildRootFileListItems());
  }

  Future<List<TreeNode<FileSystemItem>>> _drainReloads() async {
    try {
      var items = state;
      do {
        _reloadRequested = false;
        items = await _reloadFromDisk();
      } while (_reloadRequested);
      return items;
    } finally {
      _reload = null;
    }
  }

  Future<List<TreeNode<FileSystemItem>>> _reloadFromDisk() async {
    try {
      final items = await local.buildFileListItems(
        await ref.read(fileProvider.notifier).getFileList(),
        sortMode: ref.read(fileSortModeProvider),
      );
      state = items;
      await ref.read(localFileTreeViewControllerProvider).replaceRoots(items);
      return items;
    } catch (error) {
      // A workspace on a share that went away must not blank the pane or throw
      // at callers that only asked for a refresh: the previous contents stay
      // and the failure is readable in the log.
      AppLog.d('file-tree', 'local tree reload failed', error: error);
      // `state` of a disposed notifier throws too, and this is the catch block
      // itself — the second error would escape it and reach callers that never
      // saw the reload (a git operation finishing after the pane closed).
      return mounted ? state : const <TreeNode<FileSystemItem>>[];
    }
  }

  /// Adds [addedPath] to the pane the moment it exists, without re-reading the
  /// workspace.
  ///
  /// Downloads, imports and moves write one path at a time, and each of them
  /// has to appear as it lands instead of at the end of a batch that may still
  /// be cancelled. Only the row is inserted — ordering, names and the
  /// git-ignored styling still come from the full reload that follows.
  ///
  /// Does nothing when the row already exists or when the folder it belongs to
  /// was never loaded, because there is nothing to hang it under.
  Future<void> notePathAdded(String addedPath, {required bool isFolder}) async {
    final added = path.normalize(addedPath);
    final controller = ref.read(localFileTreeViewControllerProvider);
    if (controller.findNodeById(added) != null) return;

    // A `.gitignore` decides the styling of rows that are already on screen,
    // and only a full re-read recomputes those flags.
    if (local.isGitIgnoreFilePath(added)) {
      await buildRootFileListItems();
      return;
    }

    var isGitIgnored = false;
    try {
      isGitIgnored = (await local.gitIgnoredPaths([added])).isNotEmpty;
    } catch (error) {
      // Showing the row without its ignored styling beats not showing it; the
      // trailing reload recomputes the flags from a real listing.
      AppLog.d(
        'file-tree',
        'git ignore probe failed path=$added',
        error: error,
      );
    }

    final name = path.basename(added);
    final node = TreeNode<FileSystemItem>(
      id: added,
      canLoadChildren: isFolder,
      data: isFolder
          ? local.LocalFolderItem(name, isGitIgnored: isGitIgnored)
          : local.LocalFileItem(name, isGitIgnored: isGitIgnored),
    );

    final parent = controller.findNodeById(path.dirname(added));
    if (parent != null) {
      // Only a folder whose children are already loaded can take a row:
      // inserting into a folder that will still list itself on expand would
      // make that listing return an id the tree already holds, which is
      // rejected as a duplicate. A collapsed folder has no visible row to
      // update anyway, and its own listing picks the path up when expanded.
      if (parent.canLoadChildren == false) controller.addChild(parent, node);
      return;
    }

    // The pane's roots are the workspace folder's own children, so a path whose
    // parent is the workspace sits at the top level.
    final workspace = ref.read(fileProvider)?.path;
    if (workspace != null &&
        path.equals(path.normalize(workspace), path.dirname(added))) {
      controller.addRoot(node);
    }
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
localFileItemsProvider = StateNotifierProvider(LocalFileItemsNotifier.new);

// ---------------------------------------------------------------------------
// Local tree controller
// ---------------------------------------------------------------------------

final Provider<TreeController<FileSystemItem>>
localFileTreeViewControllerProvider = Provider((ref) {
  final controller = TreeController<FileSystemItem>(
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
        return await local.buildFileListItems(
          await local.getFileList(node.id),
          sortMode: ref.read(fileSortModeProvider),
        );
      } else {
        return [];
      }
    },
  );
  // Rows inserted after the tree was built (a created file, a downloaded one,
  // an uploaded folder) have to land where the current sort mode expects them,
  // not at the end of the folder.
  controller.sortComparator = (a, b) => compareFileTreeEntries(
    firstIsFolder: a.data is FolderItem,
    firstName: a.data.name,
    secondIsFolder: b.data is FolderItem,
    secondName: b.data.name,
    mode: ref.read(fileSortModeProvider),
  );
  return controller;
});

final localEnableDragAndDrop = StateProvider((ref) => false);
