import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/file/local_workspace_provider.dart';
import 'package:pyrite_ide/core/services/git/git_models.dart';
import 'package:pyrite_ide/core/services/git/git_repository_service.dart';

final gitRepositoryServiceProvider = Provider<GitRepositoryService>((ref) {
  return GitRepositoryService();
});

final gitProvider = StateNotifierProvider<GitNotifier, GitViewState>((ref) {
  return GitNotifier(ref);
});

class GitNotifier extends StateNotifier<GitViewState> {
  GitNotifier(this.ref) : super(const GitViewState()) {
    ref.listen(localWorkspaceProvider, (_, next) {
      refresh(workspacePath: next?.path);
    });
    Future.microtask(() {
      refresh(workspacePath: ref.read(localWorkspaceProvider)?.path);
    });
  }

  final Ref ref;
  StreamSubscription<FileSystemEvent>? _workspaceWatch;
  Timer? _refreshDebounce;
  String? _watchedRootPath;

  GitRepositoryService get _service => ref.read(gitRepositoryServiceProvider);

  Future<void> refresh({String? workspacePath}) async {
    final path = workspacePath ?? ref.read(localWorkspaceProvider)?.path;
    await _run(
      () async {
        await _loadAndApplySnapshot(path);
      },
      success: null,
      refreshAfter: false,
    );
  }

  Future<void> initRepository() async {
    final path = state.workspacePath ?? ref.read(localWorkspaceProvider)?.path;
    if (path == null || path.isEmpty) {
      state = state.copyWith(error: '请先打开一个本地文件夹。');
      return;
    }

    await _run(
      () async {
        await _service.initRepository(path);
        await _loadAndApplySnapshot(path);
        state = state.copyWith(lastMessage: '已初始化 Git 仓库', clearError: true);
      },
      success: null,
      refreshAfter: false,
    );
  }

  void updateCredentials(GitCredentialDraft credentials) {
    state = state.copyWith(credentials: credentials, clearError: true);
  }

  Future<void> selectPath(String path, {bool staged = false}) async {
    final rootPath = await _rootPath();
    if (rootPath == null) return;
    await _run(
      () async {
        final entry = _findStatusEntry(state.snapshot, path);
        final selectedStaged = entry == null
            ? staged
            : _preferredSelectedStaged(entry);
        final patch = entry == null
            ? await _service.diffForPath(rootPath, path, staged: selectedStaged)
            : await _service.diffForEntry(
                rootPath,
                entry,
                staged: selectedStaged,
              );
        final history = await _service.fileHistory(rootPath, path);
        state = state.copyWith(
          selectedPath: path,
          selectedStaged: selectedStaged,
          selectedPatch: patch,
          blame: const [],
          lastMessage: history.isEmpty
              ? '已选择 $path'
              : '已选择 $path，找到 ${history.length} 条文件历史',
          clearError: true,
        );
      },
      success: null,
      refreshAfter: false,
    );
  }

  Future<void> blameSelected() async {
    final rootPath = await _rootPath();
    final selectedPath = state.selectedPath;
    if (rootPath == null || selectedPath == null) return;
    await _run(
      () async {
        final blame = await _service.blame(rootPath, selectedPath);
        state = state.copyWith(
          blame: blame,
          lastMessage: '已读取 $selectedPath 的 blame',
        );
      },
      success: null,
      refreshAfter: false,
    );
  }

  Future<void> stage(String path) async {
    await _runRoot(
      (root) async => _service.stage(root, [path]),
      success: '已暂存 $path',
    );
  }

  Future<void> unstage(String path) async {
    await _runRoot(
      (root) async => _service.unstage(root, [path]),
      success: '已取消暂存 $path',
    );
  }

  Future<void> discardChanges(GitStatusEntry entry) async {
    await _runRoot(
      (root) async => _service.discardChanges(root, entry),
      success: '已放弃 ${entry.path} 的工作区更改',
    );
  }

  Future<void> stageAll() async {
    final paths = state.snapshot?.statusEntries
        .where((entry) => entry.isUnstaged || entry.isConflicted)
        .map((entry) => entry.path)
        .toList();
    if (paths == null || paths.isEmpty) return;
    await _runRoot(
      (root) async => _service.stage(root, paths),
      success: '已暂存全部更改',
    );
  }

  Future<void> unstageAll() async {
    final paths = state.snapshot?.statusEntries
        .where((entry) => entry.isStaged)
        .map((entry) => entry.path)
        .toList();
    if (paths == null || paths.isEmpty) return;
    await _runRoot(
      (root) async => _service.unstage(root, paths),
      success: '已取消暂存全部更改',
    );
  }

  Future<void> commit(GitCommitInput input) async {
    await _runRoot(
      (root) async => _service.commit(root, input),
      success: '提交完成',
    );
  }

  Future<void> createBranch(String name) async {
    await _runRoot(
      (root) async => _service.createBranch(root, name),
      success: '已创建分支 $name',
    );
  }

  Future<void> checkoutBranch(String name, {bool remote = false}) async {
    await _runRoot(
      (root) async => _service.checkoutBranch(root, name, remote: remote),
      success: '已切换到 $name',
    );
  }

  Future<void> stash(GitCommitInput input) async {
    await _runRoot(
      (root) async => _service.stash(root, input),
      success: '已储藏更改',
    );
  }

  Future<void> applyStash(int index, {bool pop = false}) async {
    await _runRoot(
      (root) async => _service.applyStash(root, index, pop: pop),
      success: pop ? '已弹出 stash #$index' : '已应用 stash #$index',
    );
  }

  Future<void> dropStash(int index) async {
    await _runRoot(
      (root) async => _service.dropStash(root, index),
      success: '已删除 stash #$index',
    );
  }

  Future<void> fetch(String remote) async {
    await _runRoot(
      (root) async => _service.fetch(root, remote, state.credentials),
      success: null,
    );
  }

  Future<void> push(String remote) async {
    await _runRoot(
      (root) async => _service.push(root, remote, state.credentials),
      success: null,
    );
  }

  Future<void> pull(String remote) async {
    await _runRoot(
      (root) async => _service.pull(root, remote, state.credentials),
      success: null,
    );
  }

  Future<void> addRemote(String name, String url) async {
    await _runRoot(
      (root) async => _service.addRemote(root, name, url),
      success: '已添加远端 $name',
    );
  }

  Future<void> merge(String targetSpec) async {
    await _runRoot(
      (root) async => _service.merge(root, targetSpec),
      success: '已开始合并 $targetSpec',
    );
  }

  Future<void> rebase(String targetSpec, GitCommitInput input) async {
    await _runRoot(
      (root) async => _service.rebase(root, targetSpec, input),
      success: '已执行 rebase 到 $targetSpec',
    );
  }

  Future<void> continueRebase(GitCommitInput input) async {
    await _runRoot(
      (root) async => _service.continueRebase(root, input),
      success: '已继续 rebase',
    );
  }

  Future<void> abortRebase() async {
    await _runRoot(
      (root) async => _service.abortRebase(root),
      success: '已中止 rebase',
    );
  }

  Future<void> cherryPick(String targetSpec) async {
    await _runRoot(
      (root) async => _service.cherryPick(root, targetSpec),
      success: '已 cherry-pick $targetSpec',
    );
  }

  Future<void> markResolved(String path) async {
    await _runRoot(
      (root) async => _service.markResolved(root, path),
      success: '已标记 $path 为已解决',
    );
  }

  Future<void> acceptConflictSide(String path, GitConflictSide side) async {
    await _runRoot(
      (root) async => _service.acceptConflictSide(root, path, side),
      success: '已应用冲突解决结果',
    );
  }

  Future<void> createTag(String name) async {
    await _runRoot(
      (root) async => _service.createTag(root, name),
      success: '已创建标签 $name',
    );
  }

  Future<void> createWorktree(String name, String path) async {
    await _runRoot(
      (root) async => _service.createWorktree(root, name, path),
      success: '已创建 worktree $name',
    );
  }

  Future<void> pruneWorktree(String name) async {
    await _runRoot(
      (root) async => _service.pruneWorktree(root, name),
      success: '已清理 worktree $name',
    );
  }

  Future<void> updateSubmodule(String name) async {
    await _runRoot(
      (root) async => _service.updateSubmodule(root, name, state.credentials),
      success: '已更新 submodule $name',
    );
  }

  Future<void> writeCommitGraph() async {
    await _runRoot(
      (root) async => _service.writeCommitGraph(root),
      success: '已写入 commit graph 索引',
    );
  }

  Future<String?> _rootPath() async {
    return state.snapshot?.rootPath ??
        await _service.discoverRoot(state.workspacePath);
  }

  Future<void> _runRoot(
    FutureOr<Object?> Function(String rootPath) action, {
    String? success,
  }) async {
    final rootPath = await _rootPath();
    if (rootPath == null) {
      state = state.copyWith(error: '当前工作区不是 Git 仓库。');
      return;
    }
    await _run(() async {
      final result = await action(rootPath);
      state = state.copyWith(
        lastMessage: result?.toString() ?? success,
        clearError: true,
      );
    }, success: null);
  }

  Future<void> _run(
    FutureOr<void> Function() action, {
    String? success,
    bool refreshAfter = true,
  }) async {
    state = state.copyWith(
      isBusy: true,
      clearError: true,
      clearLastMessage: success == null,
    );
    try {
      await action();
      if (success != null) {
        state = state.copyWith(lastMessage: success, clearError: true);
      }
      if (refreshAfter) {
        await _loadAndApplySnapshot(
          state.workspacePath ?? ref.read(localWorkspaceProvider)?.path,
        );
      }
    } catch (error) {
      state = state.copyWith(error: error.toString());
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> _loadAndApplySnapshot(String? workspacePath) async {
    final snapshot = await _service.loadSnapshot(workspacePath);
    _updateWorkspaceWatch(snapshot);

    if (snapshot == null) {
      state = state.copyWith(
        snapshot: null,
        workspacePath: workspacePath,
        clearError: true,
        clearSnapshot: true,
        clearSelection: true,
      );
      return;
    }

    final selectedPath = state.selectedPath;
    var selectedPatch = state.selectedPatch;
    var selectedStaged = state.selectedStaged;
    var clearSelection = false;
    if (selectedPath != null) {
      final selectedEntry = _findStatusEntry(snapshot, selectedPath);
      if (selectedEntry == null) {
        clearSelection = true;
      } else {
        selectedStaged = _preferredSelectedStaged(selectedEntry);
        selectedPatch = await _service.diffForEntry(
          snapshot.rootPath,
          selectedEntry,
          staged: selectedStaged,
        );
      }
    }

    state = state.copyWith(
      snapshot: snapshot,
      workspacePath: workspacePath,
      selectedPatch: selectedPatch,
      selectedStaged: selectedStaged,
      clearError: true,
      clearSelection: clearSelection,
    );
  }

  bool _preferredSelectedStaged(GitStatusEntry entry) {
    if (entry.isUntracked) return false;
    if (entry.isUnstaged) return false;
    return !entry.isUnstaged && entry.isStaged;
  }

  GitStatusEntry? _findStatusEntry(
    GitRepositorySnapshot? snapshot,
    String path,
  ) {
    if (snapshot == null) return null;
    for (final entry in snapshot.statusEntries) {
      if (entry.path == path) return entry;
    }
    return null;
  }

  void _updateWorkspaceWatch(GitRepositorySnapshot? snapshot) {
    final rootPath = snapshot?.rootPath;
    if (rootPath == _watchedRootPath) return;
    _workspaceWatch?.cancel();
    _workspaceWatch = null;
    _watchedRootPath = null;
    if (rootPath == null || rootPath.isEmpty) return;

    try {
      _workspaceWatch = Directory(rootPath).watch(recursive: true).listen((
        event,
      ) {
        if (_isIgnoredFileEvent(event.path)) return;
        _scheduleWatchedRefresh();
      });
      _watchedRootPath = rootPath;
    } on FileSystemException {
      // Some platforms or network folders do not support recursive watching.
    } on UnsupportedError {
      // The Git page still supports manual refresh in this case.
    }
  }

  bool _isIgnoredFileEvent(String eventPath) {
    final rootPath = _watchedRootPath;
    if (rootPath == null) return true;
    final snapshot = state.snapshot;
    final ignoredRoots = [
      if (snapshot?.gitDir.isNotEmpty == true) snapshot!.gitDir,
      p.join(rootPath, '.git'),
    ];
    for (final ignoredRoot in ignoredRoots) {
      if (_isWithinOrSame(ignoredRoot, eventPath)) return true;
    }
    return false;
  }

  bool _isWithinOrSame(String parent, String child) {
    final normalizedParent = p.normalize(p.absolute(parent));
    final normalizedChild = p.normalize(p.absolute(child));
    return normalizedParent.toLowerCase() == normalizedChild.toLowerCase() ||
        p.isWithin(normalizedParent, normalizedChild);
  }

  void _scheduleWatchedRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 250), () {
      if (state.isBusy) {
        _scheduleWatchedRefresh();
        return;
      }
      unawaited(refresh(workspacePath: state.snapshot?.rootPath));
    });
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _workspaceWatch?.cancel();
    super.dispose();
  }
}
