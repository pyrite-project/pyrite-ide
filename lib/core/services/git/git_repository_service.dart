import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/git/git_debug_log.dart';
import 'package:pyrite_ide/core/services/git/git_models.dart';

const _maxUntrackedScanEntries = 20000;
const _maxUntrackedStatusEntries = 1000;
const _maxSnapshotUntrackedPatches = 20;
const _maxUntrackedPatchBytes = 256 * 1024;

class GitCommitInput {
  const GitCommitInput({
    required this.message,
    required this.authorName,
    required this.authorEmail,
  });

  final String message;
  final String authorName;
  final String authorEmail;
}

class GitRepositoryService {
  GitRepositoryService({Duration commandTimeout = const Duration(seconds: 20)});

  Future<GitRepositorySnapshot?> loadSnapshot(String? workspacePath) async {
    GitDebugLog.log(
      'GitRepositoryService.loadSnapshot start workspace=$workspacePath',
    );
    final rootPath = await GitDebugLog.timeAsync(
      'GitRepositoryService.discoverRoot',
      () => discoverRoot(workspacePath),
      result: (value) => 'root=$value',
    );
    if (rootPath == null) {
      GitDebugLog.log('GitRepositoryService.loadSnapshot no repository found');
      return null;
    }

    try {
      return await _withRepository(rootPath, (repo) async {
        final statusEntries = GitDebugLog.timeSync(
          'GitRepositoryService.statusEntries',
          () => _statusEntries(repo),
          result: (value) =>
              'count=${value.length} untracked=${value.where((entry) => entry.isUntracked).length}',
        );
        final conflicts = await GitDebugLog.timeAsync(
          'GitRepositoryService.conflicts',
          () => _conflicts(repo, statusEntries),
          result: (value) => 'count=${value.length}',
        );
        final aheadBehind = GitDebugLog.timeSync(
          'GitRepositoryService.aheadBehind',
          () => _aheadBehind(repo),
          result: (value) => 'ahead=${value.$1} behind=${value.$2}',
        );
        final unstagedPatch = await GitDebugLog.timeAsync(
          'GitRepositoryService.unstagedPatch',
          () => _unstagedPatch(repo, statusEntries),
          result: (value) => 'bytes=${value.length}',
        );
        final root = _normalizeWorkdir(repo.workdir);
        final gitDir = p.normalize(repo.path);
        final branchLabel = GitDebugLog.timeSync(
          'GitRepositoryService.branchLabel',
          () => _branchLabel(repo),
        );
        final stateLabel = GitDebugLog.timeSync(
          'GitRepositoryService.repositoryStateLabel',
          () => _repositoryStateLabel(repo),
        );
        final isDetached = _isDetached(repo);
        final isEmpty = _isEmpty(repo);
        final authorName = _configValue(repo, 'user.name') ?? 'Pyrite User';
        final authorEmail =
            _configValue(repo, 'user.email') ?? 'pyrite@example.local';
        final branches = GitDebugLog.timeSync(
          'GitRepositoryService.branches',
          () => _branches(repo),
          result: (value) => 'count=${value.length}',
        );
        final remotes = GitDebugLog.timeSync(
          'GitRepositoryService.remotes',
          () => _remotes(repo),
          result: (value) => 'count=${value.length}',
        );
        final stashes = GitDebugLog.timeSync(
          'GitRepositoryService.stashes',
          () => _stashes(repo),
          result: (value) => 'count=${value.length}',
        );
        final tags = GitDebugLog.timeSync(
          'GitRepositoryService.tags',
          () => _tags(repo),
          result: (value) => 'count=${value.length}',
        );
        final submodules = GitDebugLog.timeSync(
          'GitRepositoryService.submodules',
          () => _submodules(repo),
          result: (value) => 'count=${value.length}',
        );
        final worktrees = GitDebugLog.timeSync(
          'GitRepositoryService.worktrees',
          () => _worktrees(repo),
          result: (value) => 'count=${value.length}',
        );
        final commits = GitDebugLog.timeSync(
          'GitRepositoryService.commits',
          () => _commits(repo),
          result: (value) => 'count=${value.length}',
        );
        final stagedPatch = GitDebugLog.timeSync(
          'GitRepositoryService.stagedPatch',
          () => _stagedPatch(repo),
          result: (value) => 'bytes=${value.length}',
        );

        GitDebugLog.log(
          'GitRepositoryService.loadSnapshot complete root=$root '
          'gitDir=$gitDir status=${statusEntries.length} '
          'branches=${branches.length} commits=${commits.length}',
        );
        return GitRepositorySnapshot(
          rootPath: root,
          gitDir: gitDir,
          branchLabel: branchLabel,
          stateLabel: stateLabel,
          isDetached: isDetached,
          isEmpty: isEmpty,
          authorName: authorName,
          authorEmail: authorEmail,
          ahead: aheadBehind.$1,
          behind: aheadBehind.$2,
          statusEntries: statusEntries,
          branches: branches,
          remotes: remotes,
          stashes: stashes,
          tags: tags,
          submodules: submodules,
          worktrees: worktrees,
          commits: commits,
          conflicts: conflicts,
          stagedPatch: stagedPatch,
          unstagedPatch: unstagedPatch,
        );
      });
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService.loadSnapshot error root=$rootPath',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<String?> discoverRoot(String? workspacePath) async {
    if (workspacePath == null || workspacePath.isEmpty) return null;

    final startPath = Directory(workspacePath).existsSync()
        ? workspacePath
        : p.dirname(workspacePath);
    try {
      GitDebugLog.log('Repository.discover start startPath=$startPath');
      final gitDir = Repository.discover(startPath: startPath);
      GitDebugLog.log('Repository.discover end gitDir=$gitDir');
      GitDebugLog.log('Repository.open(discovered) start gitDir=$gitDir');
      final repo = Repository.open(gitDir);
      try {
        GitDebugLog.log(
          'Repository.open(discovered) end path=${repo.path} '
          'workdir=${repo.workdir}',
        );
        final workdir = repo.workdir;
        if (workdir.isEmpty) return p.normalize(p.dirname(gitDir));
        return _normalizeWorkdir(workdir);
      } finally {
        GitDebugLog.log('Repository.free(discovered) start gitDir=$gitDir');
        repo.free();
        GitDebugLog.log('Repository.free(discovered) end gitDir=$gitDir');
      }
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService.discoverRoot failed startPath=$startPath',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> initRepository(String workspacePath) async {
    final path = workspacePath.trim();
    if (path.isEmpty) throw ArgumentError('工作区路径不能为空。');
    if (!Directory(path).existsSync()) {
      throw ArgumentError('工作区文件夹不存在：$path');
    }

    final repo = Repository.init(path: path);
    repo.free();
  }

  Future<String> diffForPath(
    String rootPath,
    String filePath, {
    bool staged = false,
  }) {
    return _withRepository(rootPath, (repo) async {
      final patch = staged
          ? _stagedPatch(repo, filePath: filePath)
          : _trackedUnstagedPatch(repo, filePath: filePath);
      if (patch.isNotEmpty || staged) return patch;
      return _untrackedFilePatch(_normalizeWorkdir(repo.workdir), filePath);
    });
  }

  Future<String> diffForEntry(
    String rootPath,
    GitStatusEntry entry, {
    bool staged = false,
  }) {
    if (entry.isUntracked && !staged) {
      return _untrackedFilePatch(rootPath, entry.path);
    }
    return diffForPath(rootPath, entry.path, staged: staged);
  }

  Future<List<GitCommitInfo>> fileHistory(
    String rootPath,
    String filePath,
  ) async {
    return _withRepository(rootPath, (repo) {
      return _commits(repo, limit: 200, pathspec: filePath);
    });
  }

  Future<List<GitBlameLine>> blame(String rootPath, String filePath) async {
    return _withRepository(rootPath, (repo) {
      final blame = Blame.file(repo: repo, path: filePath);
      try {
        return [
          for (final hunk in blame)
            GitBlameLine(
              lineStart: hunk.finalStartLineNumber,
              lineCount: hunk.linesCount,
              commitSha: hunk.finalCommitOid.sha,
              author: hunk.finalCommitter?.name ?? '',
              email: hunk.finalCommitter?.email ?? '',
              time: _signatureTime(hunk.finalCommitter),
            ),
        ];
      } finally {
        blame.free();
      }
    });
  }

  Future<void> stage(String rootPath, Iterable<String> paths) async {
    await _withRepository(rootPath, (repo) {
      final index = repo.index;
      try {
        for (final rawPath in _cleanPaths(paths)) {
          final absolutePath = p.join(_normalizeWorkdir(repo.workdir), rawPath);
          if (Directory(absolutePath).existsSync()) {
            index.addAll([_gitPath(rawPath)]);
          } else if (File(absolutePath).existsSync()) {
            index.add(_gitPath(rawPath));
          } else {
            index.remove(_gitPath(rawPath));
          }
        }
        index.write();
      } finally {
        index.free();
      }
    });
  }

  Future<void> unstage(String rootPath, Iterable<String> paths) async {
    await _withRepository(rootPath, (repo) {
      final cleanPaths = _cleanPaths(paths).toList();
      if (cleanPaths.isEmpty) return;

      final headOid = _headOidOrNull(repo);
      if (headOid != null) {
        repo.resetDefault(
          oid: headOid,
          pathspec: cleanPaths.map(_gitPath).toList(),
        );
        return;
      }

      final index = repo.index;
      try {
        for (final path in cleanPaths) {
          index.remove(_gitPath(path));
        }
        index.write();
      } finally {
        index.free();
      }
    });
  }

  Future<void> discardChanges(String rootPath, GitStatusEntry entry) async {
    await _withRepository(rootPath, (repo) async {
      if (entry.isUntracked) {
        await _deleteUntrackedPath(_normalizeWorkdir(repo.workdir), entry.path);
        return;
      }
      Checkout.head(
        repo: repo,
        strategy: const {GitCheckout.force, GitCheckout.recreateMissing},
        paths: [_gitPath(entry.path)],
      );
    });
  }

  Future<void> commit(String rootPath, GitCommitInput input) async {
    await _withRepository(rootPath, (repo) {
      if (repo.index.hasConflicts) {
        throw StateError('仍有冲突未解决，不能提交。');
      }
      final message = input.message.trim();
      if (message.isEmpty) {
        throw ArgumentError('提交信息不能为空。');
      }

      final index = repo.index;
      try {
        final tree = Tree.lookup(repo: repo, oid: index.writeTree(repo));
        try {
          final signature = _signature(input);
          final parents = _commitParents(repo);
          Commit.create(
            repo: repo,
            updateRef: 'HEAD',
            author: signature,
            committer: signature,
            messageEncoding: 'UTF-8',
            message: message,
            tree: tree,
            parents: parents,
          );
          if (repo.state != GitRepositoryState.none &&
              repo.state != GitRepositoryState.rebase &&
              repo.state != GitRepositoryState.rebaseMerge) {
            repo.stateCleanup();
          }
        } finally {
          tree.free();
        }
      } finally {
        index.free();
      }
    });
  }

  Future<void> createBranch(String rootPath, String name) async {
    await _withRepository(rootPath, (repo) {
      final branchName = name.trim();
      if (branchName.isEmpty) throw ArgumentError('分支名称不能为空。');
      final head = _headCommit(repo);
      Branch.create(repo: repo, name: branchName, target: head);
    });
  }

  Future<void> checkoutBranch(
    String rootPath,
    String name, {
    bool remote = false,
  }) async {
    await _withRepository(rootPath, (repo) {
      _checkoutBranch(repo, name, remote: remote);
    });
  }

  Future<void> checkoutBranchWithStash(
    String rootPath,
    String name, {
    bool remote = false,
  }) async {
    await _withRepository(rootPath, (repo) {
      final signature = _defaultSignature(repo);
      Stash.create(
        repo: repo,
        stasher: signature,
        message: 'PyriteIDE: stash before switching to ${name.trim()}',
        flags: const {GitStash.includeUntracked},
      );
      _checkoutBranch(repo, name, remote: remote);
    });
  }

  Future<void> checkoutBranchWithMerge(
    String rootPath,
    String name, {
    bool remote = false,
  }) async {
    await _withRepository(rootPath, (repo) {
      _checkoutBranch(
        repo,
        name,
        remote: remote,
        strategy: const {
          GitCheckout.safe,
          GitCheckout.recreateMissing,
          GitCheckout.allowConflicts,
          GitCheckout.conflictStyleMerge,
        },
      );
    });
  }

  Future<void> forceCheckoutBranch(
    String rootPath,
    String name, {
    bool remote = false,
  }) async {
    await _withRepository(rootPath, (repo) {
      final headOid = _headOidOrNull(repo);
      if (headOid != null) {
        repo.reset(
          oid: headOid,
          resetType: GitReset.hard,
          strategy: const {
            GitCheckout.force,
            GitCheckout.removeUntracked,
            GitCheckout.recreateMissing,
          },
        );
      }
      _checkoutBranch(
        repo,
        name,
        remote: remote,
        strategy: const {
          GitCheckout.force,
          GitCheckout.removeUntracked,
          GitCheckout.recreateMissing,
        },
      );
    });
  }

  Future<void> discardTrackedPathsAndCheckoutBranch(
    String rootPath,
    String name,
    Iterable<String> paths, {
    bool remote = false,
  }) async {
    await _withRepository(rootPath, (repo) {
      final trackedPaths = _cleanPaths(paths).map(_gitPath).toList();
      if (trackedPaths.isNotEmpty) {
        Checkout.head(
          repo: repo,
          strategy: const {GitCheckout.force, GitCheckout.recreateMissing},
          paths: trackedPaths,
        );
      }
      _checkoutBranch(repo, name, remote: remote);
    });
  }

  Future<void> stash(
    String rootPath,
    GitCommitInput input, {
    bool includeUntracked = true,
  }) async {
    await _withRepository(rootPath, (repo) {
      final message = input.message.trim().isEmpty
          ? 'WIP'
          : input.message.trim();
      Stash.create(
        repo: repo,
        stasher: _signature(input),
        message: message,
        flags: includeUntracked
            ? const {GitStash.includeUntracked}
            : const {GitStash.defaults},
      );
    });
  }

  Future<void> applyStash(
    String rootPath,
    int index, {
    bool pop = false,
  }) async {
    await _withRepository(rootPath, (repo) {
      if (pop) {
        Stash.pop(repo: repo, index: index);
      } else {
        Stash.apply(repo: repo, index: index);
      }
    });
  }

  Future<void> dropStash(String rootPath, int index) async {
    await _withRepository(rootPath, (repo) {
      Stash.drop(repo: repo, index: index);
    });
  }

  Future<String> fetch(
    String rootPath,
    String remoteName,
    GitCredentialDraft draft,
  ) async {
    return _withRepository(rootPath, (repo) {
      final remote = Remote.lookup(repo: repo, name: remoteName);
      try {
        remote.fetch(callbacks: _callbacks(draft));
      } finally {
        remote.free();
      }
      return '已从 $remoteName 获取更新';
    });
  }

  Future<String> push(
    String rootPath,
    String remoteName,
    GitCredentialDraft draft,
  ) async {
    return _withRepository(rootPath, (repo) {
      final branch = _currentBranch(repo);
      if (branch == null) {
        throw StateError('当前不是可推送的本地分支。');
      }
      final remote = Remote.lookup(repo: repo, name: remoteName);
      try {
        remote.push(
          refspecs: ['refs/heads/$branch:refs/heads/$branch'],
          callbacks: _callbacks(draft),
        );
      } finally {
        remote.free();
      }
      return '已推送 $branch 到 $remoteName';
    });
  }

  Future<String> pull(
    String rootPath,
    String remoteName,
    GitCredentialDraft draft,
  ) async {
    return _withRepository(rootPath, (repo) {
      final branch = _currentBranch(repo);
      if (branch == null) {
        throw StateError('当前 HEAD 分离，不能自动 pull。');
      }

      final remote = Remote.lookup(repo: repo, name: remoteName);
      try {
        remote.fetch(callbacks: _callbacks(draft));
      } finally {
        remote.free();
      }

      final upstreamSpec = _upstreamSpec(repo, branch) ?? '$remoteName/$branch';
      _merge(repo, upstreamSpec);
      return '已从 $remoteName 拉取并合并到 $branch';
    });
  }

  Future<void> addRemote(String rootPath, String name, String url) async {
    await _withRepository(rootPath, (repo) {
      final remoteName = name.trim();
      final remoteUrl = url.trim();
      if (remoteName.isEmpty) throw ArgumentError('远端名称不能为空。');
      if (remoteUrl.isEmpty) throw ArgumentError('远端 URL 不能为空。');
      final remote = Remote.create(
        repo: repo,
        name: remoteName,
        url: remoteUrl,
      );
      remote.free();
    });
  }

  Future<void> merge(String rootPath, String targetSpec) async {
    await _withRepository(rootPath, (repo) {
      _merge(repo, targetSpec);
    });
  }

  Future<void> rebase(
    String rootPath,
    String targetSpec,
    GitCommitInput input,
  ) async {
    await _withRepository(rootPath, (repo) {
      final upstream = AnnotatedCommit.fromRevSpec(
        repo: repo,
        spec: targetSpec,
      );
      final rebase = Rebase.init(repo: repo, upstream: upstream);
      try {
        _advanceRebase(repo, rebase, input);
      } finally {
        rebase.free();
        upstream.free();
      }
    });
  }

  Future<void> continueRebase(String rootPath, GitCommitInput input) async {
    await _withRepository(rootPath, (repo) {
      if (repo.index.hasConflicts) {
        throw StateError('仍有冲突未解决，不能继续 rebase。');
      }
      final rebase = Rebase.open(repo);
      try {
        rebase.commit(committer: _signature(input));
        _advanceRebase(repo, rebase, input);
      } finally {
        rebase.free();
      }
    });
  }

  Future<void> abortRebase(String rootPath) async {
    await _withRepository(rootPath, (repo) {
      final rebase = Rebase.open(repo);
      try {
        rebase.abort();
      } finally {
        rebase.free();
      }
    });
  }

  Future<void> cherryPick(String rootPath, String targetSpec) async {
    await _withRepository(rootPath, (repo) {
      final commit = _commitFromSpec(repo, targetSpec);
      Merge.cherryPick(repo: repo, commit: commit);
      if (repo.index.hasConflicts) return;

      final index = repo.index;
      try {
        final tree = Tree.lookup(repo: repo, oid: index.writeTree(repo));
        try {
          Commit.create(
            repo: repo,
            updateRef: 'HEAD',
            author: commit.author,
            committer: _defaultSignature(repo),
            messageEncoding: commit.messageEncoding,
            message: commit.message,
            tree: tree,
            parents: _commitParents(repo),
          );
          if (repo.state != GitRepositoryState.none) repo.stateCleanup();
        } finally {
          tree.free();
        }
      } finally {
        index.free();
      }
    });
  }

  Future<void> markResolved(String rootPath, String filePath) {
    return stage(rootPath, [filePath]);
  }

  Future<void> acceptConflictSide(
    String rootPath,
    String filePath,
    GitConflictSide side,
  ) async {
    await _withRepository(rootPath, (repo) {
      Checkout.index(
        repo: repo,
        strategy: {
          GitCheckout.force,
          side == GitConflictSide.ours
              ? GitCheckout.useOurs
              : GitCheckout.useTheirs,
        },
        paths: [_gitPath(filePath)],
      );
      final index = repo.index;
      try {
        index.add(_gitPath(filePath));
        index.write();
      } finally {
        index.free();
      }
    });
  }

  Future<void> createTag(
    String rootPath,
    String name, {
    String? targetSpec,
  }) async {
    await _withRepository(rootPath, (repo) {
      final tagName = name.trim();
      if (tagName.isEmpty) throw ArgumentError('标签名称不能为空。');
      final target = _objectFromSpec(
        repo,
        targetSpec?.trim().isNotEmpty == true ? targetSpec!.trim() : 'HEAD',
      );
      final oid = switch (target) {
        Commit(:final oid) => oid,
        Tree(:final oid) => oid,
        Blob(:final oid) => oid,
        Tag(:final oid) => oid,
        _ => throw ArgumentError('不支持的标签目标。'),
      };
      final type = _objectType(target);
      Tag.createLightweight(
        repo: repo,
        tagName: tagName,
        target: oid,
        targetType: type,
      );
    });
  }

  Future<void> createWorktree(String rootPath, String name, String path) async {
    await _withRepository(rootPath, (repo) {
      final worktreeName = name.trim();
      final worktreePath = path.trim();
      if (worktreeName.isEmpty) throw ArgumentError('worktree 名称不能为空。');
      if (worktreePath.isEmpty) throw ArgumentError('worktree 路径不能为空。');

      Reference? ref;
      try {
        ref = Reference.lookup(repo: repo, name: _localRefName(worktreeName));
      } catch (_) {
        ref = null;
      }
      final worktree = Worktree.create(
        repo: repo,
        name: worktreeName,
        path: worktreePath,
        ref: ref,
      );
      worktree.free();
      ref?.free();
    });
  }

  Future<void> pruneWorktree(String rootPath, String name) async {
    await _withRepository(rootPath, (repo) {
      final worktree = Worktree.lookup(repo: repo, name: name);
      try {
        worktree.prune(const {
          GitWorktree.pruneValid,
          GitWorktree.pruneLocked,
          GitWorktree.pruneWorkingTree,
        });
      } finally {
        worktree.free();
      }
    });
  }

  Future<void> updateSubmodule(
    String rootPath,
    String name,
    GitCredentialDraft draft,
  ) async {
    await _withRepository(rootPath, (repo) {
      Submodule.update(
        repo: repo,
        name: name,
        init: true,
        callbacks: _callbacks(draft),
      );
    });
  }

  Future<void> writeCommitGraph(String rootPath) async {
    await _withRepository(rootPath, (_) {
      // git2dart/libgit2 does not expose commit-graph writing. Keep the action
      // command-free so mobile platforms do not shell out to a missing Git CLI.
    });
  }

  Future<T> _withRepository<T>(
    String rootPath,
    FutureOr<T> Function(Repository repo) action,
  ) async {
    final stopwatch = Stopwatch()..start();
    GitDebugLog.log('Repository.open(root) start root=$rootPath');
    final repo = Repository.open(rootPath);
    GitDebugLog.log(
      'Repository.open(root) end ${stopwatch.elapsedMilliseconds}ms '
      'path=${repo.path} workdir=${repo.workdir}',
    );
    try {
      return await action(repo);
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'Repository action error root=$rootPath',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      GitDebugLog.log('Repository.free(root) start root=$rootPath');
      repo.free();
      GitDebugLog.log('Repository.free(root) end root=$rootPath');
    }
  }

  String _branchLabel(Repository repo) {
    final branch = _currentBranch(repo);
    if (branch != null) return branch;

    final headOid = _headOidOrNull(repo);
    return headOid == null ? '未提交仓库' : 'HEAD@${headOid.toStrN(7)}';
  }

  String? _currentBranch(Repository repo) {
    try {
      if (repo.isHeadDetached || repo.isEmpty) return null;
      final head = repo.head;
      return head.shorthand;
    } catch (_) {
      return null;
    }
  }

  bool _isDetached(Repository repo) =>
      _tryValue(() => repo.isHeadDetached) ?? false;

  bool _isEmpty(Repository repo) => _tryValue(() => repo.isEmpty) ?? true;

  (int, int) _aheadBehind(Repository repo) {
    try {
      final branchName = _currentBranch(repo);
      if (branchName == null) return (0, 0);
      final branch = Branch.lookup(repo: repo, name: branchName);
      final upstream = branch.upstream;
      final values = repo.aheadBehind(
        local: branch.target,
        upstream: upstream.target,
      );
      return (values[0], values[1]);
    } catch (_) {
      return (0, 0);
    }
  }

  Future<String> _unstagedPatch(
    Repository repo,
    List<GitStatusEntry> entries,
  ) async {
    final rootPath = _normalizeWorkdir(repo.workdir);
    GitDebugLog.log(
      'GitRepositoryService._unstagedPatch start entries=${entries.length}',
    );
    final parts = <String>[_trackedUnstagedPatch(repo)];
    var untrackedPatchCount = 0;
    for (final entry in entries) {
      if (!entry.isUntracked) continue;
      if (untrackedPatchCount >= _maxSnapshotUntrackedPatches) break;
      GitDebugLog.log(
        'GitRepositoryService._unstagedPatch untracked start '
        'path=${entry.path} index=$untrackedPatchCount',
      );
      final patch = await _untrackedFilePatch(rootPath, entry.path);
      if (patch.isNotEmpty) parts.add(patch);
      untrackedPatchCount++;
    }
    return parts.where((part) => part.isNotEmpty).join('\n');
  }

  String _trackedUnstagedPatch(Repository repo, {String? filePath}) {
    GitDebugLog.log(
      'GitRepositoryService._trackedUnstagedPatch start filePath=$filePath',
    );
    final index = repo.index;
    try {
      GitDebugLog.log('Diff.indexToWorkdir start filePath=$filePath');
      final diff = Diff.indexToWorkdir(repo: repo, index: index);
      try {
        GitDebugLog.log(
          'Diff.indexToWorkdir end filePath=$filePath length=${diff.length}',
        );
        final patch = _patchText(diff, filePath: filePath);
        GitDebugLog.log(
          'GitRepositoryService._trackedUnstagedPatch end '
          'filePath=$filePath bytes=${patch.length}',
        );
        return patch;
      } finally {
        GitDebugLog.log('Diff.indexToWorkdir free filePath=$filePath');
        diff.free();
      }
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._trackedUnstagedPatch failed filePath=$filePath',
        error: error,
        stackTrace: stackTrace,
      );
      return '';
    } finally {
      index.free();
    }
  }

  String _stagedPatch(Repository repo, {String? filePath}) {
    GitDebugLog.log(
      'GitRepositoryService._stagedPatch start filePath=$filePath',
    );
    final index = repo.index;
    try {
      GitDebugLog.log('Diff.treeToIndex start filePath=$filePath');
      final diff = Diff.treeToIndex(
        repo: repo,
        tree: _headTreeOrNull(repo),
        index: index,
      );
      try {
        GitDebugLog.log(
          'Diff.treeToIndex end filePath=$filePath length=${diff.length}',
        );
        final patch = _patchText(diff, filePath: filePath);
        GitDebugLog.log(
          'GitRepositoryService._stagedPatch end '
          'filePath=$filePath bytes=${patch.length}',
        );
        return patch;
      } finally {
        GitDebugLog.log('Diff.treeToIndex free filePath=$filePath');
        diff.free();
      }
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._stagedPatch failed filePath=$filePath',
        error: error,
        stackTrace: stackTrace,
      );
      return '';
    } finally {
      index.free();
    }
  }

  String _patchText(Diff diff, {String? filePath}) {
    if (filePath == null) {
      GitDebugLog.log('Diff.patch start length=${diff.length}');
      final patch = diff.patch.trimRight();
      GitDebugLog.log('Diff.patch end bytes=${patch.length}');
      return patch;
    }

    final wanted = _gitPath(filePath);
    final parts = <String>[];
    for (var index = 0; index < diff.length; index += 1) {
      GitDebugLog.log(
        'Patch.fromDiff start filePath=$filePath index=$index length=${diff.length}',
      );
      final patch = Patch.fromDiff(diff: diff, index: index);
      try {
        GitDebugLog.log('Patch.fromDiff end filePath=$filePath index=$index');
        final delta = patch.delta;
        final paths = {
          _gitPath(delta.oldFile.path),
          _gitPath(delta.newFile.path),
        };
        if (paths.contains(wanted)) {
          final text = patch.text.trimRight();
          if (text.isNotEmpty) parts.add(text);
        }
      } finally {
        patch.free();
      }
    }
    return parts.join('\n');
  }

  Future<String> _untrackedFilePatch(String rootPath, String filePath) async {
    GitDebugLog.log(
      'GitRepositoryService._untrackedFilePatch start path=$filePath',
    );
    final file = File(p.join(rootPath, filePath));
    if (!await file.exists()) {
      GitDebugLog.log(
        'GitRepositoryService._untrackedFilePatch missing path=$filePath',
      );
      return '';
    }

    final normalizedPath = _gitPath(filePath);
    final header = StringBuffer()
      ..writeln('diff --git a/$normalizedPath b/$normalizedPath')
      ..writeln('new file mode 100644')
      ..writeln('index 0000000..0000000')
      ..writeln('--- /dev/null')
      ..writeln('+++ b/$normalizedPath');
    late final int length;
    try {
      length = await file.length();
      GitDebugLog.log(
        'GitRepositoryService._untrackedFilePatch length path=$filePath '
        'bytes=$length',
      );
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._untrackedFilePatch length failed path=$filePath',
        error: error,
        stackTrace: stackTrace,
      );
      return '';
    }
    if (length > _maxUntrackedPatchBytes) {
      header.writeln('@@ -0,0 +1 @@');
      header.writeln(
        '+[untracked file omitted: $length bytes exceeds preview limit]',
      );
      return header.toString().trimRight();
    }

    late final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._untrackedFilePatch read failed path=$filePath',
        error: error,
        stackTrace: stackTrace,
      );
      return '';
    }
    if (bytes.contains(0)) {
      header.writeln('Binary files /dev/null and b/$normalizedPath differ');
      return header.toString().trimRight();
    }

    final content = utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = content.isEmpty ? <String>[] : content.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    header.writeln('@@ -0,0 +1,${lines.length} @@');
    for (final line in lines) {
      header.writeln('+$line');
    }
    return header.toString().trimRight();
  }

  List<GitStatusEntry> _statusEntries(Repository repo) {
    GitDebugLog.log('GitRepositoryService._statusEntries repo.status start');
    final statuses = Map<String, Set<GitStatus>>.fromEntries(
      repo.status.entries.map(
        (entry) => MapEntry(_gitPath(entry.key), entry.value),
      ),
    );
    GitDebugLog.log(
      'GitRepositoryService._statusEntries repo.status end count=${statuses.length}',
    );
    _addUntrackedStatuses(repo, statuses);

    final entries = [
      for (final item in statuses.entries)
        GitStatusEntry(
          path: item.key,
          labels: _statusLabels(item.value),
          isStaged: _isIndexStatus(item.value),
          isUnstaged: _isWorktreeStatus(item.value),
          isConflicted: item.value.contains(GitStatus.conflicted),
          isUntracked:
              item.value.contains(GitStatus.wtNew) &&
              !_isIndexStatus(item.value),
        ),
    ];
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  void _addUntrackedStatuses(
    Repository repo,
    Map<String, Set<GitStatus>> statuses,
  ) {
    final rootPath = _normalizeWorkdir(repo.workdir);
    if (rootPath.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    GitDebugLog.log(
      'GitRepositoryService._addUntrackedStatuses start root=$rootPath '
      'existing=${statuses.length}',
    );
    final trackedPaths = _trackedIndexPaths(repo);
    final pendingDirectories = <Directory>[Directory(rootPath)];
    var scannedEntries = 0;
    var untrackedEntries = 0;

    while (pendingDirectories.isNotEmpty &&
        scannedEntries < _maxUntrackedScanEntries &&
        untrackedEntries < _maxUntrackedStatusEntries) {
      final directory = pendingDirectories.removeLast();
      final children = _listDirectory(directory);

      for (final entity in children) {
        if (scannedEntries >= _maxUntrackedScanEntries ||
            untrackedEntries >= _maxUntrackedStatusEntries) {
          break;
        }
        scannedEntries++;
        if (GitDebugLog.enabled && scannedEntries % 1000 == 0) {
          GitDebugLog.log(
            'GitRepositoryService._addUntrackedStatuses progress '
            'scanned=$scannedEntries untracked=$untrackedEntries '
            'pendingDirs=${pendingDirectories.length}',
          );
        }

        final relativePath = _gitPath(p.relative(entity.path, from: rootPath));
        if (_isGitInternalPath(relativePath)) continue;

        if (entity is Directory) {
          if (statuses.containsKey(relativePath) ||
              trackedPaths.contains(relativePath)) {
            continue;
          }
          if (_isNestedGitRepository(entity)) {
            if (!_isIgnoredPath(repo, relativePath)) {
              statuses[relativePath] = const {GitStatus.wtNew};
              untrackedEntries++;
            }
            continue;
          }
          if (!_isIgnoredPath(repo, relativePath)) {
            pendingDirectories.add(entity);
          }
          continue;
        }
        if (entity is! File && entity is! Link) continue;
        if (statuses.containsKey(relativePath)) continue;
        if (trackedPaths.contains(relativePath)) continue;

        final fileStatus = _statusFile(repo, relativePath);
        if (fileStatus.contains(GitStatus.wtNew)) {
          statuses[relativePath] = fileStatus;
          untrackedEntries++;
        } else if (fileStatus.isEmpty && !_isIgnoredPath(repo, relativePath)) {
          statuses[relativePath] = const {GitStatus.wtNew};
          untrackedEntries++;
        }
      }
    }
    GitDebugLog.log(
      'GitRepositoryService._addUntrackedStatuses end '
      'elapsed=${stopwatch.elapsedMilliseconds}ms scanned=$scannedEntries '
      'untracked=$untrackedEntries total=${statuses.length} '
      'pendingDirs=${pendingDirectories.length}',
    );
  }

  Set<String> _trackedIndexPaths(Repository repo) {
    final index = repo.index;
    try {
      return {
        for (final entry in index)
          if (!entry.isConflict) _gitPath(entry.path),
      };
    } finally {
      index.free();
    }
  }

  List<FileSystemEntity> _listDirectory(Directory directory) {
    try {
      return directory.listSync(followLinks: false);
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._listDirectory failed path=${directory.path}',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  Set<GitStatus> _statusFile(Repository repo, String relativePath) {
    try {
      return repo.statusFile(relativePath);
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'Repository.statusFile failed path=$relativePath',
        error: error,
        stackTrace: stackTrace,
      );
      return const {};
    }
  }

  bool _isGitInternalPath(String relativePath) {
    return relativePath == '.git' || relativePath.startsWith('.git/');
  }

  bool _isNestedGitRepository(Directory directory) {
    return Directory(p.join(directory.path, '.git')).existsSync() ||
        File(p.join(directory.path, '.git')).existsSync();
  }

  bool _isIgnoredPath(Repository repo, String relativePath) {
    try {
      return Ignore.pathIsIgnored(repo: repo, path: relativePath) ||
          Ignore.pathIsIgnored(repo: repo, path: '$relativePath/');
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'Ignore.pathIsIgnored failed path=$relativePath',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  List<String> _statusLabels(Set<GitStatus> statuses) {
    if (statuses.contains(GitStatus.conflicted)) return const ['冲突'];
    return [
      if (statuses.contains(GitStatus.indexNew)) '已暂存新增',
      if (statuses.contains(GitStatus.indexModified)) '已暂存修改',
      if (statuses.contains(GitStatus.indexDeleted)) '已暂存删除',
      if (statuses.contains(GitStatus.indexRenamed)) '已暂存重命名',
      if (statuses.contains(GitStatus.indexTypeChange)) '已暂存类型变化',
      if (statuses.contains(GitStatus.wtNew)) '未跟踪',
      if (statuses.contains(GitStatus.wtModified)) '工作区修改',
      if (statuses.contains(GitStatus.wtDeleted)) '工作区删除',
      if (statuses.contains(GitStatus.wtRenamed)) '工作区重命名',
      if (statuses.contains(GitStatus.wtTypeChange)) '工作区类型变化',
      if (statuses.contains(GitStatus.ignored)) '已忽略',
    ];
  }

  bool _isIndexStatus(Set<GitStatus> statuses) {
    return statuses.any(
      const {
        GitStatus.indexNew,
        GitStatus.indexModified,
        GitStatus.indexDeleted,
        GitStatus.indexRenamed,
        GitStatus.indexTypeChange,
      }.contains,
    );
  }

  bool _isWorktreeStatus(Set<GitStatus> statuses) {
    return statuses.any(
      const {
        GitStatus.wtNew,
        GitStatus.wtModified,
        GitStatus.wtDeleted,
        GitStatus.wtRenamed,
        GitStatus.wtTypeChange,
      }.contains,
    );
  }

  List<GitBranchInfo> _branches(Repository repo) {
    GitDebugLog.log('GitRepositoryService._branches start');
    return [
      ..._branchInfos(repo, remote: false),
      ..._remoteBranchInfosFromRefs(repo),
    ];
  }

  List<GitBranchInfo> _branchInfos(Repository repo, {required bool remote}) {
    GitDebugLog.log('GitRepositoryService._branchInfos start remote=$remote');
    final branches = remote ? repo.branchesRemote : repo.branchesLocal;
    final infos = [
      for (final branch in branches)
        GitBranchInfo(
          name: branch.name,
          targetSha: branch.target.sha,
          isCurrent: !remote && branch.isHead,
          isRemote: remote,
          upstream: remote ? '' : _branchUpstream(branch),
        ),
    ];
    GitDebugLog.log(
      'GitRepositoryService._branchInfos end remote=$remote count=${infos.length}',
    );
    return infos;
  }

  List<GitBranchInfo> _remoteBranchInfosFromRefs(Repository repo) {
    GitDebugLog.log('GitRepositoryService._remoteBranchInfosFromRefs start');
    final refs = _remoteRefTargets(repo);
    final branches = [
      for (final entry in refs.entries)
        GitBranchInfo(
          name: entry.key,
          targetSha: entry.value,
          isCurrent: false,
          isRemote: true,
          upstream: '',
        ),
    ];
    branches.sort((a, b) => a.name.compareTo(b.name));
    GitDebugLog.log(
      'GitRepositoryService._remoteBranchInfosFromRefs end '
      'count=${branches.length}',
    );
    return branches;
  }

  Map<String, String> _remoteRefTargets(Repository repo) {
    final refs = <String, String>{};
    final gitDir = p.normalize(repo.path);
    _readPackedRemoteRefs(p.join(gitDir, 'packed-refs'), refs);
    _readLooseRemoteRefs(p.join(gitDir, 'refs', 'remotes'), refs);
    return refs;
  }

  void _readPackedRemoteRefs(String packedRefsPath, Map<String, String> refs) {
    final file = File(packedRefsPath);
    if (!file.existsSync()) return;

    try {
      for (final rawLine in file.readAsLinesSync()) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#') || line.startsWith('^')) {
          continue;
        }
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        final refName = parts[1];
        if (!refName.startsWith('refs/remotes/')) continue;
        final branchName = refName.substring('refs/remotes/'.length);
        if (_isRemoteHeadRef(branchName)) continue;
        refs[branchName] = parts[0];
      }
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._readPackedRemoteRefs failed '
        'path=$packedRefsPath',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _readLooseRemoteRefs(String refsRootPath, Map<String, String> refs) {
    final refsRoot = Directory(refsRootPath);
    if (!refsRoot.existsSync()) return;

    try {
      for (final entity in refsRoot.listSync(recursive: true)) {
        if (entity is! File) continue;
        final branchName = _gitPath(
          p.relative(entity.path, from: refsRootPath),
        );
        if (_isRemoteHeadRef(branchName)) continue;

        final value = entity.readAsStringSync().trim();
        if (value.isEmpty || value.startsWith('ref:')) continue;
        refs[branchName] = value;
      }
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._readLooseRemoteRefs failed path=$refsRootPath',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool _isRemoteHeadRef(String branchName) {
    return branchName.contains(' -> ') || branchName.endsWith('/HEAD');
  }

  String _branchUpstream(Branch branch) {
    try {
      return branch.upstream.shorthand;
    } catch (_) {
      return '';
    }
  }

  List<GitRemoteInfo> _remotes(Repository repo) {
    GitDebugLog.log('GitRepositoryService._remotes start');
    final remotes = <GitRemoteInfo>[];
    for (final name in repo.remotes) {
      GitDebugLog.log('Remote.lookup start name=$name');
      final remote = Remote.lookup(repo: repo, name: name);
      try {
        GitDebugLog.log('Remote.lookup end name=$name url=${remote.url}');
        remotes.add(
          GitRemoteInfo(
            name: remote.name,
            url: remote.url,
            pushUrl: remote.pushUrl.isEmpty ? remote.url : remote.pushUrl,
            fetchRefspecs: remote.fetchRefspecs,
            pushRefspecs: remote.pushRefspecs,
          ),
        );
      } finally {
        GitDebugLog.log('Remote.free name=$name');
        remote.free();
      }
    }
    GitDebugLog.log(
      'GitRepositoryService._remotes end count=${remotes.length}',
    );
    return remotes;
  }

  List<GitStashInfo> _stashes(Repository repo) {
    GitDebugLog.log('GitRepositoryService._stashes start');
    final stashes = [
      for (final stash in repo.stashes)
        GitStashInfo(
          index: stash.index,
          sha: stash.oid.sha,
          message: stash.message,
        ),
    ];
    GitDebugLog.log(
      'GitRepositoryService._stashes end count=${stashes.length}',
    );
    return stashes;
  }

  List<GitTagInfo> _tags(Repository repo) {
    GitDebugLog.log('GitRepositoryService._tagsFromRefs start');
    final refs = _tagRefTargets(repo);
    final tags = [
      for (final entry in refs.entries)
        GitTagInfo(name: entry.key, targetSha: entry.value),
    ];
    tags.sort((a, b) => a.name.compareTo(b.name));
    GitDebugLog.log('GitRepositoryService._tags end count=${tags.length}');
    return tags;
  }

  Map<String, String> _tagRefTargets(Repository repo) {
    final refs = <String, String>{};
    final gitDir = p.normalize(repo.path);
    _readPackedTagRefs(p.join(gitDir, 'packed-refs'), refs);
    _readLooseTagRefs(p.join(gitDir, 'refs', 'tags'), refs);
    return refs;
  }

  void _readPackedTagRefs(String packedRefsPath, Map<String, String> refs) {
    final file = File(packedRefsPath);
    if (!file.existsSync()) return;

    try {
      for (final rawLine in file.readAsLinesSync()) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#') || line.startsWith('^')) {
          continue;
        }
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        final refName = parts[1];
        if (!refName.startsWith('refs/tags/')) continue;
        refs[refName.substring('refs/tags/'.length)] = parts[0];
      }
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._readPackedTagRefs failed path=$packedRefsPath',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _readLooseTagRefs(String refsRootPath, Map<String, String> refs) {
    final refsRoot = Directory(refsRootPath);
    if (!refsRoot.existsSync()) return;

    try {
      for (final entity in refsRoot.listSync(recursive: true)) {
        if (entity is! File) continue;
        final name = _gitPath(p.relative(entity.path, from: refsRootPath));
        final value = entity.readAsStringSync().trim();
        if (value.isEmpty || value.startsWith('ref:')) continue;
        refs[name] = value;
      }
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._readLooseTagRefs failed path=$refsRootPath',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  List<GitSubmoduleInfo> _submodules(Repository repo) {
    GitDebugLog.log('GitRepositoryService._submodules start');
    final submodules = <GitSubmoduleInfo>[];
    for (final path in repo.submodules) {
      GitDebugLog.log('Submodule.lookup start path=$path');
      final submodule = Submodule.lookup(repo: repo, name: path);
      try {
        GitDebugLog.log(
          'Submodule.lookup end path=$path name=${submodule.name}',
        );
        submodules.add(
          GitSubmoduleInfo(
            name: submodule.name,
            path: submodule.path,
            url: submodule.url,
            branch: submodule.branch,
            statusLabels: [
              for (final status in submodule.status()) status.name,
            ],
          ),
        );
      } finally {
        GitDebugLog.log('Submodule.free path=$path');
        submodule.free();
      }
    }
    GitDebugLog.log(
      'GitRepositoryService._submodules end count=${submodules.length}',
    );
    return submodules;
  }

  List<GitWorktreeInfo> _worktrees(Repository repo) {
    GitDebugLog.log('GitRepositoryService._worktrees start');
    final rootPath = _normalizeWorkdir(repo.workdir);
    final worktrees = <GitWorktreeInfo>[];
    for (final name in repo.worktrees) {
      GitDebugLog.log('Worktree.lookup start name=$name');
      final worktree = Worktree.lookup(repo: repo, name: name);
      try {
        GitDebugLog.log('Worktree.lookup end name=$name path=${worktree.path}');
        final worktreePath = p.normalize(worktree.path);
        if (p.equals(worktreePath, rootPath)) continue;
        worktrees.add(
          GitWorktreeInfo(
            name: worktree.name,
            path: worktree.path,
            isLocked: worktree.isLocked,
            isPrunable: worktree.isPrunable,
            isValid: worktree.isValid,
          ),
        );
      } finally {
        GitDebugLog.log('Worktree.free name=$name');
        worktree.free();
      }
    }
    GitDebugLog.log(
      'GitRepositoryService._worktrees end count=${worktrees.length}',
    );
    return worktrees;
  }

  List<GitCommitInfo> _commits(
    Repository repo, {
    int limit = 80,
    String? pathspec,
  }) {
    GitDebugLog.log(
      'GitRepositoryService._commits start limit=$limit pathspec=$pathspec',
    );
    if (_isEmpty(repo)) return const [];
    final walker = RevWalk(repo);
    try {
      GitDebugLog.log('RevWalk.sorting start pathspec=$pathspec');
      walker.sorting(const {GitSort.topological, GitSort.time});
      GitDebugLog.log('RevWalk.pushHead start pathspec=$pathspec');
      walker.pushHead();
      final walkLimit = pathspec == null ? limit : 2000;
      final commits = <GitCommitInfo>[];
      for (final commit in walker.walk(limit: walkLimit)) {
        if (commits.length % 20 == 0) {
          GitDebugLog.log(
            'RevWalk progress pathspec=$pathspec count=${commits.length} '
            'oid=${commit.oid.sha}',
          );
        }
        if (pathspec != null && !_commitTouchesPath(repo, commit, pathspec)) {
          continue;
        }
        commits.add(_commitInfo(commit));
        if (commits.length >= limit) break;
      }
      GitDebugLog.log(
        'GitRepositoryService._commits end count=${commits.length} '
        'pathspec=$pathspec',
      );
      return commits;
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._commits failed pathspec=$pathspec',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    } finally {
      GitDebugLog.log('RevWalk.free pathspec=$pathspec');
      walker.free();
    }
  }

  GitCommitInfo _commitInfo(Commit commit) {
    return GitCommitInfo(
      sha: commit.oid.sha,
      shortSha: commit.oid.toStrN(7),
      summary: commit.summary,
      author: commit.author.name,
      email: commit.author.email,
      time: DateTime.fromMillisecondsSinceEpoch(
        commit.time * 1000,
        isUtc: true,
      ).toLocal(),
      parentShas: [for (final parent in commit.parents) parent.sha],
    );
  }

  bool _commitTouchesPath(Repository repo, Commit commit, String pathspec) {
    final path = _gitPath(pathspec);
    try {
      if (commit.parents.isEmpty) {
        commit.tree[path];
        return true;
      }
      for (var i = 0; i < commit.parents.length; i += 1) {
        final parent = commit.parent(i);
        final diff = Diff.treeToTree(
          repo: repo,
          oldTree: parent.tree,
          newTree: commit.tree,
        );
        try {
          for (final delta in diff.deltas) {
            if (_gitPath(delta.oldFile.path) == path ||
                _gitPath(delta.newFile.path) == path) {
              return true;
            }
          }
        } finally {
          diff.free();
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<List<GitConflictInfo>> _conflicts(
    Repository repo,
    List<GitStatusEntry> entries,
  ) async {
    final index = repo.index;
    try {
      return [
        for (final entry in entries)
          if (entry.isConflicted)
            _conflictInfo(repo, index.conflict(_gitPath(entry.path))),
      ];
    } finally {
      index.free();
    }
  }

  GitConflictInfo _conflictInfo(Repository repo, ConflictEntry conflict) {
    final path =
        conflict.our?.path ??
        conflict.their?.path ??
        conflict.ancestor?.path ??
        '';
    return GitConflictInfo(
      path: path,
      ancestorPath: conflict.ancestor?.path ?? path,
      oursPath: conflict.our?.path ?? path,
      theirsPath: conflict.their?.path ?? path,
      basePreview: _indexEntryPreview(repo, conflict.ancestor),
      oursPreview: _indexEntryPreview(repo, conflict.our),
      theirsPreview: _indexEntryPreview(repo, conflict.their),
      mergedPreview: _filePreview(_normalizeWorkdir(repo.workdir), path),
    );
  }

  String _indexEntryPreview(Repository repo, IndexEntry? entry) {
    if (entry == null) return '';
    try {
      final blob = Blob.lookup(repo: repo, oid: entry.oid);
      try {
        return blob.isBinary ? '[Binary file]' : blob.content;
      } finally {
        blob.free();
      }
    } catch (_) {
      return '';
    }
  }

  String _filePreview(String rootPath, String filePath) {
    final file = File(p.join(rootPath, filePath));
    if (!file.existsSync()) return '';
    try {
      return file.readAsStringSync();
    } on FormatException {
      return '[Binary file]';
    }
  }

  String _repositoryStateLabel(Repository repo) {
    return switch (repo.state) {
      GitRepositoryState.none => '空闲',
      GitRepositoryState.merge => '合并中',
      GitRepositoryState.cherrypick ||
      GitRepositoryState.cherrypickSequence => 'Cherry-pick 中',
      GitRepositoryState.rebase ||
      GitRepositoryState.rebaseInteractive ||
      GitRepositoryState.rebaseMerge ||
      GitRepositoryState.applyMailboxOrRebase => 'Rebase 中',
      GitRepositoryState.revert ||
      GitRepositoryState.revertSequence => 'Revert 中',
      GitRepositoryState.bisect => 'Bisect 中',
      GitRepositoryState.applyMailbox => 'Apply mailbox 中',
    };
  }

  String? _configValue(Repository repo, String key) {
    try {
      final value = repo.config.getString(key).trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  void _checkoutBranch(
    Repository repo,
    String name, {
    required bool remote,
    Set<GitCheckout> strategy = const {
      GitCheckout.safe,
      GitCheckout.recreateMissing,
    },
  }) {
    final branchName = name.trim();
    if (branchName.isEmpty) throw ArgumentError('分支名称不能为空。');

    final localName = remote
        ? _localBranchNameForRemote(branchName)
        : branchName;
    if (remote) _ensureLocalTrackingBranch(repo, branchName, localName);

    final refName = _localRefName(localName);
    final targetCommit = _commitFromSpec(repo, refName);
    if (strategy.contains(GitCheckout.safe)) {
      final blockedPaths = _checkoutBlockedPaths(repo, targetCommit);
      if (blockedPaths.isNotEmpty) {
        throw GitCheckoutBlockedException(
          message: '以下本地更改会被切换分支覆盖，请先处理后重试。',
          paths: blockedPaths,
        );
      }
    }

    try {
      Checkout.reference(repo: repo, name: refName, strategy: strategy);
      repo.setHead(refName);
    } catch (error) {
      throw GitCheckoutBlockedException(
        message: error.toString(),
        paths: _checkoutBlockedPaths(repo, targetCommit),
      );
    }
  }

  void _ensureLocalTrackingBranch(
    Repository repo,
    String remoteBranchName,
    String localName,
  ) {
    try {
      Branch.lookup(repo: repo, name: localName);
      return;
    } catch (_) {
      // Create the branch below.
    }

    final remoteRef = Reference.lookup(
      repo: repo,
      name: 'refs/remotes/$remoteBranchName',
    );
    final target = Commit.lookup(repo: repo, oid: remoteRef.target);
    final localBranch = Branch.create(
      repo: repo,
      name: localName,
      target: target,
    );
    try {
      localBranch.setUpstream(remoteBranchName);
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._ensureLocalTrackingBranch setUpstream failed '
        'remote=$remoteBranchName local=$localName',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  List<String> _checkoutBlockedPaths(Repository repo, Commit targetCommit) {
    final dirtyEntries = _statusEntries(
      repo,
    ).where((entry) => entry.isUnstaged || entry.isUntracked).toList();
    if (dirtyEntries.isEmpty) return const [];

    final targetChangedPaths = _changedPaths(
      repo,
      oldTree: _headTreeOrNull(repo),
      newTree: targetCommit.tree,
    );
    return [
      for (final entry in dirtyEntries)
        if ((entry.isUntracked &&
                _treeContains(targetCommit.tree, entry.path)) ||
            (!entry.isUntracked &&
                targetChangedPaths.contains(_gitPath(entry.path))))
          entry.path,
    ];
  }

  Set<String> _changedPaths(
    Repository repo, {
    Tree? oldTree,
    required Tree newTree,
  }) {
    final diff = Diff.treeToTree(
      repo: repo,
      oldTree: oldTree,
      newTree: newTree,
    );
    try {
      return {
        for (final delta in diff.deltas) ...[
          _gitPath(delta.oldFile.path),
          _gitPath(delta.newFile.path),
        ],
      }..remove('');
    } finally {
      diff.free();
    }
  }

  bool _treeContains(Tree tree, String filePath) {
    try {
      tree[_gitPath(filePath)];
      return true;
    } catch (_) {
      return false;
    }
  }

  void _merge(Repository repo, String targetSpec) {
    final annotated = AnnotatedCommit.fromRevSpec(repo: repo, spec: targetSpec);
    try {
      final analysis = Merge.analysis(repo: repo, theirHead: annotated.oid);
      if (analysis.result.contains(GitMergeAnalysis.upToDate)) return;
      if (analysis.result.contains(GitMergeAnalysis.fastForward) ||
          analysis.result.contains(GitMergeAnalysis.unborn)) {
        _fastForward(repo, annotated.oid);
        return;
      }
      Merge.commit(repo: repo, commit: annotated);
    } finally {
      annotated.free();
    }
  }

  void _fastForward(Repository repo, Oid target) {
    if (repo.isHeadDetached) {
      repo.setHead(target);
      Checkout.head(repo: repo);
      return;
    }
    final head = repo.head;
    Reference.setTarget(
      repo: repo,
      name: head.name,
      target: target,
      logMessage: 'PyriteIDE fast-forward',
    );
    repo.setHead(head.name);
    Checkout.head(repo: repo);
  }

  void _advanceRebase(Repository repo, Rebase rebase, GitCommitInput input) {
    while (true) {
      try {
        rebase.next();
      } catch (_) {
        rebase.finish();
        return;
      }
      if (repo.index.hasConflicts) return;
      rebase.commit(committer: _signature(input));
    }
  }

  Commit _headCommit(Repository repo) {
    final commit = _headCommitOrNull(repo);
    if (commit == null) throw StateError('当前仓库还没有提交。');
    return commit;
  }

  Commit? _headCommitOrNull(Repository repo) {
    try {
      return repo.head.peel(GitObject.commit) as Commit;
    } catch (_) {
      return null;
    }
  }

  Oid? _headOidOrNull(Repository repo) {
    try {
      return repo.head.target;
    } catch (_) {
      return null;
    }
  }

  Tree? _headTreeOrNull(Repository repo) {
    try {
      return _headCommit(repo).tree;
    } catch (_) {
      return null;
    }
  }

  List<Commit> _commitParents(Repository repo) {
    final parents = <Commit>[];
    final head = _headCommitOrNull(repo);
    if (head != null) parents.add(head);
    for (final sha in repo.mergeHeadOids) {
      try {
        parents.add(Commit.lookup(repo: repo, oid: repo[sha]));
      } catch (_) {
        // Ignore stale merge heads.
      }
    }
    return parents;
  }

  Commit _commitFromSpec(Repository repo, String spec) {
    final object = _objectFromSpec(repo, spec);
    if (object is Commit) return object;
    if (object is Tag) return object.peel(GitObject.commit) as Commit;
    throw ArgumentError('目标不是提交：$spec');
  }

  Object _objectFromSpec(Repository repo, String spec) {
    return RevParse.single(repo: repo, spec: spec);
  }

  GitObject _objectType(Object object) {
    return switch (object) {
      Commit() => GitObject.commit,
      Tree() => GitObject.tree,
      Blob() => GitObject.blob,
      Tag() => GitObject.tag,
      _ => GitObject.any,
    };
  }

  String? _upstreamSpec(Repository repo, String branchName) {
    try {
      final branch = Branch.lookup(repo: repo, name: branchName);
      return branch.upstream.shorthand;
    } catch (_) {
      return null;
    }
  }

  Signature _signature(GitCommitInput input) {
    final now = DateTime.now();
    return Signature.create(
      name: _authorName(input),
      email: _authorEmail(input),
      time: now.millisecondsSinceEpoch ~/ 1000,
      offset: now.timeZoneOffset.inMinutes,
    );
  }

  Signature _defaultSignature(Repository repo) {
    try {
      return repo.defaultSignature;
    } catch (_) {
      return Signature.create(
        name: 'Pyrite User',
        email: 'pyrite@example.local',
      );
    }
  }

  String _authorName(GitCommitInput input) {
    return input.authorName.trim().isEmpty
        ? 'Pyrite User'
        : input.authorName.trim();
  }

  String _authorEmail(GitCommitInput input) {
    return input.authorEmail.trim().isEmpty
        ? 'pyrite@example.local'
        : input.authorEmail.trim();
  }

  Callbacks _callbacks(GitCredentialDraft draft) {
    return Callbacks(credentials: _credentials(draft));
  }

  Credentials? _credentials(GitCredentialDraft draft) {
    return switch (draft.mode) {
      GitCredentialMode.httpsToken =>
        draft.token.trim().isEmpty
            ? null
            : UserPass(
                username: draft.username.trim().isEmpty
                    ? 'oauth2'
                    : draft.username.trim(),
                password: draft.token.trim(),
              ),
      GitCredentialMode.sshAgent => KeypairFromAgent(
        draft.username.trim().isEmpty ? 'git' : draft.username.trim(),
      ),
      GitCredentialMode.sshKey =>
        draft.privateKeyPath.trim().isEmpty
            ? null
            : Keypair(
                username: draft.username.trim().isEmpty
                    ? 'git'
                    : draft.username.trim(),
                pubKey: draft.publicKeyPath.trim(),
                privateKey: draft.privateKeyPath.trim(),
                passPhrase: draft.passphrase,
              ),
      GitCredentialMode.none => null,
    };
  }

  DateTime? _signatureTime(Signature? signature) {
    if (signature == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      signature.time * 1000,
      isUtc: true,
    ).toLocal();
  }

  Iterable<String> _cleanPaths(Iterable<String> paths) {
    return paths.map((path) => path.trim()).where((path) => path.isNotEmpty);
  }

  String _localBranchNameForRemote(String remoteBranchName) {
    if (remoteBranchName.contains(' -> ') ||
        remoteBranchName.endsWith('/HEAD')) {
      throw ArgumentError('不能切换到远端 HEAD 指针。');
    }
    final separator = remoteBranchName.indexOf('/');
    if (separator == -1 || separator == remoteBranchName.length - 1) {
      return remoteBranchName;
    }
    return remoteBranchName.substring(separator + 1);
  }

  String _localRefName(String branchName) {
    return branchName.startsWith('refs/')
        ? branchName
        : 'refs/heads/$branchName';
  }

  String _gitPath(String value) => p.normalize(value).replaceAll('\\', '/');

  String _normalizeWorkdir(String workdir) {
    final normalized = p.normalize(workdir);
    if (normalized.endsWith('/') || normalized.endsWith('\\')) {
      return p.normalize(p.dirname(normalized));
    }
    return normalized;
  }

  Future<void> _deleteUntrackedPath(
    String rootPath,
    String relativePath,
  ) async {
    final target = p.normalize(p.absolute(p.join(rootPath, relativePath)));
    final root = p.normalize(p.absolute(rootPath));
    if (!p.equals(root, target) && !p.isWithin(root, target)) {
      throw ArgumentError('不能删除仓库外路径：$relativePath');
    }

    final type = FileSystemEntity.typeSync(target);
    if (type == FileSystemEntityType.directory) {
      await Directory(target).delete(recursive: true);
    } else if (type == FileSystemEntityType.file ||
        type == FileSystemEntityType.link) {
      await File(target).delete();
    }
  }

  T? _tryValue<T>(T Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }
}

class GitCheckoutBlockedException implements Exception {
  const GitCheckoutBlockedException({
    required this.message,
    required this.paths,
  });

  final String message;
  final List<String> paths;

  @override
  String toString() => message;
}
