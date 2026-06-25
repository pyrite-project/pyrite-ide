import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:git2dart/git2dart.dart';
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

  GitRepositoryService get _service => ref.read(gitRepositoryServiceProvider);

  Future<void> refresh({String? workspacePath}) async {
    final path = workspacePath ?? ref.read(localWorkspaceProvider)?.path;
    await _run(
      () async {
        final snapshot = _service.loadSnapshot(path);
        state = state.copyWith(
          snapshot: snapshot,
          workspacePath: path,
          clearError: true,
          clearSnapshot: snapshot == null,
          clearSelection: snapshot == null,
        );
      },
      success: null,
      refreshAfter: false,
    );
  }

  void updateCredentials(GitCredentialDraft credentials) {
    state = state.copyWith(credentials: credentials, clearError: true);
  }

  Future<void> selectPath(String path, {bool staged = false}) async {
    final rootPath = _rootPath;
    if (rootPath == null) return;
    await _run(
      () async {
        final patch = _service.diffForPath(rootPath, path, staged: staged);
        final history = _service.fileHistory(rootPath, path);
        state = state.copyWith(
          selectedPath: path,
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
    final rootPath = _rootPath;
    final selectedPath = state.selectedPath;
    if (rootPath == null || selectedPath == null) return;
    await _run(
      () async {
        final blame = _service.blame(rootPath, selectedPath);
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

  Future<void> checkoutBranch(String name) async {
    await _runRoot(
      (root) async => _service.checkoutBranch(root, name),
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

  Future<void> acceptConflictSide(String path, GitMergeFileFavor favor) async {
    await _runRoot(
      (root) async => _service.acceptConflictSide(root, path, favor),
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

  String? get _rootPath {
    return state.snapshot?.rootPath ??
        _service.discoverRoot(state.workspacePath);
  }

  Future<void> _runRoot(
    FutureOr<Object?> Function(String rootPath) action, {
    String? success,
  }) async {
    final rootPath = _rootPath;
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
        final snapshot = _service.loadSnapshot(
          state.workspacePath ?? ref.read(localWorkspaceProvider)?.path,
        );
        state = state.copyWith(
          snapshot: snapshot,
          clearError: true,
          clearSnapshot: snapshot == null,
          clearSelection: snapshot == null,
        );
      }
    } catch (error) {
      state = state.copyWith(error: error.toString());
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }
}
