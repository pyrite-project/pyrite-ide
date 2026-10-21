import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/file/local_backend.dart';
import 'package:pyrite_ide/core/services/git/git_debug_log.dart';
import 'package:pyrite_ide/core/services/git/git_models.dart';
import 'package:pyrite_ide/core/services/git/git_repository_service.dart';
import 'package:pyrite_ide/core/services/git/git_status_summary_provider.dart';

final gitRepositoryServiceProvider = Provider<GitRepositoryService>((ref) {
  return GitRepositoryService();
});

final gitProvider = StateNotifierProvider<GitNotifier, GitViewState>((ref) {
  return GitNotifier(ref);
});

class GitNotifier extends StateNotifier<GitViewState> {
  GitNotifier(this.ref) : super(const GitViewState()) {
    GitDebugLog.log('GitNotifier created');
    ref.listen(localWorkspaceProvider, (_, next) {
      GitDebugLog.log('localWorkspaceProvider changed path=${next?.path}');
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

  /// busy 期间收到的刷新请求。
  ///
  /// 旧实现会在 busy 时递归重排 timer，结果既没有真正刷新、又让 timer 永远
  /// 在转；这里改成“记一个挂起标记，空闲后补一次”，保证事件不丢也不循环。
  bool _pendingWatchedRefresh = false;

  GitRepositoryService get _service => ref.read(gitRepositoryServiceProvider);

  Future<void> refresh({String? workspacePath}) async {
    if (state.isBusy) {
      // 不再直接丢弃：记下挂起刷新，当前操作结束（isBusy=false）后补一次。
      _pendingWatchedRefresh = true;
      GitDebugLog.log('GitNotifier.refresh deferred because state.isBusy=true');
      return;
    }
    final path = workspacePath ?? ref.read(localWorkspaceProvider)?.path;
    if (GitDebugLog.enabled) {
      GitDebugLog.log(
        'GitNotifier.refresh requested workspacePath=$path '
        'currentSnapshot=${_snapshotSummary(state.snapshot)}',
      );
    }
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

  Future<void> selectPath(String path, {bool? staged}) async {
    final rootPath = await _rootPath();
    if (rootPath == null) return;
    await _run(
      () async {
        await _selectPathPatch(rootPath, path, staged: staged);
      },
      success: null,
      refreshAfter: false,
    );
  }

  Future<void> blameSelected() async {
    final selectedPath = state.selectedPath;
    if (selectedPath == null) return;
    await showBlame(selectedPath);
  }

  Future<void> stage(String path) async {
    await _runRoot(
      (root) async => _service.stage(root, [path]),
      success: '已暂存 $path',
      selectPathAfterRefresh: path,
      selectStagedAfterRefresh: true,
    );
  }

  Future<void> unstage(String path) async {
    await _runRoot(
      (root) async => _service.unstage(root, [path]),
      success: '已取消暂存 $path',
      selectPathAfterRefresh: path,
      selectStagedAfterRefresh: false,
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

  Future<GitCheckoutBlocked?> checkoutBranch(
    String name, {
    bool remote = false,
  }) async {
    return _checkoutBranch(
      name,
      remote: remote,
      action: (root) => _service.checkoutBranch(root, name, remote: remote),
      success: '已切换到 $name',
    );
  }

  Future<void> checkoutBranchWithStash(
    String name, {
    bool remote = false,
  }) async {
    await _runRoot(
      (root) => _service.checkoutBranchWithStash(root, name, remote: remote),
      success: '已储藏更改并切换到 $name',
    );
  }

  Future<void> checkoutBranchWithMerge(
    String name, {
    bool remote = false,
  }) async {
    await _runRoot(
      (root) => _service.checkoutBranchWithMerge(root, name, remote: remote),
      success: '已切换到 $name，并尝试迁移更改',
    );
  }

  Future<void> forceCheckoutBranch(String name, {bool remote = false}) async {
    await _runRoot(
      (root) => _service.forceCheckoutBranch(root, name, remote: remote),
      success: '已强制切换到 $name',
    );
  }

  Future<void> discardPathsAndCheckoutBranch(
    String name,
    Iterable<String> paths, {
    bool remote = false,
  }) async {
    await _runRoot(
      (root) => _service.discardTrackedPathsAndCheckoutBranch(
        root,
        name,
        paths,
        remote: remote,
      ),
      success: '已放弃冲突文件并切换到 $name',
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

  Future<void> createTag(String name, {String message = ''}) async {
    await _runRoot(
      (root) async => _service.createTag(root, name, message: message),
      success: message.trim().isEmpty
          ? '已创建标签 $name'
          : '已创建 annotated 标签 $name',
    );
  }

  Future<void> deleteTag(String name, {String? remoteName}) async {
    await _runRoot(
      (root) async => _service.deleteTag(
        root,
        name,
        remoteName: remoteName,
        draft: state.credentials,
      ),
      success: remoteName == null || remoteName.isEmpty
          ? '已删除标签 $name'
          : '已删除本地与 $remoteName 上的标签 $name',
    );
  }

  /// 查询分支在本地/远端的删除目标。
  ///
  /// 页面需要提前知道“是否存在同名远端分支”，才能在删除本地后单独询问是否
  /// 一并删除远端；失败时把错误写回 state 并返回 null。
  Future<GitBranchDeletionTarget?> inspectBranchDeletionTarget(
    String name,
  ) async {
    final rootPath = await _rootPath();
    if (rootPath == null) {
      state = state.copyWith(error: '当前工作区不是 Git 仓库。');
      return null;
    }
    try {
      return await _service.inspectBranchDeletionTarget(rootPath, name);
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitNotifier.inspectBranchDeletionTarget error name=$name',
        error: error,
        stackTrace: stackTrace,
      );
      state = state.copyWith(error: error.toString());
      return null;
    }
  }

  Future<void> deleteBranch(
    GitBranchInfo branch, {
    bool includeRemote = false,
    bool force = false,
  }) async {
    if (branch.isRemote) {
      final separator = branch.name.indexOf('/');
      if (separator <= 0) {
        state = state.copyWith(error: '无法解析远端分支：${branch.name}');
        return;
      }
      await _runRoot(
        (root) async => _service.deleteRemoteBranch(
          root,
          branch.name.substring(0, separator),
          branch.name.substring(separator + 1),
          state.credentials,
        ),
        success: '已删除远端分支 ${branch.name}',
      );
      return;
    }

    final currentRoot = await _rootPath();
    if (currentRoot == null) {
      state = state.copyWith(error: '当前工作区不是 Git 仓库。');
      return;
    }
    final target = await _service.inspectBranchDeletionTarget(
      currentRoot,
      branch.name,
    );
    await _runRoot(
      (root) async {
        await _service.deleteBranch(root, branch.name, force: force);
        if (includeRemote && target.hasRemote) {
          return _service.deleteRemoteBranch(
            root,
            target.remoteName,
            branch.name,
            state.credentials,
          );
        }
        return null;
      },
      success: includeRemote && target.hasRemote
          ? '已删除本地与 ${target.remoteBranchName} 分支'
          : '已删除分支 ${branch.name}',
    );
  }

  Future<void> renameBranch(
    GitBranchInfo branch,
    String newName, {
    bool force = false,
  }) async {
    await _runRoot(
      (root) async =>
          _service.renameBranch(root, branch.name, newName, force: force),
      success: '已重命名为 $newName',
    );
  }

  Future<void> setRemoteUrl(String name, String url) async {
    await _runRoot(
      (root) async => _service.setRemoteUrl(root, name, url),
      success: '已更新远端 $name 的 URL',
    );
  }

  Future<void> renameRemote(String oldName, String newName) async {
    await _runRoot(
      (root) async => _service.renameRemote(root, oldName, newName),
      success: '已将远端 $oldName 重命名为 $newName',
    );
  }

  Future<void> deleteRemote(String name) async {
    await _runRoot(
      (root) async => _service.deleteRemote(root, name),
      success: '已删除远端 $name',
    );
  }

  /// 打开某个文件的 blame，并记录当前 blame 文件路径。
  Future<void> showBlame(String path) async {
    final rootPath = await _rootPath();
    if (rootPath == null) return;
    await _run(
      () async {
        final blame = await _service.blame(rootPath, path);
        state = state.copyWith(
          blame: blame,
          blamePath: path,
          lastMessage: blame.isEmpty
              ? '$path 还没有 blame 信息'
              : '已读取 $path 的 blame（${blame.length} 段）',
        );
      },
      success: null,
      refreshAfter: false,
    );
  }

  void clearBlame() {
    state = state.copyWith(blame: const [], clearBlamePath: true);
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
    String? selectPathAfterRefresh,
    bool? selectStagedAfterRefresh,
  }) async {
    final rootPath = await _rootPath();
    if (rootPath == null) {
      state = state.copyWith(error: '当前工作区不是 Git 仓库。');
      return;
    }
    await _run(
      () async {
        final result = await action(rootPath);
        state = state.copyWith(
          lastMessage: result?.toString() ?? success,
          clearError: true,
        );
      },
      success: null,
      afterRefresh: selectPathAfterRefresh == null
          ? null
          : () => _selectPathPatch(
              rootPath,
              selectPathAfterRefresh,
              staged: selectStagedAfterRefresh,
              lastMessage: success,
            ),
    );
  }

  Future<GitCheckoutBlocked?> _checkoutBranch(
    String name, {
    required bool remote,
    required Future<void> Function(String rootPath) action,
    required String success,
  }) async {
    final rootPath = await _rootPath();
    if (rootPath == null) {
      state = state.copyWith(error: '当前工作区不是 Git 仓库。');
      return null;
    }

    state = state.copyWith(
      isBusy: true,
      clearError: true,
      clearLastMessage: true,
    );
    try {
      await action(rootPath);
      state = state.copyWith(lastMessage: success, clearError: true);
      await _loadAndApplySnapshot(
        state.workspacePath ?? ref.read(localWorkspaceProvider)?.path,
      );
      return null;
    } on GitCheckoutBlockedException catch (error) {
      state = state.copyWith(clearError: true);
      return GitCheckoutBlocked(
        branchName: name,
        remote: remote,
        paths: error.paths,
        message: error.message,
      );
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitNotifier.checkoutBranch error name=$name remote=$remote',
        error: error,
        stackTrace: stackTrace,
      );
      state = state.copyWith(error: error.toString());
      return null;
    } finally {
      state = state.copyWith(isBusy: false);
      _flushPendingRefresh();
    }
  }

  Future<void> _run(
    FutureOr<void> Function() action, {
    String? success,
    bool refreshAfter = true,
    FutureOr<void> Function()? afterRefresh,
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
      await afterRefresh?.call();
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitNotifier._run error',
        error: error,
        stackTrace: stackTrace,
      );
      state = state.copyWith(error: error.toString());
    } finally {
      state = state.copyWith(isBusy: false);
      _flushPendingRefresh();
    }
  }

  Future<void> _selectPathPatch(
    String rootPath,
    String path, {
    bool? staged,
    String? lastMessage,
  }) async {
    final entry = _findStatusEntry(state.snapshot, path);
    final selectedStaged = entry == null
        ? staged ?? false
        : _selectedStagedForEntry(entry, staged);
    final patch = entry == null
        ? await _service.diffForPath(rootPath, path, staged: selectedStaged)
        : await _service.diffForEntry(rootPath, entry, staged: selectedStaged);
    final history = await _service.fileHistory(rootPath, path);
    state = state.copyWith(
      selectedPath: path,
      selectedStaged: selectedStaged,
      selectedPatch: patch,
      blame: const [],
      clearBlamePath: true,
      lastMessage:
          lastMessage ??
          (history.isEmpty
              ? '已选择 $path'
              : '已选择 $path，找到 ${history.length} 条文件历史'),
      clearError: true,
    );
  }

  Future<void> _loadAndApplySnapshot(String? workspacePath) async {
    final stopwatch = Stopwatch()..start();
    GitDebugLog.log(
      'GitNotifier._loadAndApplySnapshot start workspacePath=$workspacePath '
      'selectedPath=${state.selectedPath}',
    );
    final snapshot = await _service.loadSnapshot(workspacePath);
    if (GitDebugLog.enabled) {
      GitDebugLog.log(
        'GitNotifier._loadAndApplySnapshot service returned '
        '${stopwatch.elapsedMilliseconds}ms ${_snapshotSummary(snapshot)}',
      );
    }
    ref.invalidate(gitStatusSummaryProvider);
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
        GitDebugLog.log(
          'GitNotifier refreshing selected diff path=$selectedPath '
          'staged=$selectedStaged',
        );
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
    GitDebugLog.log(
      'GitNotifier._loadAndApplySnapshot applied '
      '${stopwatch.elapsedMilliseconds}ms clearSelection=$clearSelection',
    );
  }

  bool _selectedStagedForEntry(GitStatusEntry entry, bool? requestedStaged) {
    if (requestedStaged == true && entry.isStaged) return true;
    if (requestedStaged == false && (entry.isUnstaged || entry.isUntracked)) {
      return false;
    }
    return _preferredSelectedStaged(entry);
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
      GitDebugLog.log('GitNotifier installing workspace watch root=$rootPath');
      _workspaceWatch = Directory(rootPath).watch(recursive: false).listen((
        event,
      ) {
        if (_isIgnoredFileEvent(event.path)) return;
        GitDebugLog.log(
          'GitNotifier workspace event type=${event.type} path=${event.path}',
        );
        _scheduleWatchedRefresh();
      });
      _watchedRootPath = rootPath;
      GitDebugLog.log('GitNotifier workspace watch installed root=$rootPath');
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitNotifier workspace watch FileSystemException root=$rootPath',
        error: error,
        stackTrace: stackTrace,
      );
      // Some platforms or network folders do not support recursive watching.
    } on UnsupportedError catch (error, stackTrace) {
      GitDebugLog.log(
        'GitNotifier workspace watch UnsupportedError root=$rootPath',
        error: error,
        stackTrace: stackTrace,
      );
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
        // 关键修复：busy 时只记录挂起，不再递归重排 timer。
        _pendingWatchedRefresh = true;
        GitDebugLog.log('GitNotifier watched refresh deferred while busy');
        return;
      }
      _pendingWatchedRefresh = false;
      unawaited(_refreshFromWatcher());
    });
  }

  /// watcher 触发的刷新：异常统一记账，不允许静默丢失。
  Future<void> _refreshFromWatcher() async {
    try {
      await refresh(workspacePath: state.snapshot?.rootPath);
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitNotifier._refreshFromWatcher failed',
        error: error,
        stackTrace: stackTrace,
      );
      state = state.copyWith(error: error.toString());
    }
  }

  /// 空闲后补一次被挂起的刷新。
  ///
  /// 在所有会把 isBusy 置回 false 的路径末尾调用；这是“补刷新”的唯一出口，
  /// 避免每个操作各写一份触发逻辑。
  void _flushPendingRefresh() {
    if (!_pendingWatchedRefresh) return;
    if (state.isBusy) return;
    _pendingWatchedRefresh = false;
    GitDebugLog.log('GitNotifier flushing deferred refresh');
    unawaited(_refreshFromWatcher());
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _workspaceWatch?.cancel();
    super.dispose();
  }
}

String _snapshotSummary(GitRepositorySnapshot? snapshot) {
  if (snapshot == null) return 'snapshot=null';
  return 'root=${snapshot.rootPath} branch=${snapshot.branchLabel} '
      'status=${snapshot.statusEntries.length} '
      'branches=${snapshot.branches.length} remotes=${snapshot.remotes.length} '
      'commits=${snapshot.commits.length} stagedPatch=${snapshot.stagedPatch.length} '
      'unstagedPatch=${snapshot.unstagedPatch.length}';
}
