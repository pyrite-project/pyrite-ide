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
import 'package:pyrite_ide/core/services/editor/external_change_dialog.dart';
import 'package:pyrite_ide/core/services/editor/exclusive_pass.dart';
import 'package:pyrite_ide/core/services/editor/external_file_change.dart';
import 'package:pyrite_ide/core/services/editor/file_open_codec.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/core/sdk/view_model_store_provider.dart';
import 'package:pyrite_ide/core/services/editor/file_tab_title.dart';
import 'package:pyrite_ide/core/services/expansion_page.dart';
import 'package:pyrite_ide/core/services/file/canonical_path.dart';
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

  /// Per-path unsaved-change listeners added to editor controllers, kept so
  /// they can be removed when the tab closes.
  final Map<String, VoidCallback> _unsavedListeners = {};

  /// Exact text last written to (or last read from) the tab's backing store,
  /// keyed by file path.
  ///
  /// This is the baseline the editor's unsaved listener diffs against, so it
  /// has to be captured from the same source the save path writes to. A `null`
  /// entry means "no baseline known", which the listener treats as not-dirty
  /// rather than guessing.
  final Map<String, String> _lastSavedText = {};

  /// What was on disk for each open path the last time the editor looked, so a
  /// change made by another program can be told apart from our own writes.
  ///
  /// Keyed by the same path as [_lastSavedText], and maintained at the two
  /// moments the editor itself is responsible for the bytes: opening a file and
  /// writing it back.
  final Map<String, FileDiskStamp> _diskStamps = {};

  /// Serializes disk reconciliation.
  ///
  /// Reconciliation is driven from two independent places -- the window focus
  /// check and the save path -- and the focus check is fired unawaited on every
  /// activation, several of which can arrive while the first pass is still
  /// sitting on its dialog. Two passes then both see the same unresolved
  /// conflict and each opens a copy, so the dialogs stack: the user has to
  /// click through them one at a time and the barriers pile up behind.
  final ExclusivePass _reconcilePass = ExclusivePass();

  /// The disk state a cancelled prompt was about, keyed by file path.
  ///
  /// Cancel means "leave the buffer alone for now", not "ask me about the same
  /// bytes again every time the window comes back". The stamp is kept so a
  /// later change on disk raises the question anew. The save path deliberately
  /// ignores this: it is about to destroy the other program's work, so it asks
  /// every time.
  final Map<String, FileDiskStamp> _declinedExternalChanges = {};

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

    /// Text the backing store holds for this path, when it differs from the
    /// buffer being opened.
    ///
    /// Only a restored unsaved session needs this: the buffer holds
    /// `unsavedContent` while the file on disk still holds the last saved
    /// bytes, and that on-disk text is the baseline "modified" is measured
    /// against. A normal open needs no argument because the buffer *is* the
    /// stored text.
    String? savedBaseline,

    /// Character set the buffer was decoded from, carried so a save can write
    /// the file back in the same encoding instead of transcoding to UTF-8.
    String? encoding,
    bool byteOrderMark = false,
  }) async {
    file = File(canonicalLocalPath(file.path));
    if (editorController == null) {
      return null;
    }

    ensurePendingFileProviders(file.path);

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
      encoding: encoding,
      byteOrderMark: byteOrderMark,
    );

    final tab = TabData(
      leading: (context, status) =>
          _buildFileTabLeading(context, isBoardFile: isBoardFile),
      value: value,
      text: path.basename(file.path),
      keepAlive: true,
      content: EditCore(
        file: file,
        editorController: editorController,
        undoController: undoRedoCntroller,
      ),
    );

    // A previous tab for this path may still hold a listener (e.g. after a
    // rename re-key); never stack duplicates on the same controller.
    final staleListener = _unsavedListeners.remove(file.path);
    if (staleListener != null) {
      editorController.displayChanges.removeListener(staleListener);
    }

    // Baseline for the content-based dirty check below. An unsaved restore is
    // seeded with the restored buffer so the dot matches `isSaved: false`
    // without having to be re-derived.
    _lastSavedText[file.path] = savedBaseline ?? editorController.text;
    // Whatever is on disk right now is by definition the text this tab was
    // opened from, so it is the stamp the next external-change check compares
    // against.
    unawaited(_recordDiskStamp(file));

    // Subscribes to `displayChanges`, not to the controller directly.
    //
    // The controller notifies from inside the editor's own lifecycle — its
    // `initState` clears diagnostics through `openedFile`, and bracket
    // highlighting, fold recomputation and the buffer flush a caret move
    // triggers all run during its build. A listener attached to the controller
    // itself is therefore invoked while the tree is building, and the write
    // below reaches `TabData.leading`, which is a ChangeNotifier setter that
    // forwards through `TabbedViewController` to `TabbedView.setState` — a
    // "marked as needing to be built during build" throw.
    //
    // `displayChanges` is the controller's frame-safe signal for exactly this
    // kind of out-of-subtree consumer.
    //
    // The dirty state is derived from the *text*, not from `contentVersion`.
    // A version bump only means "some mutating API was called": undo/redo, a
    // no-op backspace at offset 0, applying a workspace edit that rewrites the
    // buffer with identical content, or a save-time format that reformats to
    // the same bytes all bump it without changing the document. Keying off the
    // version therefore lit the modified dot on tabs the user never touched.
    // Comparing against the last persisted text is O(n), but it only runs when
    // the version moved, and it is what "modified" actually means.
    var lastSeenVersion = editorController.contentVersion;
    void unsavedListener() {
      if (tab.value is! TabDataValue) return;
      final currentVersion = editorController.contentVersion;
      if (currentVersion == lastSeenVersion) return;
      lastSeenVersion = currentVersion;
      final value = tab.value as TabDataValue;
      // Applies the transition itself rather than returning a flag the caller
      // has to interpret. A bare `bool` here is a trap: the value means "is
      // saved", but the interesting branch is "is dirty", and mixing the two
      // up silently inverts every outcome without any type error. Keeping the
      // mapping in one place is what makes that inversion impossible.
      final changed = applyDirtyState(
        tab,
        savedText: _lastSavedText[value.filePath],
        currentText: editorController.text,
      );
      if (!changed) return;
      if (!value.isSaved) onUnsavedChange?.call();
      _publishTabsPreservingSelection();
    }

    _unsavedListeners[file.path] = unsavedListener;
    editorController.displayChanges.addListener(unsavedListener);

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
      // Tab identity is the exact filePath string, so the incoming path must
      // carry the spelling tabs were created with — e.g. a jump target handed
      // over by a language server spells the drive `e:` where the file tree
      // spells `E:`. Without this, the same file opens a second tab.
      file = File(canonicalLocalPath(file.path));
      // Lexical normalization still leaves a symlink and its target (or two
      // casings of one Windows directory) looking like different files, so the
      // duplicate check compares resolved identities as well.
      final identity = openFileIdentity(file.path);
      for (TabData tab in state.tabs) {
        final value = tab.value as TabDataValue;
        final sameLocalFile =
            value.filePath == file.path ||
            (value.isBoardFile != true &&
                openFileIdentity(value.filePath) == identity);
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

      // Fresh file: classify its bytes before anything reaches a tab. Binary
      // files get a warning (open read-only or abort), non-UTF-8 text gets an
      // encoding retry; unreadable files fall through to the old no-op.
      var text = initialText;
      var openReadOnly = false;
      String? encoding;
      var byteOrderMark = false;
      if (text == null) {
        final FileTextPreparation prepared;
        try {
          prepared = await prepareFileForEditing(file);
        } on FileSystemException {
          return;
        }
        switch (prepared) {
          case BinaryFilePrepared():
            if (!context.mounted) return;
            final proceed = await showBinaryFileDialog(
              ref,
              context,
              filePath: file.path,
            );
            if (!proceed) return;
            text = prepared.text;
            openReadOnly = prepared.readOnly;
          case UndecodableFilePrepared():
            if (!context.mounted) return;
            final decoded = await showEncodingRetryDialog(
              ref,
              context,
              filePath: file.path,
              bytes: prepared.bytes,
            );
            if (decoded == null) return;
            text = decoded.text;
            encoding = decoded.encoding;
          default:
            text = prepared.text;
            openReadOnly = prepared.readOnly;
            encoding = prepared.encoding;
            byteOrderMark = prepared.byteOrderMark;
        }
      }

      final TabData? newTab = await _createNewFileTab(
        file,
        await ref
            .read(editorControllerMapProvider.notifier)
            .createNewEditorController(
              file,
              initialText: text,
              openReadOnly: openReadOnly,
            ),
        ref
            .read(editorControllerMapProvider.notifier)
            .createNewUndoRedoController(),
        isBoardFile: isBoardFile,
        boardFilePath: boardFilePath,
        encoding: encoding,
        byteOrderMark: byteOrderMark,
      );

      if (newTab == null) {
        return;
      }

      state.addTab(newTab);
      refreshFileTabTitles(state.tabs);

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

    // Re-seed the diff baseline to the buffer's current contents.
    //
    // These tabs are marked unsaved because the file changed *underneath* them,
    // not because their buffer moved. The old baseline is the text as of the
    // last write, which the transfer has now replaced. If it were left in
    // place, the next edit followed by an undo would diff back to the original
    // text, match it, and silently clear a dot that is still legitimately set.
    // Pinning the baseline to the buffer means the tab can only return to clean
    // by an actual save, which is the intended behaviour.
    _lastSavedText.addAll(
      reseedOpenFileTransferBaselines(
        state.tabs,
        boardFiles: boardFiles,
        affectedPaths: affectedPaths,
      ),
    );

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

  /// Republishes the tab list so listeners (and the tab strip) see the new
  /// `TabDataValue` instances produced by the dirty/saved transitions.
  ///
  /// No frame guard is needed here: the only caller that can run mid-frame is
  /// the editor's unsaved listener, and `CodeForgeController.notifyListeners`
  /// now defers out of the build phase before reaching it.
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
      tabId: value.tabId,
      file: newFile,
      editorController: value.editorController,
      undoRedoController: value.undoRedoController,
      isBoardFile: value.isBoardFile,
      boardFilePath: newBoardFilePath,
      isSaved: value.isSaved,
      encoding: value.encoding,
      byteOrderMark: value.byteOrderMark,
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
    final upload = pendingUploadProviderMap.remove(oldPath);
    final download = pendingDownloadProviderMap.remove(oldPath);
    pendingUploadProviderMap[newPath] =
        upload ?? StateProvider<PendingUpload?>((ref) => null);
    pendingDownloadProviderMap[newPath] =
        download ?? StateProvider<PendingDownload?>((ref) => null);
    final listener = _unsavedListeners.remove(oldPath);
    if (listener != null) {
      _unsavedListeners[newPath] = listener;
    }
    // The dirty baseline is keyed by path, so it has to follow the rename.
    // Carry the text across rather than dropping it: the buffer is unchanged
    // by a rename, so the old baseline is still the right one, and dropping it
    // would leave a genuinely dirty tab with nothing to diff against.
    final baseline = _lastSavedText.remove(oldPath);
    if (baseline != null) {
      _lastSavedText[newPath] = baseline;
    }
    // Same for the on-disk stamp: a rename does not move the bytes, and
    // dropping the stamp would make the first check after the rename read the
    // file again and report our own rename as an external edit.
    final stamp = _diskStamps.remove(oldPath);
    if (stamp != null) {
      _diskStamps[newPath] = stamp;
    }
    // A rename does not change the bytes either, so a conflict the user
    // declined for the old path is still declined for the new one.
    final declined = _declinedExternalChanges.remove(oldPath);
    if (declined != null) {
      _declinedExternalChanges[newPath] = declined;
    }
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

  void closePluginView(TabDataValue value) {
    if (!value.isPluginView) return;
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
      closePluginView(value);
      return;
    }

    if (value.type != 'file') return;

    if (pendingUploadProviderMap[filePath] != null) {
      ref.read(pendingUploadProviderMap[filePath]!.notifier).state = null;
    }
    if (pendingDownloadProviderMap[filePath] != null) {
      ref.read(pendingDownloadProviderMap[filePath]!.notifier).state = null;
    }
    releasePendingFileProviders(filePath);

    if (value.isBoardFile == true) {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    // Release the editor resources for the closed tab: drop its unsaved
    // listener, remove it from the controller map, and dispose the editor
    // (which also closes its LSP connection/subprocess) and undo stack.
    _unsavedListeners.remove(filePath);
    _lastSavedText.remove(filePath);
    _diskStamps.remove(filePath);
    _declinedExternalChanges.remove(filePath);
    ref.read(editorControllerMapProvider.notifier).removePath(filePath);
    value.editorController?.dispose();
    value.undoRedoController?.dispose();
  }

  /// Marks a tab clean after its buffer was written to the backing store.
  ///
  /// The text is read back here rather than trusted from the caller so the
  /// diff baseline matches exactly what was persisted, including a save-time
  /// format pass that may have rewritten the buffer between the write and this
  /// call.
  void afterFileSave(TabData tab) {
    final value = tab.value;
    if (value is! TabDataValue) return;
    final controller = value.editorController;
    if (controller != null) {
      _lastSavedText[value.filePath] = controller.text;
    }
    // Our own write is not an external change; move the stamp forward so the
    // next check does not report the save as someone else's edit.
    unawaited(_recordDiskStamp(value.file ?? File(value.filePath)));
    if (!state.tabs.contains(tab) || !markFileTabSaved(tab)) return;
    _publishTabsPreservingSelection();
  }

  Future<void> _recordDiskStamp(File file) async {
    final stamp = await statFileStamp(file);
    if (stamp == null) {
      _diskStamps.remove(file.path);
      return;
    }
    _diskStamps[file.path] = stamp;
  }

  /// Reconciles every open local file with what is on disk now.
  ///
  /// Called when the window regains focus, which is when a user is most likely
  /// to have just switched back from the editor that changed the file. Without
  /// it, a change made elsewhere is invisible until a save silently discards
  /// it — or throws on a file that was deleted outright.
  ///
  /// Opportunistic by design: a pass that is already running is reading the
  /// same files at this moment and its prompt, if any, is still on screen.
  /// Queueing behind it would only produce the same dialog a second time once
  /// the user answers the first, so a burst of focus events is dropped
  /// instead -- the running pass sees everything this one would have.
  Future<void> checkExternalChanges(BuildContext context) {
    return _reconcilePass.runIfIdle(() async {
      for (final tab in List<TabData>.from(state.tabs)) {
        final value = tab.value;
        if (value is! TabDataValue ||
            value.type != 'file' ||
            value.isBoardFile == true) {
          continue;
        }
        if (!context.mounted) return;
        await _reconcileTabWithDisk(context, tab, value);
      }
    });
  }

  /// The save-path half of [checkExternalChanges].
  ///
  /// Returns false when the user cancelled, in which case the caller must not
  /// write. Reloading here means the caller writes the text it just read, so
  /// the buffer and the file agree either way the user picks.
  Future<bool> confirmSaveOverwritesExternalChange(
    BuildContext context,
    TabData tab,
  ) {
    // Unlike the focus check this one cannot be dropped: the answer decides
    // whether the save writes at all. It waits its turn, then reconciles the
    // tab itself -- by then the pass ahead of it has already recorded whatever
    // the user decided, so this one usually exits on the cheap stamp compare.
    return _reconcilePass.run(() async {
      final value = tab.value;
      if (value is! TabDataValue ||
          value.type != 'file' ||
          value.isBoardFile == true) {
        return true;
      }
      final decision = await _reconcileTabWithDisk(
        context,
        tab,
        value,
        onSaveConflict: true,
      );
      return decision != ExternalChangeAction.prompt;
    });
  }

  /// Applies [planExternalChange] for one tab and reports what it did.
  Future<ExternalChangeAction> _reconcileTabWithDisk(
    BuildContext context,
    TabData tab,
    TabDataValue value, {
    bool onSaveConflict = false,
  }) async {
    final file = value.file;
    if (file == null) return ExternalChangeAction.none;
    final currentStamp = await statFileStamp(file);
    final exists = currentStamp != null;
    final previousStamp = _diskStamps[value.filePath];

    // Cheap exit: nothing about this path moved since we last looked.
    if (exists && previousStamp != null && previousStamp.sameAs(currentStamp)) {
      return ExternalChangeAction.none;
    }

    final diskText = exists ? await readDiskText(file) : null;
    final action = planExternalChange(
      exists: exists,
      previousStamp: previousStamp,
      currentStamp: currentStamp,
      diskText: diskText,
      baseline: _lastSavedText[value.filePath],
      tabIsDirty: value.isSaved != true,
    );

    switch (action) {
      case ExternalChangeAction.none:
        _declinedExternalChanges.remove(value.filePath);
        if (currentStamp != null) _diskStamps[value.filePath] = currentStamp;
      case ExternalChangeAction.touchOnly:
        _declinedExternalChanges.remove(value.filePath);
        if (currentStamp != null) _diskStamps[value.filePath] = currentStamp;
      case ExternalChangeAction.deleted:
        _diskStamps.remove(value.filePath);
        _declinedExternalChanges.remove(value.filePath);
        // The buffer stays readable — the user may still want to copy out of it
        // or undo — but a save must not recreate a file someone deliberately
        // removed.
        value.editorController?.readOnly = true;
        ref
            .read(ideMessageProvider.notifier)
            .show(
              translateWithReplacements(ref, I18nKey.editorFileDeletedOnDisk, {
                'path': value.filePath,
              }),
              type: IdeMessageType.warning,
              duration: const Duration(seconds: 12),
              closeable: true,
            );
      case ExternalChangeAction.reload:
        _declinedExternalChanges.remove(value.filePath);
        await _reloadTabFromDisk(tab, value, diskText!);
      case ExternalChangeAction.prompt:
        if (!context.mounted) return action;
        // Planning a prompt means the file is there, so the stamp is too.
        final stamp = currentStamp!;
        final declinedStamp = _declinedExternalChanges[value.filePath];
        if (declinedStamp != null) {
          if (declinedStamp.sameAs(stamp)) {
            if (!onSaveConflict) {
              // The user already said "not now" about these exact bytes, and
              // the file has not moved since. Reopening this on the next window
              // activation is nagging about a conflict they are aware of. A
              // save is the opposite case: it is about to overwrite the other
              // program's work, so it asks every time.
              return action;
            }
          } else {
            // The file moved on since they declined, so what they were shown
            // is no longer what is on disk.
            _declinedExternalChanges.remove(value.filePath);
          }
        }
        final resolution = await showExternalChangeDialog(
          ref,
          context,
          filePath: value.filePath,
          onSaveConflict: onSaveConflict,
        );
        if (resolution == ExternalChangeResolution.reload) {
          _declinedExternalChanges.remove(value.filePath);
          await _reloadTabFromDisk(tab, value, diskText);
        } else if (resolution == ExternalChangeResolution.keepEditor) {
          _declinedExternalChanges.remove(value.filePath);
          // The user chose this buffer's version, so its content becomes the
          // baseline: the next check must not raise the same conflict again
          // for a difference we have already resolved.
          _lastSavedText[value.filePath] = diskText ?? '';
          _diskStamps[value.filePath] = stamp;
        } else {
          // Cancelled, or the dialog was dismissed. Remember the state so the
          // focus check does not reopen it on the very next activation.
          _declinedExternalChanges[value.filePath] = stamp;
        }
    }
    return action;
  }

  Future<void> _reloadTabFromDisk(
    TabData tab,
    TabDataValue value,
    String? diskText,
  ) async {
    final controller = value.editorController;
    if (controller == null || diskText == null) return;
    _lastSavedText[value.filePath] = diskText;
    controller.text = diskText;
    // The undo stack describes edits against the buffer that just went away;
    // leaving it in place would let a single undo resurrect stale content over
    // a freshly loaded file.
    value.undoRedoController?.clear();
    await _recordDiskStamp(value.file ?? File(value.filePath));
    markFileTabSaved(tab);
    _publishTabsPreservingSelection();
    ref
        .read(ideMessageProvider.notifier)
        .success(
          translateWithReplacements(ref, I18nKey.editorFileReloadedFromDisk, {
            'path': value.filePath,
          }),
        );
  }

  Future<void> restoreTabs(
    List<PersistedTab> persistedTabs,
    int selectedIndex, {
    String? selectedTabPath,
  }) async {
    final List<TabData> tabs = [];

    tabs.addAll(_buildTabbedViewController(ref).tabs);

    for (final persisted in persistedTabs) {
      final file = File(persisted.filePath);
      final exists = await file.exists();
      if (!exists) continue;

      // Classify the bytes once, here, for two reasons the headless path
      // cannot get any other way: a non-UTF-8 file would make the controller's
      // own `readAsString` throw, and the encoding is what lets a later save
      // write the file back in its original character set. There is no context
      // for the encoding picker during a restore, so an undecodable file keeps
      // falling through to the controller's malformed-tolerant read-only path.
      String? restoredEncoding;
      var restoredByteOrderMark = false;
      String? savedBaseline;
      String? initialText;
      var restoreReadOnly = false;
      try {
        final prepared = await prepareFileForEditing(file);
        switch (prepared) {
          case UndecodableFilePrepared():
            break;
          case BinaryFilePrepared():
            initialText = prepared.text;
            restoreReadOnly = true;
          default:
            initialText = prepared.text;
            restoredEncoding = prepared.encoding;
            restoredByteOrderMark = prepared.byteOrderMark;
            restoreReadOnly = prepared.readOnly;
        }
        // The on-disk text is the baseline for an unsaved restore: the buffer is
        // seeded with the unsaved content, so without this the comparison would
        // measure the buffer against itself and the dot would never clear.
        savedBaseline = prepared.text;
      } on FileSystemException {
        continue;
      }

      final controller = await ref
          .read(editorControllerMapProvider.notifier)
          .createNewEditorController(
            file,
            initialText: persisted.isSaved
                ? initialText
                : persisted.unsavedContent,
            openReadOnly: restoreReadOnly,
          );
      if (controller == null) continue;
      // Seed the fold state before the tab is built: the editor hydrates its
      // fold cache from `controller.foldings` when it mounts, so collapsed
      // regions are honored from the first layout.
      controller.restoreFoldedRanges(_foldSnapshots(persisted.foldedRanges));
      final tab = await _createNewFileTab(
        file,
        controller,
        ref
            .read(editorControllerMapProvider.notifier)
            .createNewUndoRedoController(),
        isBoardFile: persisted.isBoardFile,
        boardFilePath: persisted.boardFilePath,
        isSaved: persisted.isSaved,
        savedBaseline: persisted.isSaved ? null : savedBaseline,
        encoding: restoredEncoding,
        byteOrderMark: restoredByteOrderMark,
      );
      if (tab != null) {
        if (!persisted.isSaved) {
          _markFileTabUnsaved(tab, tab.value as TabDataValue);
        }
        _restoreViewPosition(controller, persisted);
        tabs.add(tab);
      }
    }

    refreshFileTabTitles(tabs);
    final newController = TabbedViewController(tabs);
    final restoredIndex = _resolveRestoredSelection(
      tabs,
      selectedTabPath,
      selectedIndex,
    );
    if (restoredIndex != null) {
      newController.selectedIndex = restoredIndex;
    }
    state = newController;
  }

  /// Puts the caret and viewport back where they were.
  ///
  /// The caret is clamped to the current document: the file may have shrunk on
  /// disk while the app was closed, so the saved offset can point past the
  /// end. Only the caret offset itself can be applied to a controller with no
  /// mounted editor — the scroll always needs the editor's viewport.
  ///
  /// The viewport restores by topmost visible line rather than pixel offset,
  /// which survives font-size changes and resizes between sessions. When a
  /// saved line exists it wins over centering the caret — it is what the user
  /// actually saw — and it is handed to the controller as a pending viewport
  /// line the editor consumes on mount: a post-frame scroll would silently
  /// miss background tabs whose editor is not mounted yet.
  void _restoreViewPosition(
    CodeForgeController controller,
    PersistedTab persisted,
  ) {
    final offset = persisted.cursorOffset;
    int? caretLine;
    if (offset != null) {
      final safeOffset = offset.clamp(0, controller.length).toInt();
      controller.setSelectionSilently(
        TextSelection.collapsed(offset: safeOffset),
      );
      caretLine = controller.getLineAtOffset(safeOffset);
    }
    final scrollLine = persisted.scrollLine;
    if (scrollLine != null &&
        scrollLine > 0 &&
        scrollLine < controller.lineCount) {
      controller.pendingViewportLine = scrollLine;
    } else if (caretLine != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          controller.scrollToLine(caretLine!);
        } on StateError {
          // The tab may have been closed before its editor was mounted.
        }
      });
    }
  }

  /// Finds the tab to select after a restore.
  ///
  /// Path wins over index: the restored list always carries the welcome tab in
  /// front and drops any file that disappeared while the app was closed, so
  /// the saved index does not line up with the rebuilt list. The index is only
  /// used for sessions written before [selectedTabPath] existed, and then only
  /// when it still points inside the rebuilt list.
  int? _resolveRestoredSelection(
    List<TabData> tabs,
    String? selectedTabPath,
    int selectedIndex,
  ) {
    if (selectedTabPath != null) {
      // Sessions saved before paths were canonicalized may spell the drive
      // differently than the restored (canonical) tab values.
      final canonicalSelectedPath = canonicalLocalPath(selectedTabPath);
      for (var i = 0; i < tabs.length; i++) {
        final value = tabs[i].value;
        if (value is TabDataValue && value.filePath == canonicalSelectedPath) {
          return i;
        }
      }
      return null;
    }
    if (selectedIndex > 0 && selectedIndex < tabs.length) return selectedIndex;
    return null;
  }
}

String _gitDiffTabTitle(Ref ref, String filePath, bool staged) {
  final fileName = filePath.split(RegExp(r'[\\/]')).last;
  final sideLabel = staged
      ? translate(ref, I18nKey.gitStageStaged)
      : translate(ref, I18nKey.gitChanges);
  return '$fileName · $sideLabel';
}

/// Converts persisted fold ranges into the snapshots the editor seeds from.
List<FoldRangeSnapshot> _foldSnapshots(List<PersistedFoldRange> ranges) => [
  for (final range in ranges)
    FoldRangeSnapshot(
      startLine: range.startLine,
      endLine: range.endLine,
      children: _foldSnapshots(range.children),
    ),
];

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

/// Recomputes the dirty baseline of every tab affected by a transfer.
///
/// Returns the entries to merge into the notifier's `_lastSavedText` map.
///
/// [affectedPaths] is matched in transfer-path space -- board paths for board
/// tabs -- but the returned baselines are keyed by the tab's own `filePath`
/// (the local cache path for board tabs). The unsaved-change listener diffs
/// under exactly that key, so keying the reseed any other way would write
/// where nothing reads: the listener would keep diffing against the stale
/// pre-transfer text, and an undo back to that text would silently clear a
/// modified dot that is still legitimately set.
Map<String, String> reseedOpenFileTransferBaselines(
  Iterable<TabData> tabs, {
  required bool boardFiles,
  required Set<String> affectedPaths,
}) {
  final baselines = <String, String>{};
  for (final tab in tabs) {
    final value = tab.value;
    if (value is! TabDataValue || value.type != 'file') continue;
    final candidatePath = boardFiles ? value.boardFilePath : value.filePath;
    if (candidatePath == null || !affectedPaths.contains(candidatePath)) {
      continue;
    }
    final controller = value.editorController;
    if (controller != null) {
      baselines[value.filePath] = controller.text;
    }
  }
  return baselines;
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

/// Applies the dirty transition to [tab] and reports whether the flag moved.
///
/// This is the single place where the comparison result becomes a UI state
/// change, so callers cannot invert the meaning of the flag.
bool applyDirtyState(
  TabData tab, {
  required String? savedText,
  required String currentText,
}) {
  final value = tab.value;
  if (value is! TabDataValue || value.type != 'file') return false;
  final nextIsSaved = resolveDirtyState(
    savedText: savedText,
    currentText: currentText,
    isSaved: value.isSaved,
  );
  if (nextIsSaved == null) return false;
  // `nextIsSaved` is the new value of `isSaved`, so it maps straight onto the
  // two setters without the caller having to re-derive the polarity.
  return nextIsSaved ? markFileTabSaved(tab) : _markFileTabUnsaved(tab, value);
}

/// Decides whether a tab's dirty flag should change, given the text it was
/// last saved with and its current buffer.
///
/// Returns the new `isSaved` value, or `null` when nothing should change.
///
/// The distinction that matters is between "the buffer differs from what is
/// stored" and "some mutating API ran". Only the former means modified, which
/// is why a version bump alone is not treated as a change: undo back to the
/// saved text, a no-op edit, or a format that re-emits identical bytes all move
/// the version without modifying the document.
///
/// A `null` [savedText] means no baseline is known -- the file could not be
/// read back. That returns `null` rather than guessing, leaving the current
/// flag alone; flipping a tab to dirty on a guess would show a modified dot
/// for an untouched file, which is the bug this exists to remove.
bool? resolveDirtyState({
  required String? savedText,
  required String currentText,
  required bool isSaved,
}) {
  if (savedText == null) return null;
  final isModified = savedText != currentText;
  if (isModified == !isSaved) return null;
  return !isModified;
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
