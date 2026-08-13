import 'dart:async';
import 'dart:io';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/core/sdk/view_model_store_provider.dart';
import 'package:pyrite_ide/core/services/editor/file_tab_title.dart';
import 'package:pyrite_ide/core/services/expansion_page.dart';
import 'package:pyrite_ide/core/services/file/local_tree.dart';
import 'package:pyrite_ide/core/services/file/local_backend.dart' as local;
import 'package:pyrite_ide/core/services/file/file_ops.dart';
import 'package:pyrite_ide/core/services/file/file_rename.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/git/git_diff_editor.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:pyrite_ide/features/edit_core/main.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_view_surface.dart';
import 'package:pyrite_ide/pages/editor/welcome.dart';

class TabbedViewControllerNotifier extends StateNotifier<TabbedViewController> {
  final Ref ref;
  VoidCallback? onUnsavedChange;

  /// Monotonic so two tabs hosting the same view never collide, and so a tab
  /// instance can never collide with the sidebar's `container:<id>` instances.
  int _pluginViewTabCounter = 0;

  TabbedViewControllerNotifier(this.ref)
    : super(_buildTabbedViewController(ref));

  static TabbedViewController _buildTabbedViewController(Ref ref) {
    return TabbedViewController([
      TabData(
        closable: false,
        value: TabDataValue(type: "page", filePath: "welcome"),
        text: "${translate(ref, I18nKey.editorWelcomeTab)}   ",
        content: EditorWelcome(),
        leading: (context, status) => Padding(
          padding: EdgeInsetsGeometry.directional(
            start: 5,
            end: 10,
            top: 5,
            bottom: 5,
          ),
          child: Image.asset(
            "assets/icons/app_icon.webp",
            width: 15,
            height: 15,
          ),
        ),
      ),
    ]);
  }

  Future<TabData?> _createNewFileTab(
    File file,
    CodeForgeController? editorController,
    UndoRedoController? undoRedoCntroller, {
    bool isBoardFile = false,
    String? boardFilePath,
    bool isSaved = true,
  }) async {
    if (editorController == null) {
      return null;
    }

    String pattern = "\\";

    if (Platform.isWindows) {
      pattern = "\\";
    } else {
      pattern = "/";
    }

    editorController.setUndoController(undoRedoCntroller);

    TabDataValue value = TabDataValue(
      type: "file",
      filePath: file.path,
      file: file,
      editorController: editorController,
      undoRedoController: undoRedoCntroller,
      isBoardFile: isBoardFile,
      boardFilePath: boardFilePath,
      isSaved: isSaved,
    );

    final tab = TabData(
      leading: (context, status) =>
          _buildFileTabLeading(context, isBoardFile: isBoardFile),
      value: value,
      text: file.path.split(pattern).last,
      keepAlive: true,
      content: EditCore(
        file: file,
        editorController: editorController,
        undoController: undoRedoCntroller,
      ),
    );

    String savedText = editorController.text;
    editorController.addListener(() {
      if (tab.value is TabDataValue) {
        final val = tab.value as TabDataValue;
        final currentText = editorController.text;
        if (currentText == savedText) return;
        savedText = currentText;
        if (_markFileTabUnsaved(tab, val)) {
          _publishTabsPreservingSelection();
          onUnsavedChange?.call();
        }
      }
    });

    return tab;
  }

  void createFile() async {
    final file = await local.sysCreateFile();
    if (file != null) {
      final TabData? newTab = await _createNewFileTab(
        file,
        await ref
            .read(editorControllerMapProvider.notifier)
            .createNewEditorController(file),
        ref
            .read(editorControllerMapProvider.notifier)
            .createNewUndoRedoController(),
      );

      if (newTab == null) {
        debugPrint("cannot open file");
        return;
      }

      state.addTab(newTab);
      refreshFileTabTitles(state.tabs);
      state = TabbedViewController(List.from(state.tabs));
      state.selectTab(newTab);
      ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
    }
  }

  Future openFile(
    BuildContext context, {
    File? file,
    bool isBoardFile = false,
    String? boardFilePath,
    String? initialText,
  }) async {
    file ??= await local.sysGetFile();
    if (file != null) {
      for (TabData tab in state.tabs) {
        final value = tab.value as TabDataValue;
        final sameLocalFile = value.filePath == file.path;
        final sameBoardFile =
            boardFilePath != null && value.boardFilePath == boardFilePath;
        if (sameLocalFile || sameBoardFile) {
          TabbedViewController newController = TabbedViewController(
            List.from(state.tabs),
          );
          newController.selectTab(tab);
          state = newController;
          return;
        }
      }

      final TabData? newTab = await _createNewFileTab(
        file,
        await ref
            .read(editorControllerMapProvider.notifier)
            .createNewEditorController(file, initialText: initialText),
        ref
            .read(editorControllerMapProvider.notifier)
            .createNewUndoRedoController(),
        isBoardFile: isBoardFile,
        boardFilePath: boardFilePath,
      );

      if (newTab == null) {
        return;
      }

      state.addTab(newTab);
      refreshFileTabTitles(state.tabs);

      pendingUploadProviderMap[file.path] = StateProvider((ref) => null);
      pendingDownloadProviderMap[file.path] = StateProvider((ref) => null);

      TabbedViewController newController = TabbedViewController(
        List.from(state.tabs),
      );
      newController.selectTab(newTab);
      state = newController;
      if (context.mounted) {
        if (ResponsiveBreakpoints.of(context).isMobile) {
          ref.read(mobileSelectedIndex.notifier).state = 3;
        } else if (ResponsiveBreakpoints.of(context).isTablet) {
          ref.read(tabletSelectedIndex.notifier).state = 3;
        }
      }
    }
  }

  void renameLocalOpenPath(String oldPath, String newPath) {
    var changed = false;
    for (final tab in state.tabs) {
      final value = tab.value;
      if (value is! TabDataValue ||
          value.type != 'file' ||
          value.isBoardFile == true) {
        continue;
      }
      final renamedPath = rebaseLocalPath(
        value.filePath,
        oldRoot: oldPath,
        newRoot: newPath,
      );
      if (renamedPath == null) continue;
      _replaceFileTab(tab, value, renamedPath, value.boardFilePath);
      changed = true;
    }
    if (changed) _publishRenamedTabs();
  }

  Future<void> renameBoardOpenPath(String oldPath, String newPath) async {
    var changed = false;
    final cacheMigrations = <Future<void>>[];
    for (final tab in state.tabs) {
      final value = tab.value;
      final boardFilePath = value is TabDataValue ? value.boardFilePath : null;
      if (value is! TabDataValue ||
          value.type != 'file' ||
          value.isBoardFile != true ||
          boardFilePath == null) {
        continue;
      }
      final renamedBoardPath = rebaseBoardPath(
        boardFilePath,
        oldRoot: oldPath,
        newRoot: newPath,
      );
      if (renamedBoardPath == null) continue;
      final renamedCachePath = rebaseBoardCachePath(
        oldCachePath: value.filePath,
        oldBoardPath: boardFilePath,
        newBoardPath: renamedBoardPath,
      );
      final controller = value.editorController;
      if (controller != null) {
        cacheMigrations.add(
          _writeBoardCache(
            oldPath: value.filePath,
            newPath: renamedCachePath,
            content: controller.text,
          ),
        );
      }
      _replaceFileTab(tab, value, renamedCachePath, renamedBoardPath);
      changed = true;
    }
    if (changed) _publishRenamedTabs();
    await Future.wait(cacheMigrations);
  }

  void warnOpenFilesOverwritten({
    required bool boardFiles,
    Iterable<String> filePaths = const [],
    Iterable<String> folderPaths = const [],
  }) {
    final result = markOpenFilesAffectedByTransferUnsaved(
      state.tabs,
      boardFiles: boardFiles,
      filePaths: filePaths,
      folderPaths: folderPaths,
    );
    final affectedPaths = result.affectedPaths;
    if (affectedPaths.isEmpty) return;
    _publishTabsPreservingSelection();
    if (result.newlyUnsaved) onUnsavedChange?.call();
    final key = boardFiles
        ? I18nKey.fileMessageOpenBoardFilesOverwritten
        : I18nKey.fileMessageOpenLocalFilesOverwritten;
    ref
        .read(ideMessageProvider.notifier)
        .show(
          translateWithReplacements(ref, key, {
            'count': affectedPaths.length.toString(),
            'path': affectedPaths.first,
          }),
          type: IdeMessageType.warning,
          duration: const Duration(seconds: 12),
          closeable: true,
        );
  }

  void _publishTabsPreservingSelection() {
    final selectedIndex = state.selectedIndex;
    final newController = TabbedViewController(List.from(state.tabs));
    if (selectedIndex != null && selectedIndex < newController.tabs.length) {
      newController.selectedIndex = selectedIndex;
    }
    state = newController;
  }

  void _replaceFileTab(
    TabData tab,
    TabDataValue value,
    String newFilePath,
    String? newBoardFilePath,
  ) {
    final newFile = File(newFilePath);
    ref
        .read(editorControllerMapProvider.notifier)
        .movePath(value.filePath, newFilePath);
    _movePendingFileProviders(value.filePath, newFilePath);
    tab.value = TabDataValue(
      type: value.type,
      filePath: newFilePath,
      file: newFile,
      editorController: value.editorController,
      undoRedoController: value.undoRedoController,
      isBoardFile: value.isBoardFile,
      boardFilePath: newBoardFilePath,
      isSaved: value.isSaved,
      pluginId: value.pluginId,
      viewId: value.viewId,
      viewInstanceId: value.viewInstanceId,
      renderer: value.renderer,
    );
    final editorController = value.editorController;
    if (editorController != null) {
      tab.content = EditCore(
        file: newFile,
        editorController: editorController,
        undoController: value.undoRedoController,
      );
    }
  }

  void _movePendingFileProviders(String oldPath, String newPath) {
    if (oldPath == newPath) return;
    pendingUploadProviderMap[newPath] =
        pendingUploadProviderMap.remove(oldPath) ??
        StateProvider<PendingUpload?>((ref) => null);
    pendingDownloadProviderMap[newPath] =
        pendingDownloadProviderMap.remove(oldPath) ??
        StateProvider<PendingDownload?>((ref) => null);
  }

  void _publishRenamedTabs() {
    final selectedIndex = state.selectedIndex;
    refreshFileTabTitles(state.tabs);
    final newController = TabbedViewController(List.from(state.tabs));
    if (selectedIndex != null && selectedIndex < newController.tabs.length) {
      newController.selectedIndex = selectedIndex;
    }
    state = newController;
  }

  Future<void> _writeBoardCache({
    required String oldPath,
    required String newPath,
    required String content,
  }) async {
    if (path.equals(oldPath, newPath)) return;
    try {
      final newFile = File(newPath);
      await newFile.parent.create(recursive: true);
      await newFile.writeAsString(content);
      final oldFile = File(oldPath);
      if (await oldFile.exists()) await oldFile.delete();
    } catch (error) {
      debugPrint('[editor] failed to migrate board cache: $error');
    }
  }

  void openReadOnlyGitDiff({
    required String filePath,
    required bool staged,
    required String patch,
  }) {
    final tabId = 'git-diff:${staged ? 'staged' : 'unstaged'}:$filePath';
    final tabTitle = _gitDiffTabTitle(ref, filePath, staged);

    for (final tab in state.tabs) {
      final value = tab.value;
      if (value is! TabDataValue ||
          value.type != 'git_diff' ||
          value.filePath != tabId) {
        continue;
      }
      final controller = value.editorController;
      if (controller != null) {
        setGitDiffPatch(controller, patch);
      }
      tab.text = tabTitle;
      final newController = TabbedViewController(List.from(state.tabs));
      newController.selectTab(tab);
      state = newController;
      return;
    }

    final controller = CodeForgeController();
    setGitDiffPatch(controller, patch);
    final tab = TabData(
      leading: (context, status) => Padding(
        padding: const EdgeInsetsGeometry.only(right: 4),
        child: Icon(
          Icons.difference_outlined,
          size: 16,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      value: TabDataValue(
        type: 'git_diff',
        filePath: tabId,
        editorController: controller,
        isSaved: true,
      ),
      text: tabTitle,
      content: GitDiffEditor(controller: controller, filePath: filePath),
    );

    state.addTab(tab);
    final newController = TabbedViewController(List.from(state.tabs));
    newController.selectTab(tab);
    state = newController;
  }

  /// Opens [viewId] as an editor tab hosting a [PluginViewSurface].
  ///
  /// The tab gets its own [ViewInstanceId] so the same view may be open in a tab
  /// and in the sidebar at once as two independent models. Returns the created
  /// instance, or null when the plugin is not running — without a live session
  /// there is nothing to bind the instance to.
  ViewInstanceId? openPluginView({
    required String pluginId,
    required String viewId,
    required String renderer,
    String? title,
    bool expansion = false,
  }) {
    final manager = ref
        .read(pluginRunManagerProvider)
        .entries
        .where((entry) => entry.key.id == pluginId)
        .map((entry) => entry.value)
        .firstOrNull;
    if (manager == null) return null;

    final instanceId = 'tab:${++_pluginViewTabCounter}';
    final instance = ViewInstanceId(
      pluginId: pluginId,
      sessionId: manager.sessionId,
      viewId: viewId,
      instanceId: instanceId,
    );

    final tab = TabData(
      leading: (context, status) => Padding(
        padding: const EdgeInsetsGeometry.only(right: 4),
        child: Icon(
          Icons.extension_outlined,
          size: 16,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      value: TabDataValue(
        type: TabDataValue.pluginViewType,
        filePath: TabDataValue.pluginViewPath(
          pluginId: pluginId,
          viewId: viewId,
          instanceId: instanceId,
        ),
        pluginId: pluginId,
        viewId: viewId,
        viewInstanceId: instanceId,
        renderer: renderer,
      ),
      text: (title == null || title.isEmpty) ? viewId : title,
      content: PluginViewSurface(
        instance: instance,
        renderer: renderer,
        title: title,
      ),
    );

    if (expansion) {
      final controller = ref.read(expansionViewController);
      controller.addTab(tab);
      final newController = TabbedViewController(List.from(controller.tabs));
      newController.selectTab(tab);
      ref.read(expansionViewController.notifier).state = newController;
      return instance;
    }

    state.addTab(tab);
    final newController = TabbedViewController(List.from(state.tabs));
    newController.selectTab(tab);
    state = newController;
    return instance;
  }

  void onTabTap(TabData tabData, int newTabIndex) async {
    // print("tap");
    TabbedViewController newController = TabbedViewController(
      List.from(state.tabs),
    );
    newController.selectedIndex = newTabIndex;
    state = newController;
  }

  void afterTabClose(int index, TabData tabData) async {
    final value = tabData.value;
    refreshFileTabTitles(state.tabs);
    TabbedViewController newController = TabbedViewController(
      List.from(state.tabs),
    );
    state = newController;

    if (value is! TabDataValue) return;
    final filePath = value.filePath;

    if (value.type == 'git_diff') {
      value.editorController?.dispose();
      return;
    }

    // Closing the host must close the instance, otherwise the plugin keeps
    // patching a model nothing renders.
    if (value.isPluginView) {
      final pluginId = value.pluginId;
      final viewId = value.viewId;
      final instanceId = value.viewInstanceId;
      if (pluginId == null || viewId == null || instanceId == null) return;
      final manager = ref
          .read(pluginRunManagerProvider)
          .entries
          .where((entry) => entry.key.id == pluginId)
          .map((entry) => entry.value)
          .firstOrNull;
      if (manager == null) return;
      ref
          .read(viewModelStoreProvider)
          .close(
            ViewInstanceId(
              pluginId: pluginId,
              sessionId: manager.sessionId,
              viewId: viewId,
              instanceId: instanceId,
            ),
          );
      return;
    }

    if (value.type != 'file') return;

    if (pendingUploadProviderMap[filePath] != null) {
      ref.read(pendingUploadProviderMap[filePath]!.notifier).state = null;
    }
    if (pendingDownloadProviderMap[filePath] != null) {
      ref.read(pendingDownloadProviderMap[filePath]!.notifier).state = null;
    }

    if (value.isBoardFile == true) {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  void afterFileSave(TabData tab) {
    if (!state.tabs.contains(tab) || !markFileTabSaved(tab)) return;
    _publishTabsPreservingSelection();
  }

  Future<void> restoreTabs(
    List<PersistedTab> persistedTabs,
    int selectedIndex,
  ) async {
    final List<TabData> tabs = [];

    tabs.addAll(_buildTabbedViewController(ref).tabs);

    for (final persisted in persistedTabs) {
      final file = File(persisted.filePath);
      final exists = await file.exists();
      if (!exists) continue;

      final controller = await ref
          .read(editorControllerMapProvider.notifier)
          .createNewEditorController(
            file,
            initialText: !persisted.isSaved ? persisted.unsavedContent : null,
          );
      if (controller == null) continue;
      final tab = await _createNewFileTab(
        file,
        controller,
        ref
            .read(editorControllerMapProvider.notifier)
            .createNewUndoRedoController(),
        isBoardFile: persisted.isBoardFile,
        boardFilePath: persisted.boardFilePath,
        isSaved: persisted.isSaved,
      );
      if (tab != null) {
        if (!persisted.isSaved) {
          _markFileTabUnsaved(tab, tab.value as TabDataValue);
        }
        tabs.add(tab);
      }
    }

    refreshFileTabTitles(tabs);
    final newController = TabbedViewController(tabs);
    if (selectedIndex > 0 && selectedIndex < tabs.length) {
      newController.selectedIndex = selectedIndex;
    }
    state = newController;
  }
}

String _gitDiffTabTitle(Ref ref, String filePath, bool staged) {
  final fileName = filePath.split(RegExp(r'[\\/]')).last;
  final sideLabel = staged
      ? translate(ref, I18nKey.gitStageStaged)
      : translate(ref, I18nKey.gitChanges);
  return '$fileName · $sideLabel';
}

final StateNotifierProvider<TabbedViewControllerNotifier, TabbedViewController>
tabbedViewControllerProvider = StateNotifierProvider(
  (ref) => TabbedViewControllerNotifier(ref),
);

final _boardTransferPath = path.Context(style: path.Style.posix);

Set<String> findOpenFilesAffectedByTransfer(
  Iterable<TabData> tabs, {
  required bool boardFiles,
  Iterable<String> filePaths = const [],
  Iterable<String> folderPaths = const [],
}) {
  return _visitOpenFilesAffectedByTransfer(
    tabs,
    boardFiles: boardFiles,
    filePaths: filePaths,
    folderPaths: folderPaths,
  );
}

({Set<String> affectedPaths, bool newlyUnsaved})
markOpenFilesAffectedByTransferUnsaved(
  Iterable<TabData> tabs, {
  required bool boardFiles,
  Iterable<String> filePaths = const [],
  Iterable<String> folderPaths = const [],
}) {
  var newlyUnsaved = false;
  final affectedPaths = _visitOpenFilesAffectedByTransfer(
    tabs,
    boardFiles: boardFiles,
    filePaths: filePaths,
    folderPaths: folderPaths,
    onMatch: (tab, value) {
      newlyUnsaved = _markFileTabUnsaved(tab, value) || newlyUnsaved;
    },
  );
  return (affectedPaths: affectedPaths, newlyUnsaved: newlyUnsaved);
}

Set<String> _visitOpenFilesAffectedByTransfer(
  Iterable<TabData> tabs, {
  required bool boardFiles,
  required Iterable<String> filePaths,
  required Iterable<String> folderPaths,
  void Function(TabData tab, TabDataValue value)? onMatch,
}) {
  bool pathsEqual(String first, String second) => boardFiles
      ? _boardTransferPath.equals(first, second)
      : path.equals(first, second);
  bool isWithin(String parent, String child) => boardFiles
      ? _boardTransferPath.isWithin(parent, child)
      : path.isWithin(parent, child);

  final files = filePaths.toList(growable: false);
  final folders = folderPaths.toList(growable: false);
  final affected = <String>{};
  for (final tab in tabs) {
    final value = tab.value;
    if (value is! TabDataValue || value.type != 'file') continue;
    if (boardFiles != (value.isBoardFile == true)) continue;
    final candidate = boardFiles ? value.boardFilePath : value.filePath;
    if (candidate == null || candidate.isEmpty) continue;
    final matchesFile = files.any((target) => pathsEqual(target, candidate));
    final matchesFolder = folders.any(
      (target) => pathsEqual(target, candidate) || isWithin(target, candidate),
    );
    if (matchesFile || matchesFolder) {
      affected.add(candidate);
      onMatch?.call(tab, value);
    }
  }
  return affected;
}

bool _markFileTabUnsaved(TabData tab, TabDataValue value) {
  final newlyUnsaved = value.isSaved;
  value.isSaved = false;
  tab.leading = (context, status) => _buildFileTabLeading(
    context,
    isBoardFile: value.isBoardFile == true,
    isUnsaved: true,
  );
  return newlyUnsaved;
}

bool markFileTabSaved(TabData tab) {
  final value = tab.value;
  if (value is! TabDataValue || value.type != 'file') return false;
  value.isSaved = true;
  tab.leading = (context, status) =>
      _buildFileTabLeading(context, isBoardFile: value.isBoardFile == true);
  return true;
}

Widget _buildFileTabLeading(
  BuildContext context, {
  required bool isBoardFile,
  bool isUnsaved = false,
}) {
  final fileIcon = Icon(
    isBoardFile ? Icons.developer_board_outlined : Icons.description_outlined,
    size: 16,
    color: Theme.of(context).colorScheme.primary,
  );
  return Padding(
    padding: const EdgeInsets.only(right: 4),
    child: isUnsaved
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.circle, size: 8, color: Colors.orange),
              const SizedBox(width: 4),
              fileIcon,
            ],
          )
        : fileIcon,
  );
}
