import 'dart:io';

import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/git/git_models.dart';

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
  GitRepositorySnapshot? loadSnapshot(String? workspacePath) {
    final rootPath = discoverRoot(workspacePath);
    if (rootPath == null) return null;

    return _withRepo(rootPath, (repo) {
      final head = _safe(() => repo.head);
      final headCommit = _safe(() => repo.headCommit);
      final branchName = _currentBranchName(repo, head);
      final aheadBehind = _aheadBehind(repo, branchName);
      final defaultSignature = _safe(() => repo.defaultSignature);
      final index = repo.index;
      final headTree = headCommit?.tree;
      final stagedPatch = _safe(
        () => Diff.treeToIndex(repo: repo, tree: headTree, index: index).patch,
      );
      final unstagedPatch = _safe(
        () => Diff.indexToWorkdir(repo: repo, index: index).patch,
      );

      return GitRepositorySnapshot(
        rootPath: _normalizeWorkdir(repo),
        gitDir: repo.path,
        branchLabel: branchName ?? _detachedLabel(repo),
        stateLabel: _repositoryStateLabel(repo.state),
        isDetached: _safe(() => repo.isHeadDetached) ?? false,
        isEmpty: _safe(() => repo.isEmpty) ?? false,
        authorName: defaultSignature?.name ?? 'Pyrite User',
        authorEmail: defaultSignature?.email ?? 'pyrite@example.local',
        ahead: aheadBehind.$1,
        behind: aheadBehind.$2,
        statusEntries: _statusEntries(_statusMap(repo)),
        branches: _branches(repo),
        remotes: _remotes(repo),
        stashes: _stashes(repo),
        tags: _tags(repo),
        submodules: _submodules(repo),
        worktrees: _worktrees(repo),
        commits: _commits(repo),
        conflicts: _conflicts(repo),
        stagedPatch: stagedPatch ?? '',
        unstagedPatch: unstagedPatch ?? '',
      );
    });
  }

  String? discoverRoot(String? workspacePath) {
    if (workspacePath == null || workspacePath.isEmpty) return null;

    try {
      final discovered = Repository.discover(startPath: workspacePath);
      return _withRepo(discovered, _normalizeWorkdir);
    } catch (_) {
      return null;
    }
  }

  String diffForPath(String rootPath, String filePath, {bool staged = false}) {
    return _withRepo(rootPath, (repo) {
      final diff = staged
          ? Diff.treeToIndex(
              repo: repo,
              tree: _safe(() => repo.headCommit.tree),
              index: repo.index,
            )
          : Diff.indexToWorkdir(repo: repo, index: repo.index);
      final patches = diff.patches.where((patch) {
        final delta = patch.delta;
        return delta.oldFile.path == filePath || delta.newFile.path == filePath;
      });
      return patches.map((patch) => patch.text).join('\n');
    });
  }

  List<GitCommitInfo> fileHistory(String rootPath, String filePath) {
    return _withRepo(rootPath, (repo) {
      final commits = _commits(repo, limit: 200);
      final filtered = <GitCommitInfo>[];
      for (final info in commits) {
        final commit = _safe(
          () => Commit.lookup(repo: repo, oid: repo[info.sha]),
        );
        if (commit == null) continue;
        if (_commitTouchesPath(repo, commit, filePath)) {
          filtered.add(info);
        }
      }
      return filtered;
    });
  }

  List<GitBlameLine> blame(String rootPath, String filePath) {
    return _withRepo(rootPath, (repo) {
      final blame = Blame.file(repo: repo, path: filePath);
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
    });
  }

  void stage(String rootPath, Iterable<String> paths) {
    _withRepo(rootPath, (repo) {
      final index = repo.index;
      final status = _statusMap(repo);
      for (final filePath in paths) {
        final flags = status[filePath] ?? {};
        if (flags.contains(GitStatus.wtDeleted)) {
          index.remove(filePath);
        } else {
          index.add(filePath);
        }
      }
      index.write();
    });
  }

  void unstage(String rootPath, Iterable<String> paths) {
    _withRepo(rootPath, (repo) {
      repo.resetDefault(
        oid: _safe(() => repo.head.target),
        pathspec: paths.toList(),
      );
    });
  }

  void commit(String rootPath, GitCommitInput input) {
    _withRepo(rootPath, (repo) {
      if (repo.index.hasConflicts) {
        throw StateError('仍有冲突未解决，不能提交。');
      }
      final message = input.message.trim();
      if (message.isEmpty) {
        throw ArgumentError('提交信息不能为空。');
      }
      final signature = _signature(input);
      final tree = Tree.lookup(repo: repo, oid: repo.index.writeTree());
      Commit.create(
        repo: repo,
        updateRef: 'HEAD',
        message: '$message\n',
        author: signature,
        committer: signature,
        tree: tree,
        parents: _commitParents(repo),
      );
      _cleanupPreparedMessage(repo);
      _safe(() => repo.stateCleanup());
    });
  }

  void createBranch(String rootPath, String name) {
    _withRepo(rootPath, (repo) {
      final branchName = name.trim();
      if (branchName.isEmpty) throw ArgumentError('分支名称不能为空。');
      Branch.create(repo: repo, name: branchName, target: repo.headCommit);
    });
  }

  void checkoutBranch(String rootPath, String name) {
    _withRepo(rootPath, (repo) {
      Checkout.reference(repo: repo, name: 'refs/heads/$name');
      repo.setHead('refs/heads/$name');
    });
  }

  void stash(
    String rootPath,
    GitCommitInput input, {
    bool includeUntracked = true,
  }) {
    _withRepo(rootPath, (repo) {
      Stash.create(
        repo: repo,
        stasher: _signature(input),
        message: input.message.trim().isEmpty ? null : input.message.trim(),
        flags: includeUntracked ? {GitStash.includeUntracked} : {},
      );
    });
  }

  void applyStash(String rootPath, int index, {bool pop = false}) {
    _withRepo(rootPath, (repo) {
      if (pop) {
        Stash.pop(repo: repo, index: index, reinstateIndex: true);
      } else {
        Stash.apply(repo: repo, index: index, reinstateIndex: true);
      }
    });
  }

  void dropStash(String rootPath, int index) {
    _withRepo(rootPath, (repo) => Stash.drop(repo: repo, index: index));
  }

  String fetch(String rootPath, String remoteName, GitCredentialDraft draft) {
    return _withRepo(rootPath, (repo) {
      final remote = Remote.lookup(repo: repo, name: remoteName);
      final stats = remote.fetch(callbacks: _callbacks(draft));
      return '收到 ${stats.receivedObjects}/${stats.totalObjects} 个对象';
    });
  }

  String push(String rootPath, String remoteName, GitCredentialDraft draft) {
    return _withRepo(rootPath, (repo) {
      final branch = _currentBranchName(repo, _safe(() => repo.head));
      if (branch == null || branch.startsWith('HEAD@')) {
        throw StateError('当前不是可推送的本地分支。');
      }
      final remote = Remote.lookup(repo: repo, name: remoteName);
      remote.push(
        refspecs: ['refs/heads/$branch:refs/heads/$branch'],
        callbacks: _callbacks(draft),
      );
      return '已推送 $branch 到 $remoteName';
    });
  }

  String pull(String rootPath, String remoteName, GitCredentialDraft draft) {
    return _withRepo(rootPath, (repo) {
      final remote = Remote.lookup(repo: repo, name: remoteName);
      final stats = remote.fetch(callbacks: _callbacks(draft));
      final branchName = _currentBranchName(repo, _safe(() => repo.head));
      if (branchName == null) {
        throw StateError('当前 HEAD 分离，不能自动 pull。');
      }
      final branch = Branch.lookup(repo: repo, name: branchName);
      final upstream = branch.upstream;
      Merge.commit(
        repo: repo,
        commit: AnnotatedCommit.lookup(repo: repo, oid: upstream.target),
      );
      return '收到 ${stats.receivedObjects}/${stats.totalObjects} 个对象；'
          '已将 ${upstream.shorthand} 合并到 $branchName';
    });
  }

  void merge(String rootPath, String targetSpec) {
    _withRepo(rootPath, (repo) {
      final commit = _commitFromSpec(repo, targetSpec);
      Merge.commit(
        repo: repo,
        commit: AnnotatedCommit.lookup(repo: repo, oid: commit.oid),
      );
    });
  }

  void rebase(String rootPath, String targetSpec, GitCommitInput input) {
    _withRepo(rootPath, (repo) {
      final signature = _signature(input);
      final target = _commitFromSpec(repo, targetSpec);
      final rebase = Rebase.init(
        repo: repo,
        onto: AnnotatedCommit.lookup(repo: repo, oid: target.oid),
      );
      _runRebaseUntilConflict(repo, rebase, signature);
    });
  }

  void continueRebase(String rootPath, GitCommitInput input) {
    _withRepo(rootPath, (repo) {
      if (repo.index.hasConflicts) {
        throw StateError('仍有冲突未解决，不能继续 rebase。');
      }
      final rebase = Rebase.open(repo);
      final signature = _signature(input);
      rebase.commit(committer: signature, author: signature);
      _runRebaseUntilConflict(repo, rebase, signature);
    });
  }

  void abortRebase(String rootPath) {
    _withRepo(rootPath, (repo) => Rebase.open(repo).abort());
  }

  void cherryPick(String rootPath, String targetSpec) {
    _withRepo(rootPath, (repo) {
      Merge.cherryPick(repo: repo, commit: _commitFromSpec(repo, targetSpec));
    });
  }

  void markResolved(String rootPath, String filePath) {
    _withRepo(rootPath, (repo) {
      final index = repo.index;
      index.add(filePath);
      index.write();
    });
  }

  void acceptConflictSide(
    String rootPath,
    String filePath,
    GitMergeFileFavor favor,
  ) {
    _withRepo(rootPath, (repo) {
      final conflict = repo.index.conflicts[filePath];
      if (conflict == null || conflict.our == null || conflict.their == null) {
        throw StateError('没有找到 $filePath 的三方冲突。');
      }
      final merged = Merge.fileFromIndex(
        repo: repo,
        ancestor: conflict.ancestor,
        ancestorLabel: 'base',
        ours: conflict.our!,
        oursLabel: 'ours',
        theirs: conflict.their!,
        theirsLabel: 'theirs',
        favor: favor,
        flags: {GitMergeFileFlag.styleDiff3},
      );
      final target = File(p.join(_normalizeWorkdir(repo), filePath));
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(merged);
      markResolved(rootPath, filePath);
    });
  }

  void createTag(String rootPath, String name, {String? targetSpec}) {
    _withRepo(rootPath, (repo) {
      final tagName = name.trim();
      if (tagName.isEmpty) throw ArgumentError('标签名称不能为空。');
      final target = targetSpec == null || targetSpec.trim().isEmpty
          ? repo.head.target
          : _commitFromSpec(repo, targetSpec).oid;
      Tag.createLightweight(
        repo: repo,
        tagName: tagName,
        target: target,
        targetType: GitObject.commit,
      );
    });
  }

  void createWorktree(String rootPath, String name, String path) {
    _withRepo(rootPath, (repo) {
      Worktree.create(repo: repo, name: name.trim(), path: path.trim());
    });
  }

  void pruneWorktree(String rootPath, String name) {
    _withRepo(rootPath, (repo) {
      Worktree.lookup(repo: repo, name: name).prune({GitWorktree.pruneValid});
    });
  }

  void updateSubmodule(String rootPath, String name, GitCredentialDraft draft) {
    _withRepo(rootPath, (repo) {
      Submodule.update(
        repo: repo,
        name: name,
        init: true,
        callbacks: _callbacks(draft),
      );
    });
  }

  void writeCommitGraph(String rootPath) {
    _withRepo(rootPath, (repo) {
      final writer = CommitGraphWriter(p.join(repo.path, 'objects', 'info'));
      final walk = RevWalk(repo)..pushHead();
      writer.addRevWalk(walk);
      writer.commit();
      writer.free();
      walk.free();
    });
  }

  T _withRepo<T>(String rootPath, T Function(Repository repo) action) {
    final repo = Repository.open(rootPath);
    try {
      return action(repo);
    } finally {
      repo.free();
    }
  }

  String _normalizeWorkdir(Repository repo) {
    final workdir = repo.workdir.isEmpty ? p.dirname(repo.path) : repo.workdir;
    return p.normalize(workdir);
  }

  String _relativePath(String rootPath, String filePath) {
    return p.relative(filePath, from: rootPath).split(p.separator).join('/');
  }

  bool _isInsideGitDir(String relativePath) {
    return relativePath.split('/').contains('.git');
  }

  String? _currentBranchName(Repository repo, Reference? head) {
    if (head == null || (_safe(() => repo.isHeadDetached) ?? false)) {
      return null;
    }
    return _safe(() => head.shorthand);
  }

  String _detachedLabel(Repository repo) {
    final sha = _safe(() => repo.head.target.sha);
    if (sha == null) return '未提交仓库';
    return 'HEAD@${_shortSha(sha)}';
  }

  (int, int) _aheadBehind(Repository repo, String? branchName) {
    if (branchName == null) return (0, 0);
    return _safe(() {
          final branch = Branch.lookup(repo: repo, name: branchName);
          final upstream = branch.upstream;
          final values = repo.aheadBehind(
            local: branch.target,
            upstream: upstream.target,
          );
          return (values[0], values[1]);
        }) ??
        (0, 0);
  }

  List<GitStatusEntry> _statusEntries(Map<String, Set<GitStatus>> status) {
    final entries = [
      for (final item in status.entries)
        GitStatusEntry(
          path: item.key,
          labels: _statusLabels(item.value),
          isStaged: item.value.any(_isIndexStatus),
          isUnstaged: item.value.any(_isWorktreeStatus),
          isConflicted: item.value.contains(GitStatus.conflicted),
        ),
    ];
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  Map<String, Set<GitStatus>> _statusMap(Repository repo) {
    final result = {
      for (final item in repo.status.entries) item.key: {...item.value},
    };
    final workdir = _normalizeWorkdir(repo);
    final root = Directory(workdir);
    if (!root.existsSync()) return result;

    // git2dart 0.5.0 builds full status lists with libgit2 defaults, which
    // omit untracked files. Ask libgit2 for per-file status so the SCM view
    // still reflects newly-created files without bypassing git2dart.
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = _relativePath(workdir, entity.path);
      if (_isInsideGitDir(relative) || result.containsKey(relative)) continue;
      final statuses = _safe(() => repo.statusFile(relative));
      if (statuses == null || !statuses.contains(GitStatus.wtNew)) continue;
      result[relative] = statuses;
    }
    return result;
  }

  List<String> _statusLabels(Set<GitStatus> statuses) {
    return [for (final status in statuses) _statusLabel(status)];
  }

  String _statusLabel(GitStatus status) {
    return switch (status) {
      GitStatus.indexNew => '已暂存新增',
      GitStatus.indexModified => '已暂存修改',
      GitStatus.indexDeleted => '已暂存删除',
      GitStatus.indexRenamed => '已暂存重命名',
      GitStatus.indexTypeChange => '已暂存类型变化',
      GitStatus.wtNew => '未跟踪',
      GitStatus.wtModified => '工作区修改',
      GitStatus.wtDeleted => '工作区删除',
      GitStatus.wtTypeChange => '工作区类型变化',
      GitStatus.wtRenamed => '工作区重命名',
      GitStatus.wtUnreadable => '不可读',
      GitStatus.ignored => '已忽略',
      GitStatus.conflicted => '冲突',
      GitStatus.current => '干净',
    };
  }

  bool _isIndexStatus(GitStatus status) {
    return status == GitStatus.indexNew ||
        status == GitStatus.indexModified ||
        status == GitStatus.indexDeleted ||
        status == GitStatus.indexRenamed ||
        status == GitStatus.indexTypeChange;
  }

  bool _isWorktreeStatus(GitStatus status) {
    return status == GitStatus.wtNew ||
        status == GitStatus.wtModified ||
        status == GitStatus.wtDeleted ||
        status == GitStatus.wtTypeChange ||
        status == GitStatus.wtRenamed ||
        status == GitStatus.wtUnreadable;
  }

  List<GitBranchInfo> _branches(Repository repo) {
    return [
      for (final branch in repo.branchesLocal) _branchInfo(branch, false),
      for (final branch in repo.branchesRemote) _branchInfo(branch, true),
    ];
  }

  GitBranchInfo _branchInfo(Branch branch, bool isRemote) {
    return GitBranchInfo(
      name: branch.name,
      targetSha: branch.target.sha,
      isCurrent: _safe(() => branch.isHead) ?? false,
      isRemote: isRemote,
      upstream: isRemote ? '' : _safe(() => branch.upstreamName) ?? '',
    );
  }

  List<GitRemoteInfo> _remotes(Repository repo) {
    return [
      for (final name in repo.remotes)
        _remoteInfo(Remote.lookup(repo: repo, name: name)),
    ];
  }

  GitRemoteInfo _remoteInfo(Remote remote) {
    return GitRemoteInfo(
      name: remote.name,
      url: remote.url,
      pushUrl: remote.pushUrl,
      fetchRefspecs: remote.fetchRefspecs,
      pushRefspecs: remote.pushRefspecs,
    );
  }

  List<GitStashInfo> _stashes(Repository repo) {
    return [
      for (final stash in repo.stashes)
        GitStashInfo(
          index: stash.index,
          sha: stash.oid.sha,
          message: stash.message,
        ),
    ];
  }

  List<GitTagInfo> _tags(Repository repo) {
    return [
      for (final tag in repo.tags)
        GitTagInfo(
          name: tag,
          targetSha:
              _safe(() {
                final ref = Reference.lookup(
                  repo: repo,
                  name: 'refs/tags/$tag',
                );
                return ref.target.sha;
              }) ??
              '',
        ),
    ];
  }

  List<GitSubmoduleInfo> _submodules(Repository repo) {
    return [
      for (final name in repo.submodules)
        _submoduleInfo(repo, Submodule.lookup(repo: repo, name: name)),
    ];
  }

  GitSubmoduleInfo _submoduleInfo(Repository repo, Submodule submodule) {
    return GitSubmoduleInfo(
      name: submodule.name,
      path: submodule.path,
      url: submodule.url,
      branch: submodule.branch,
      statusLabels: [
        for (final status in _safe(() => submodule.status()) ?? {})
          _enumTail(status),
      ],
    );
  }

  List<GitWorktreeInfo> _worktrees(Repository repo) {
    return [
      for (final name in repo.worktrees)
        _worktreeInfo(Worktree.lookup(repo: repo, name: name)),
    ];
  }

  GitWorktreeInfo _worktreeInfo(Worktree worktree) {
    return GitWorktreeInfo(
      name: worktree.name,
      path: worktree.path,
      isLocked: worktree.isLocked,
      isPrunable: worktree.isPrunable,
      isValid: worktree.isValid,
    );
  }

  List<GitCommitInfo> _commits(Repository repo, {int limit = 80}) {
    final head = _safe(() => repo.head.target);
    if (head == null) return const [];
    final walker = RevWalk(repo)
      ..sorting({GitSort.time, GitSort.topological})
      ..push(head);
    final commits = walker.walk(limit: limit);
    walker.free();
    return commits.map(_commitInfo).toList();
  }

  GitCommitInfo _commitInfo(Commit commit) {
    return GitCommitInfo(
      sha: commit.oid.sha,
      shortSha: _shortSha(commit.oid.sha),
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

  List<GitConflictInfo> _conflicts(Repository repo) {
    final index = repo.index;
    if (!index.hasConflicts) return const [];
    return [
      for (final item in index.conflicts.entries)
        if (item.value.our != null && item.value.their != null)
          GitConflictInfo(
            path: item.key,
            ancestorPath: item.value.ancestor?.path ?? '',
            oursPath: item.value.our?.path ?? '',
            theirsPath: item.value.their?.path ?? '',
            basePreview: _blobContent(repo, item.value.ancestor),
            oursPreview: _blobContent(repo, item.value.our),
            theirsPreview: _blobContent(repo, item.value.their),
            mergedPreview:
                _safe(
                  () => Merge.fileFromIndex(
                    repo: repo,
                    ancestor: item.value.ancestor,
                    ancestorLabel: 'base',
                    ours: item.value.our!,
                    oursLabel: 'ours',
                    theirs: item.value.their!,
                    theirsLabel: 'theirs',
                    flags: {GitMergeFileFlag.styleDiff3},
                  ),
                ) ??
                '',
          ),
    ];
  }

  String _blobContent(Repository repo, IndexEntry? entry) {
    if (entry == null) return '';
    return _safe(() {
          final blob = Blob.lookup(repo: repo, oid: entry.oid);
          if (blob.isBinary) return '[Binary file]';
          return blob.content;
        }) ??
        '';
  }

  bool _commitTouchesPath(Repository repo, Commit commit, String filePath) {
    final parents = commit.parents;
    if (parents.isEmpty) {
      return _safe(
            () => RevParse.single(
              repo: repo,
              spec: '${commit.oid.sha}:$filePath',
            ),
          ) !=
          null;
    }
    final parent = Commit.lookup(repo: repo, oid: parents.first);
    final diff = Diff.treeToTree(
      repo: repo,
      oldTree: parent.tree,
      newTree: commit.tree,
    );
    return diff.deltas.any((delta) {
      return delta.oldFile.path == filePath || delta.newFile.path == filePath;
    });
  }

  Commit _commitFromSpec(Repository repo, String spec) {
    final target = spec.trim();
    if (target.isEmpty) throw ArgumentError('目标不能为空。');
    final object = RevParse.single(repo: repo, spec: target);
    if (object is Commit) return object;
    if (object is Tag) return object.target as Commit;
    throw ArgumentError('目标必须解析为 commit。');
  }

  List<Commit> _commitParents(Repository repo) {
    final head = _safe(() => repo.headCommit);
    final parents = <Commit>[];
    if (head != null) {
      parents.add(head);
    }
    for (final oid in _mergeHeadOids(repo)) {
      if (head == null || oid.sha != head.oid.sha) {
        parents.add(Commit.lookup(repo: repo, oid: oid));
      }
    }
    return parents;
  }

  List<Oid> _mergeHeadOids(Repository repo) {
    final mergeHead = File(p.join(repo.path, 'MERGE_HEAD'));
    if (!mergeHead.existsSync()) return const [];
    return [
      for (final line in mergeHead.readAsLinesSync())
        if (line.trim().isNotEmpty) repo[line.trim()],
    ];
  }

  void _runRebaseUntilConflict(
    Repository repo,
    Rebase rebase,
    Signature signature,
  ) {
    while (true) {
      try {
        rebase.next();
      } catch (_) {
        rebase.finish();
        return;
      }
      if (repo.index.hasConflicts) return;
      rebase.commit(committer: signature, author: signature);
    }
  }

  Signature _signature(GitCommitInput input) {
    final name = input.authorName.trim().isEmpty
        ? 'Pyrite User'
        : input.authorName.trim();
    final email = input.authorEmail.trim().isEmpty
        ? 'pyrite@example.local'
        : input.authorEmail.trim();
    return Signature.create(name: name, email: email);
  }

  Callbacks _callbacks(GitCredentialDraft draft) {
    return Callbacks(credentials: _credentials(draft));
  }

  Credentials? _credentials(GitCredentialDraft draft) {
    return switch (draft.mode) {
      GitCredentialMode.none => null,
      GitCredentialMode.httpsToken => UserPass(
        username: draft.username.trim().isEmpty
            ? 'x-access-token'
            : draft.username.trim(),
        password: draft.token,
      ),
      GitCredentialMode.sshAgent => KeypairFromAgent(
        draft.username.trim().isEmpty ? 'git' : draft.username.trim(),
      ),
      GitCredentialMode.sshKey => Keypair(
        username: draft.username.trim().isEmpty ? 'git' : draft.username.trim(),
        pubKey: draft.publicKeyPath,
        privateKey: draft.privateKeyPath,
        passPhrase: draft.passphrase,
      ),
    };
  }

  void _cleanupPreparedMessage(Repository repo) {
    _safe(() => repo.removeMessage());
  }

  DateTime? _signatureTime(Signature? signature) {
    if (signature == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      signature.time * 1000,
      isUtc: true,
    ).toLocal();
  }

  String _repositoryStateLabel(GitRepositoryState state) {
    return switch (state) {
      GitRepositoryState.none => '空闲',
      GitRepositoryState.merge => '合并中',
      GitRepositoryState.revert => '回滚中',
      GitRepositoryState.revertSequence => '连续回滚中',
      GitRepositoryState.cherrypick => 'Cherry-pick 中',
      GitRepositoryState.cherrypickSequence => '连续 Cherry-pick 中',
      GitRepositoryState.bisect => 'Bisect 中',
      GitRepositoryState.rebase => 'Rebase 中',
      GitRepositoryState.rebaseInteractive => '交互式 Rebase 中',
      GitRepositoryState.rebaseMerge => 'Rebase 合并中',
      GitRepositoryState.applyMailbox => '应用邮箱补丁中',
      GitRepositoryState.applyMailboxOrRebase => '应用补丁或 Rebase 中',
    };
  }

  String _enumTail(Object value) {
    return value.toString().split('.').last;
  }

  String _shortSha(String sha) {
    return sha.length <= 7 ? sha : sha.substring(0, 7);
  }

  T? _safe<T>(T Function() action) {
    try {
      return action();
    } catch (_) {
      return null;
    }
  }
}
