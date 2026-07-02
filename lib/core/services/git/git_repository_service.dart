import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  GitRepositoryService({this.commandTimeout = const Duration(seconds: 20)});

  final Duration commandTimeout;

  Future<GitRepositorySnapshot?> loadSnapshot(String? workspacePath) async {
    final rootPath = await discoverRoot(workspacePath);
    if (rootPath == null) return null;

    final gitDir = await _gitOutput(rootPath, [
      'rev-parse',
      '--git-dir',
    ], allowFailure: true);
    final branchLabel = await _branchLabel(rootPath);
    final statusEntries = await _statusEntries(rootPath);
    final conflicts = await _conflicts(rootPath, statusEntries);
    final defaultAuthor = await _configValue(rootPath, 'user.name');
    final defaultEmail = await _configValue(rootPath, 'user.email');
    final aheadBehind = await _aheadBehind(rootPath);
    final unstagedPatch = await _unstagedPatch(rootPath, statusEntries);

    return GitRepositorySnapshot(
      rootPath: rootPath,
      gitDir: _normalizeGitDir(rootPath, gitDir),
      branchLabel: branchLabel,
      stateLabel: await _repositoryStateLabel(rootPath),
      isDetached: await _isDetached(rootPath),
      isEmpty: await _isEmpty(rootPath),
      authorName: defaultAuthor ?? 'Pyrite User',
      authorEmail: defaultEmail ?? 'pyrite@example.local',
      ahead: aheadBehind.$1,
      behind: aheadBehind.$2,
      statusEntries: statusEntries,
      branches: await _branches(rootPath),
      remotes: await _remotes(rootPath),
      stashes: await _stashes(rootPath),
      tags: await _tags(rootPath),
      submodules: await _submodules(rootPath),
      worktrees: await _worktrees(rootPath),
      commits: await _commits(rootPath),
      conflicts: conflicts,
      stagedPatch: await _gitOutput(rootPath, [
        'diff',
        '--cached',
        '--no-ext-diff',
      ], allowFailure: true),
      unstagedPatch: unstagedPatch,
    );
  }

  Future<String?> discoverRoot(String? workspacePath) async {
    if (workspacePath == null || workspacePath.isEmpty) return null;

    final startPath = Directory(workspacePath).existsSync()
        ? workspacePath
        : p.dirname(workspacePath);
    final result = await _runGit(
      null,
      ['-C', startPath, 'rev-parse', '--show-toplevel'],
      allowFailure: true,
      timeout: const Duration(seconds: 5),
    );
    if (result.exitCode != 0) return null;

    final root = result.stdout.trim();
    return root.isEmpty ? null : p.normalize(root);
  }

  Future<void> initRepository(String workspacePath) async {
    final path = workspacePath.trim();
    if (path.isEmpty) throw ArgumentError('工作区路径不能为空。');
    if (!Directory(path).existsSync()) {
      throw ArgumentError('工作区文件夹不存在：$path');
    }

    await _runGit(null, [
      '-C',
      path,
      'init',
    ], timeout: const Duration(seconds: 20));
  }

  Future<String> diffForPath(
    String rootPath,
    String filePath, {
    bool staged = false,
  }) {
    return _gitOutput(rootPath, [
      'diff',
      if (staged) '--cached',
      '--no-ext-diff',
      '--',
      filePath,
    ], allowFailure: true);
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
    return _commits(rootPath, limit: 200, pathspec: filePath, follow: true);
  }

  Future<List<GitBlameLine>> blame(String rootPath, String filePath) async {
    final output = await _gitOutput(rootPath, [
      'blame',
      '--line-porcelain',
      '--',
      filePath,
    ], allowFailure: true);
    final lines = output.split('\n');
    final blameLines = <GitBlameLine>[];
    var lineStart = 0;
    var lineCount = 1;
    var sha = '';
    var author = '';
    var email = '';
    DateTime? time;

    for (final line in lines) {
      final headerMatch = RegExp(
        r'^([0-9a-f]{40}) \d+ (\d+)(?: (\d+))?$',
      ).firstMatch(line);
      if (headerMatch != null) {
        sha = headerMatch.group(1)!;
        lineStart = int.parse(headerMatch.group(2)!);
        lineCount = int.tryParse(headerMatch.group(3) ?? '') ?? 1;
      } else if (line.startsWith('author ')) {
        author = line.substring('author '.length);
      } else if (line.startsWith('author-mail ')) {
        email = line.substring('author-mail '.length).replaceAll('<', '');
        email = email.replaceAll('>', '');
      } else if (line.startsWith('author-time ')) {
        final seconds = int.tryParse(line.substring('author-time '.length));
        time = seconds == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                seconds * 1000,
                isUtc: true,
              ).toLocal();
      } else if (line.startsWith('\t')) {
        blameLines.add(
          GitBlameLine(
            lineStart: lineStart,
            lineCount: lineCount,
            commitSha: sha,
            author: author,
            email: email,
            time: time,
          ),
        );
      }
    }
    return blameLines;
  }

  Future<void> stage(String rootPath, Iterable<String> paths) {
    return _gitVoid(rootPath, ['add', '--', ...paths]);
  }

  Future<void> unstage(String rootPath, Iterable<String> paths) {
    return _gitVoid(rootPath, ['restore', '--staged', '--', ...paths]);
  }

  Future<void> discardChanges(String rootPath, GitStatusEntry entry) {
    if (entry.isUntracked) {
      return _gitVoid(rootPath, ['clean', '-f', '--', entry.path]);
    }
    return _gitVoid(rootPath, ['restore', '--', entry.path]);
  }

  Future<void> commit(String rootPath, GitCommitInput input) async {
    if ((await _conflictedPaths(rootPath)).isNotEmpty) {
      throw StateError('仍有冲突未解决，不能提交。');
    }
    final message = input.message.trim();
    if (message.isEmpty) {
      throw ArgumentError('提交信息不能为空。');
    }

    final tempDir = await Directory.systemTemp.createTemp('pyrite_git_commit_');
    final messageFile = File(p.join(tempDir.path, 'message.txt'));
    try {
      await messageFile.writeAsString(message, encoding: utf8);
      await _gitVoid(rootPath, [
        '-c',
        'user.name=${_authorName(input)}',
        '-c',
        'user.email=${_authorEmail(input)}',
        '-c',
        'i18n.commitEncoding=UTF-8',
        'commit',
        '-F',
        messageFile.path,
      ]);
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<void> createBranch(String rootPath, String name) async {
    final branchName = name.trim();
    if (branchName.isEmpty) throw ArgumentError('分支名称不能为空。');
    await _gitVoid(rootPath, ['branch', branchName]);
  }

  Future<void> checkoutBranch(
    String rootPath,
    String name, {
    bool remote = false,
  }) async {
    final branchName = name.trim();
    if (branchName.isEmpty) throw ArgumentError('分支名称不能为空。');

    if (!remote) {
      await _gitVoid(rootPath, ['switch', branchName]);
      return;
    }

    if (branchName.contains(' -> ') || branchName.endsWith('/HEAD')) {
      throw ArgumentError('不能切换到远端 HEAD 指针。');
    }

    final localName = _localBranchNameForRemote(branchName);
    final localBranchNames = (await _branchInfos(
      rootPath,
      remote: false,
    )).map((branch) => branch.name).toSet();
    if (localBranchNames.contains(localName)) {
      await _gitVoid(rootPath, ['switch', localName]);
      return;
    }

    await _gitVoid(rootPath, ['switch', '--track', branchName]);
  }

  Future<void> stash(
    String rootPath,
    GitCommitInput input, {
    bool includeUntracked = true,
  }) {
    final message = input.message.trim().isEmpty ? 'WIP' : input.message.trim();
    return _gitVoid(rootPath, [
      'stash',
      'push',
      if (includeUntracked) '--include-untracked',
      '-m',
      message,
    ]);
  }

  Future<void> applyStash(String rootPath, int index, {bool pop = false}) {
    return _gitVoid(rootPath, [
      'stash',
      pop ? 'pop' : 'apply',
      'stash@{$index}',
    ]);
  }

  Future<void> dropStash(String rootPath, int index) {
    return _gitVoid(rootPath, ['stash', 'drop', 'stash@{$index}']);
  }

  Future<String> fetch(
    String rootPath,
    String remoteName,
    GitCredentialDraft draft,
  ) async {
    await _gitVoid(
      rootPath,
      ['fetch', remoteName],
      environment: _credentialEnvironment(draft),
      timeout: const Duration(minutes: 2),
    );
    return '已从 $remoteName 获取更新';
  }

  Future<String> push(
    String rootPath,
    String remoteName,
    GitCredentialDraft draft,
  ) async {
    final branch = await _currentBranch(rootPath);
    if (branch == null) {
      throw StateError('当前不是可推送的本地分支。');
    }
    await _gitVoid(
      rootPath,
      ['push', remoteName, branch],
      environment: _credentialEnvironment(draft),
      timeout: const Duration(minutes: 2),
    );
    return '已推送 $branch 到 $remoteName';
  }

  Future<String> pull(
    String rootPath,
    String remoteName,
    GitCredentialDraft draft,
  ) async {
    final branch = await _currentBranch(rootPath);
    if (branch == null) {
      throw StateError('当前 HEAD 分离，不能自动 pull。');
    }
    await _gitVoid(
      rootPath,
      ['pull', remoteName, branch],
      environment: _credentialEnvironment(draft),
      timeout: const Duration(minutes: 2),
    );
    return '已从 $remoteName 拉取并合并到 $branch';
  }

  Future<void> addRemote(String rootPath, String name, String url) {
    final remoteName = name.trim();
    final remoteUrl = url.trim();
    if (remoteName.isEmpty) throw ArgumentError('远端名称不能为空。');
    if (remoteUrl.isEmpty) throw ArgumentError('远端 URL 不能为空。');
    return _gitVoid(rootPath, ['remote', 'add', remoteName, remoteUrl]);
  }

  Future<void> merge(String rootPath, String targetSpec) {
    return _runConflictAware(rootPath, ['merge', targetSpec]);
  }

  Future<void> rebase(
    String rootPath,
    String targetSpec,
    GitCommitInput input,
  ) {
    return _runConflictAware(rootPath, [
      '-c',
      'user.name=${_authorName(input)}',
      '-c',
      'user.email=${_authorEmail(input)}',
      'rebase',
      targetSpec,
    ]);
  }

  Future<void> continueRebase(String rootPath, GitCommitInput input) {
    return _gitVoid(
      rootPath,
      [
        '-c',
        'user.name=${_authorName(input)}',
        '-c',
        'user.email=${_authorEmail(input)}',
        'rebase',
        '--continue',
      ],
      environment: {'GIT_EDITOR': 'true'},
    );
  }

  Future<void> abortRebase(String rootPath) {
    return _gitVoid(rootPath, ['rebase', '--abort']);
  }

  Future<void> cherryPick(String rootPath, String targetSpec) {
    return _runConflictAware(rootPath, ['cherry-pick', targetSpec]);
  }

  Future<void> markResolved(String rootPath, String filePath) {
    return stage(rootPath, [filePath]);
  }

  Future<void> acceptConflictSide(
    String rootPath,
    String filePath,
    GitConflictSide side,
  ) async {
    await _gitVoid(rootPath, [
      'checkout',
      side == GitConflictSide.ours ? '--ours' : '--theirs',
      filePath,
    ]);
    await markResolved(rootPath, filePath);
  }

  Future<void> createTag(String rootPath, String name, {String? targetSpec}) {
    final tagName = name.trim();
    if (tagName.isEmpty) throw ArgumentError('标签名称不能为空。');
    return _gitVoid(rootPath, [
      'tag',
      tagName,
      if (targetSpec?.trim().isNotEmpty == true) targetSpec!,
    ]);
  }

  Future<void> createWorktree(String rootPath, String name, String path) {
    return _gitVoid(rootPath, ['worktree', 'add', path.trim(), name.trim()]);
  }

  Future<void> pruneWorktree(String rootPath, String name) async {
    final result = await _git(rootPath, [
      'worktree',
      'remove',
      '--force',
      name,
    ], allowFailure: true);
    if (result.exitCode != 0) {
      await _gitVoid(rootPath, ['worktree', 'prune']);
    }
  }

  Future<void> updateSubmodule(
    String rootPath,
    String name,
    GitCredentialDraft draft,
  ) {
    return _gitVoid(
      rootPath,
      ['submodule', 'update', '--init', '--recursive', name],
      environment: _credentialEnvironment(draft),
      timeout: const Duration(minutes: 2),
    );
  }

  Future<void> writeCommitGraph(String rootPath) {
    return _gitVoid(rootPath, ['commit-graph', 'write', '--reachable']);
  }

  Future<String> _branchLabel(String rootPath) async {
    final branch = await _currentBranch(rootPath);
    if (branch != null) return branch;

    final sha = await _gitOutput(rootPath, [
      'rev-parse',
      '--short',
      'HEAD',
    ], allowFailure: true);
    return sha.isEmpty ? '未提交仓库' : 'HEAD@$sha';
  }

  Future<String?> _currentBranch(String rootPath) async {
    final branch = await _gitOutput(rootPath, [
      'symbolic-ref',
      '--quiet',
      '--short',
      'HEAD',
    ], allowFailure: true);
    return branch.isEmpty ? null : branch;
  }

  Future<bool> _isDetached(String rootPath) async {
    return await _currentBranch(rootPath) == null && !await _isEmpty(rootPath);
  }

  Future<bool> _isEmpty(String rootPath) async {
    final result = await _git(rootPath, [
      'rev-parse',
      '--verify',
      'HEAD',
    ], allowFailure: true);
    return result.exitCode != 0;
  }

  Future<(int, int)> _aheadBehind(String rootPath) async {
    final output = await _gitOutput(rootPath, [
      'rev-list',
      '--left-right',
      '--count',
      '@{upstream}...HEAD',
    ], allowFailure: true);
    final values = output.split(RegExp(r'\s+'));
    if (values.length < 2) return (0, 0);
    final behind = int.tryParse(values[0]) ?? 0;
    final ahead = int.tryParse(values[1]) ?? 0;
    return (ahead, behind);
  }

  Future<String> _unstagedPatch(
    String rootPath,
    List<GitStatusEntry> entries,
  ) async {
    final parts = <String>[
      await _gitOutput(rootPath, ['diff', '--no-ext-diff'], allowFailure: true),
    ];
    for (final entry in entries) {
      if (!entry.isUntracked) continue;
      final patch = await _untrackedFilePatch(rootPath, entry.path);
      if (patch.isNotEmpty) parts.add(patch);
    }
    return parts.where((part) => part.isNotEmpty).join('\n');
  }

  Future<String> _untrackedFilePatch(String rootPath, String filePath) async {
    final file = File(p.join(rootPath, filePath));
    if (!await file.exists()) return '';

    final header = StringBuffer()
      ..writeln('diff --git a/$filePath b/$filePath')
      ..writeln('new file mode 100644')
      ..writeln('index 0000000..0000000')
      ..writeln('--- /dev/null')
      ..writeln('+++ b/$filePath');
    final bytes = await file.readAsBytes();
    if (bytes.contains(0)) {
      header.writeln('Binary files /dev/null and b/$filePath differ');
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

  Future<List<GitStatusEntry>> _statusEntries(String rootPath) async {
    final output = await _gitOutput(
      rootPath,
      ['status', '--porcelain=v1', '-z', '--untracked-files=all'],
      allowFailure: true,
      trimOutput: false,
    );
    if (output.isEmpty) return const [];

    final entries = <GitStatusEntry>[];
    final records = output.split('\u0000');
    for (var index = 0; index < records.length; index += 1) {
      final record = records[index];
      if (record.length < 4) continue;

      final indexStatus = record[0];
      final worktreeStatus = record[1];
      var filePath = record.substring(3);
      if ((indexStatus == 'R' || indexStatus == 'C') &&
          index + 1 < records.length) {
        index += 1;
        filePath = records[index];
      }

      final labels = _statusLabels(indexStatus, worktreeStatus);
      entries.add(
        GitStatusEntry(
          path: filePath,
          labels: labels,
          isStaged: _isIndexStatus(indexStatus),
          isUnstaged: _isWorktreeStatus(worktreeStatus),
          isConflicted: _isConflictStatus(indexStatus, worktreeStatus),
          isUntracked: indexStatus == '?' && worktreeStatus == '?',
        ),
      );
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  List<String> _statusLabels(String indexStatus, String worktreeStatus) {
    if (_isConflictStatus(indexStatus, worktreeStatus)) return const ['冲突'];

    return [
      if (_indexStatusLabel(indexStatus) != null)
        _indexStatusLabel(indexStatus)!,
      if (_worktreeStatusLabel(worktreeStatus) != null)
        _worktreeStatusLabel(worktreeStatus)!,
    ];
  }

  String? _indexStatusLabel(String status) {
    return switch (status) {
      'A' => '已暂存新增',
      'M' => '已暂存修改',
      'D' => '已暂存删除',
      'R' => '已暂存重命名',
      'C' => '已暂存复制',
      _ => null,
    };
  }

  String? _worktreeStatusLabel(String status) {
    return switch (status) {
      '?' => '未跟踪',
      'M' => '工作区修改',
      'D' => '工作区删除',
      'R' => '工作区重命名',
      'C' => '工作区复制',
      '!' => '已忽略',
      _ => null,
    };
  }

  bool _isIndexStatus(String status) {
    return const {'A', 'M', 'D', 'R', 'C'}.contains(status);
  }

  bool _isWorktreeStatus(String status) {
    return const {'?', 'M', 'D', 'R', 'C'}.contains(status);
  }

  bool _isConflictStatus(String indexStatus, String worktreeStatus) {
    return const {
      'DD',
      'AU',
      'UD',
      'UA',
      'DU',
      'AA',
      'UU',
    }.contains('$indexStatus$worktreeStatus');
  }

  Future<List<GitBranchInfo>> _branches(String rootPath) async {
    final local = await _branchInfos(rootPath, remote: false);
    final remote = await _branchInfos(rootPath, remote: true);
    return [...local, ...remote];
  }

  Future<List<GitBranchInfo>> _branchInfos(
    String rootPath, {
    required bool remote,
  }) async {
    final output = await _gitOutput(rootPath, [
      'branch',
      remote ? '--remotes' : '--list',
      '--format=%(HEAD)%00%(refname:short)%00%(objectname)%00%(upstream:short)',
    ], allowFailure: true);
    return [
      for (final line in _lines(output))
        if (_branchInfo(line, remote) != null) _branchInfo(line, remote)!,
    ];
  }

  GitBranchInfo? _branchInfo(String line, bool isRemote) {
    final parts = line.split('\u0000');
    if (parts.length < 3 || parts[1].isEmpty) return null;
    if (isRemote && (parts[1].contains(' -> ') || parts[1].endsWith('/HEAD'))) {
      return null;
    }
    return GitBranchInfo(
      name: parts[1],
      targetSha: parts[2],
      isCurrent: parts[0] == '*',
      isRemote: isRemote,
      upstream: parts.length > 3 ? parts[3] : '',
    );
  }

  Future<List<GitRemoteInfo>> _remotes(String rootPath) async {
    return [
      for (final name in _lines(
        await _gitOutput(rootPath, ['remote'], allowFailure: true),
      ))
        GitRemoteInfo(
          name: name,
          url: await _gitOutput(rootPath, [
            'remote',
            'get-url',
            name,
          ], allowFailure: true),
          pushUrl: await _gitOutput(rootPath, [
            'remote',
            'get-url',
            '--push',
            name,
          ], allowFailure: true),
          fetchRefspecs: _lines(
            await _gitOutput(rootPath, [
              'config',
              '--get-all',
              'remote.$name.fetch',
            ], allowFailure: true),
          ),
          pushRefspecs: _lines(
            await _gitOutput(rootPath, [
              'config',
              '--get-all',
              'remote.$name.push',
            ], allowFailure: true),
          ),
        ),
    ];
  }

  Future<List<GitStashInfo>> _stashes(String rootPath) async {
    final output = await _gitOutput(rootPath, [
      'stash',
      'list',
      '--format=%gd%x00%H%x00%s',
    ], allowFailure: true);
    return [
      for (final line in _lines(output))
        if (_stashInfo(line) != null) _stashInfo(line)!,
    ];
  }

  GitStashInfo? _stashInfo(String line) {
    final parts = line.split('\u0000');
    if (parts.length < 3) return null;
    final match = RegExp(r'stash@\{(\d+)\}').firstMatch(parts[0]);
    return GitStashInfo(
      index: int.tryParse(match?.group(1) ?? '') ?? 0,
      sha: parts[1],
      message: parts[2],
    );
  }

  Future<List<GitTagInfo>> _tags(String rootPath) async {
    final output = await _gitOutput(rootPath, [
      'tag',
      '--format=%(refname:short)%00%(objectname)',
    ], allowFailure: true);
    return [
      for (final line in _lines(output))
        if (_tagInfo(line) != null) _tagInfo(line)!,
    ];
  }

  GitTagInfo? _tagInfo(String line) {
    final parts = line.split('\u0000');
    if (parts.length < 2) return null;
    return GitTagInfo(name: parts[0], targetSha: parts[1]);
  }

  Future<List<GitSubmoduleInfo>> _submodules(String rootPath) async {
    final output = await _gitOutput(rootPath, [
      'config',
      '--file',
      '.gitmodules',
      '--get-regexp',
      r'^submodule\..*\.path$',
    ], allowFailure: true);
    final submodules = <GitSubmoduleInfo>[];
    for (final line in _lines(output)) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final name = parts.first
          .replaceFirst('submodule.', '')
          .replaceFirst('.path', '');
      final path = parts.sublist(1).join(' ');
      submodules.add(
        GitSubmoduleInfo(
          name: name,
          path: path,
          url: await _gitOutput(rootPath, [
            'config',
            '--file',
            '.gitmodules',
            'submodule.$name.url',
          ], allowFailure: true),
          branch: await _gitOutput(rootPath, [
            'config',
            '--file',
            '.gitmodules',
            'submodule.$name.branch',
          ], allowFailure: true),
          statusLabels: _lines(
            await _gitOutput(rootPath, [
              'submodule',
              'status',
              '--',
              path,
            ], allowFailure: true),
          ),
        ),
      );
    }
    return submodules;
  }

  Future<List<GitWorktreeInfo>> _worktrees(String rootPath) async {
    final output = await _gitOutput(rootPath, [
      'worktree',
      'list',
      '--porcelain',
    ], allowFailure: true);
    final worktrees = <GitWorktreeInfo>[];
    var current = <String, String>{};
    for (final line in [..._lines(output), '']) {
      if (line.isEmpty) {
        if (current['worktree'] != null) {
          final path = current['worktree']!;
          if (p.normalize(path) != p.normalize(rootPath)) {
            worktrees.add(
              GitWorktreeInfo(
                name: path,
                path: path,
                isLocked: current.containsKey('locked'),
                isPrunable: current.containsKey('prunable'),
                isValid: true,
              ),
            );
          }
        }
        current = {};
        continue;
      }
      final separator = line.indexOf(' ');
      if (separator == -1) {
        current[line] = '';
      } else {
        current[line.substring(0, separator)] = line.substring(separator + 1);
      }
    }
    return worktrees;
  }

  Future<List<GitCommitInfo>> _commits(
    String rootPath, {
    int limit = 80,
    String? pathspec,
    bool follow = false,
  }) async {
    final output = await _gitOutput(rootPath, [
      'log',
      '-n',
      '$limit',
      '--topo-order',
      '--date=iso-strict',
      '--format=%H%x00%h%x00%s%x00%an%x00%ae%x00%aI%x00%P',
      if (follow) '--follow',
      if (pathspec != null) ...['--', pathspec],
    ], allowFailure: true);
    return [
      for (final line in _lines(output))
        if (_commitInfo(line) != null) _commitInfo(line)!,
    ];
  }

  GitCommitInfo? _commitInfo(String line) {
    final parts = line.split('\u0000');
    if (parts.length < 7) return null;
    return GitCommitInfo(
      sha: parts[0],
      shortSha: parts[1],
      summary: parts[2],
      author: parts[3],
      email: parts[4],
      time: DateTime.tryParse(parts[5])?.toLocal() ?? DateTime.now(),
      parentShas: parts[6].isEmpty ? const [] : parts[6].split(' '),
    );
  }

  String _localBranchNameForRemote(String remoteBranchName) {
    final separator = remoteBranchName.indexOf('/');
    if (separator == -1 || separator == remoteBranchName.length - 1) {
      return remoteBranchName;
    }
    return remoteBranchName.substring(separator + 1);
  }

  Future<List<GitConflictInfo>> _conflicts(
    String rootPath,
    List<GitStatusEntry> entries,
  ) async {
    return [
      for (final entry in entries)
        if (entry.isConflicted)
          GitConflictInfo(
            path: entry.path,
            ancestorPath: entry.path,
            oursPath: entry.path,
            theirsPath: entry.path,
            basePreview: await _showStage(rootPath, 1, entry.path),
            oursPreview: await _showStage(rootPath, 2, entry.path),
            theirsPreview: await _showStage(rootPath, 3, entry.path),
            mergedPreview: await _filePreview(rootPath, entry.path),
          ),
    ];
  }

  Future<String> _showStage(String rootPath, int stage, String filePath) {
    return _gitOutput(rootPath, [
      'show',
      ':$stage:$filePath',
    ], allowFailure: true);
  }

  Future<String> _filePreview(String rootPath, String filePath) async {
    final file = File(p.join(rootPath, filePath));
    if (!file.existsSync()) return '';
    try {
      return await file.readAsString();
    } on FormatException {
      return '[Binary file]';
    }
  }

  Future<List<String>> _conflictedPaths(String rootPath) async {
    return _lines(
      await _gitOutput(rootPath, [
        'diff',
        '--name-only',
        '--diff-filter=U',
      ], allowFailure: true),
    );
  }

  Future<String> _repositoryStateLabel(String rootPath) async {
    final gitDir = _normalizeGitDir(
      rootPath,
      await _gitOutput(rootPath, [
        'rev-parse',
        '--git-dir',
      ], allowFailure: true),
    );
    if (File(p.join(gitDir, 'MERGE_HEAD')).existsSync()) return '合并中';
    if (File(p.join(gitDir, 'CHERRY_PICK_HEAD')).existsSync()) {
      return 'Cherry-pick 中';
    }
    if (Directory(p.join(gitDir, 'rebase-merge')).existsSync() ||
        Directory(p.join(gitDir, 'rebase-apply')).existsSync()) {
      return 'Rebase 中';
    }
    return '空闲';
  }

  Future<String?> _configValue(String rootPath, String key) async {
    final value = await _gitOutput(rootPath, [
      'config',
      '--get',
      key,
    ], allowFailure: true);
    return value.isEmpty ? null : value;
  }

  String _normalizeGitDir(String rootPath, String gitDir) {
    if (gitDir.isEmpty) return p.join(rootPath, '.git');
    return p.normalize(
      p.isAbsolute(gitDir) ? gitDir : p.join(rootPath, gitDir),
    );
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

  Map<String, String> _credentialEnvironment(GitCredentialDraft draft) {
    final environment = <String, String>{};
    if (draft.mode == GitCredentialMode.sshKey &&
        draft.privateKeyPath.trim().isNotEmpty) {
      environment['GIT_SSH_COMMAND'] =
          'ssh -i "${draft.privateKeyPath.trim()}" -o IdentitiesOnly=yes';
    }
    return environment;
  }

  Future<void> _runConflictAware(String rootPath, List<String> args) async {
    final result = await _git(rootPath, args, allowFailure: true);
    if (result.exitCode == 0) return;
    if ((await _conflictedPaths(rootPath)).isNotEmpty) return;
    throw StateError(result.message);
  }

  Future<void> _gitVoid(
    String rootPath,
    List<String> args, {
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    await _git(rootPath, args, environment: environment, timeout: timeout);
  }

  Future<String> _gitOutput(
    String rootPath,
    List<String> args, {
    bool allowFailure = false,
    bool trimOutput = true,
  }) async {
    final result = await _git(rootPath, args, allowFailure: allowFailure);
    if (allowFailure && result.exitCode != 0) return '';
    return trimOutput ? result.stdout.trim() : result.stdout;
  }

  Future<_GitCommandResult> _git(
    String rootPath,
    List<String> args, {
    bool allowFailure = false,
    Map<String, String>? environment,
    Duration? timeout,
  }) {
    return _runGit(
      rootPath,
      ['-C', rootPath, '-c', 'i18n.logOutputEncoding=UTF-8', ...args],
      allowFailure: allowFailure,
      environment: environment,
      timeout: timeout,
    );
  }

  Future<_GitCommandResult> _runGit(
    String? rootPath,
    List<String> args, {
    bool allowFailure = false,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final mergedEnvironment = {'GIT_TERMINAL_PROMPT': '0', ...?environment};
    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: rootPath,
        environment: mergedEnvironment,
        runInShell: Platform.isWindows,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout ?? commandTimeout);
      final commandResult = _GitCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
      if (!allowFailure && commandResult.exitCode != 0) {
        throw StateError(commandResult.message);
      }
      return commandResult;
    } on ProcessException catch (error) {
      throw StateError('未找到 Git 可执行文件：${error.message}');
    } on TimeoutException {
      throw TimeoutException('Git 命令执行超时。');
    }
  }

  List<String> _lines(String output) {
    return output
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList();
  }
}

class _GitCommandResult {
  const _GitCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  String get message {
    final text = stderr.trim().isEmpty ? stdout.trim() : stderr.trim();
    return text.isEmpty ? 'Git 命令失败，退出码 $exitCode。' : text;
  }
}
