import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/git/git_models.dart';
import 'package:pyrite_ide/core/services/git/git_provider.dart';
import 'package:pyrite_ide/core/services/git/git_repository_service.dart';

void main() {
  test('GitNotifier.deleteBranch 委托服务并携带远端删除选项', () async {
    final fake = _RecordingGitRepositoryService();
    final container = ProviderContainer(
      overrides: [gitRepositoryServiceProvider.overrideWithValue(fake)],
    );

    try {
      container.read(gitProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      // 先建立 workspacePath/snapshot，否则 _rootPath() 找不到仓库根。
      await container
          .read(gitProvider.notifier)
          .refresh(workspacePath: Directory.systemTemp.path);

      await container
          .read(gitProvider.notifier)
          .deleteBranch(_branch('main'), includeRemote: true, force: true);

      expect(fake.deletedBranches, hasLength(1));
      final deleted = fake.deletedBranches.single;
      expect(deleted.name, 'main');
      expect(deleted.force, isTrue);
      // 说明：deleteBranch 收到的 includeRemote 来自 inspect 结果；
      // provider 在 includeRemote && hasRemote 时才追加远端删除。
      expect(fake.deletedRemoteBranches, [(remote: 'origin', branch: 'main')]);
      expect(container.read(gitProvider).lastMessage, contains('已删除'));
    } finally {
      container.dispose();
    }
  });

  test('GitNotifier.deleteBranch 对远端分支走远端删除', () async {
    final fake = _RecordingGitRepositoryService();
    final container = ProviderContainer(
      overrides: [gitRepositoryServiceProvider.overrideWithValue(fake)],
    );

    try {
      container.read(gitProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      // 先建立 workspacePath/snapshot，否则 _rootPath() 找不到仓库根。
      await container
          .read(gitProvider.notifier)
          .refresh(workspacePath: Directory.systemTemp.path);

      await container
          .read(gitProvider.notifier)
          .deleteBranch(_branch('origin/feature', remote: true));

      expect(fake.deletedRemoteBranches, [
        (remote: 'origin', branch: 'feature'),
      ]);
      expect(fake.deletedBranches, isEmpty);
    } finally {
      container.dispose();
    }
  });

  test('GitNotifier.renameBranch 刷新 snapshot', () async {
    final fake = _RecordingGitRepositoryService();
    final container = ProviderContainer(
      overrides: [gitRepositoryServiceProvider.overrideWithValue(fake)],
    );

    try {
      container.read(gitProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      // 先建立 workspacePath/snapshot，否则 _rootPath() 找不到仓库根。
      await container
          .read(gitProvider.notifier)
          .refresh(workspacePath: Directory.systemTemp.path);

      await container
          .read(gitProvider.notifier)
          .renameBranch(_branch('old'), 'new');

      expect(fake.renamedBranches, [(old: 'old', newName: 'new')]);
      // 重命名后必须刷新 snapshot，否则 UI 仍显示旧名字。
      expect(fake.loadSnapshotCalls, greaterThanOrEqualTo(1));
    } finally {
      container.dispose();
    }
  });

  test('GitNotifier remote 编辑/重命名/删除都刷新 snapshot', () async {
    final fake = _RecordingGitRepositoryService();
    final container = ProviderContainer(
      overrides: [gitRepositoryServiceProvider.overrideWithValue(fake)],
    );

    try {
      container.read(gitProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      // 先建立 workspacePath/snapshot，否则 _rootPath() 找不到仓库根。
      await container
          .read(gitProvider.notifier)
          .refresh(workspacePath: Directory.systemTemp.path);
      final notifier = container.read(gitProvider.notifier);

      await notifier.setRemoteUrl('origin', 'https://example.test/x.git');
      await notifier.renameRemote('origin', 'upstream');
      await notifier.deleteRemote('upstream');

      expect(fake.remoteCalls, [
        'url:origin:https://example.test/x.git',
        'rename:origin:upstream',
        'delete:upstream',
      ]);
      expect(fake.loadSnapshotCalls, greaterThanOrEqualTo(3));
    } finally {
      container.dispose();
    }
  });

  test('GitNotifier.createTag 传 message 时创建 annotated', () async {
    final fake = _RecordingGitRepositoryService();
    final container = ProviderContainer(
      overrides: [gitRepositoryServiceProvider.overrideWithValue(fake)],
    );

    try {
      container.read(gitProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      // 先建立 workspacePath/snapshot，否则 _rootPath() 找不到仓库根。
      await container
          .read(gitProvider.notifier)
          .refresh(workspacePath: Directory.systemTemp.path);
      final notifier = container.read(gitProvider.notifier);

      await notifier.createTag('v1.0');
      await notifier.createTag('v1.1', message: 'Release');

      expect(fake.tagCalls, [
        (name: 'v1.0', message: ''),
        (name: 'v1.1', message: 'Release'),
      ]);
      expect(container.read(gitProvider).lastMessage, contains('annotated'));
    } finally {
      container.dispose();
    }
  });

  test('GitNotifier.deleteTag 透传远端名', () async {
    final fake = _RecordingGitRepositoryService();
    final container = ProviderContainer(
      overrides: [gitRepositoryServiceProvider.overrideWithValue(fake)],
    );

    try {
      container.read(gitProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      // 先建立 workspacePath/snapshot，否则 _rootPath() 找不到仓库根。
      await container
          .read(gitProvider.notifier)
          .refresh(workspacePath: Directory.systemTemp.path);
      final notifier = container.read(gitProvider.notifier);

      await notifier.deleteTag('v1.0');
      await notifier.deleteTag('v1.1', remoteName: 'origin');

      expect(fake.deletedTags, [
        (name: 'v1.0', remote: null),
        (name: 'v1.1', remote: 'origin'),
      ]);
    } finally {
      container.dispose();
    }
  });

  test('GitNotifier.showBlame 写入 blame 与 blamePath', () async {
    final tempDir = Directory.systemTemp.createTempSync('pyrite_blame_ui_');
    final fake = _RecordingGitRepositoryService();
    final container = ProviderContainer(
      overrides: [gitRepositoryServiceProvider.overrideWithValue(fake)],
    );

    try {
      container.read(gitProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      // 先建立 workspacePath/snapshot，否则 _rootPath() 找不到仓库根。
      await container
          .read(gitProvider.notifier)
          .refresh(workspacePath: Directory.systemTemp.path);

      await container.read(gitProvider.notifier).showBlame('README.md');

      final state = container.read(gitProvider);
      expect(state.blamePath, 'README.md');
      expect(state.blame.single.author, 'Pyrite Test');
      expect(fake.blameCalls, ['README.md']);
    } finally {
      container.dispose();
      tempDir.deleteSync(recursive: true);
    }
  });

  test('GitNotifier.clearBlame 清空 blame 与路径', () async {
    final fake = _RecordingGitRepositoryService();
    final container = ProviderContainer(
      overrides: [gitRepositoryServiceProvider.overrideWithValue(fake)],
    );

    try {
      container.read(gitProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      // 先建立 workspacePath/snapshot，否则 _rootPath() 找不到仓库根。
      await container
          .read(gitProvider.notifier)
          .refresh(workspacePath: Directory.systemTemp.path);
      final notifier = container.read(gitProvider.notifier);

      await notifier.showBlame('README.md');
      notifier.clearBlame();

      final state = container.read(gitProvider);
      expect(state.blame, isEmpty);
      expect(state.blamePath, isNull);
    } finally {
      container.dispose();
    }
  });

  test('GitNotifier.inspectBranchDeletionTarget 透传服务结果', () async {
    final fake = _RecordingGitRepositoryService();
    final container = ProviderContainer(
      overrides: [gitRepositoryServiceProvider.overrideWithValue(fake)],
    );

    try {
      container.read(gitProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      // 先建立 workspacePath/snapshot，否则 _rootPath() 找不到仓库根。
      await container
          .read(gitProvider.notifier)
          .refresh(workspacePath: Directory.systemTemp.path);

      final target = await container
          .read(gitProvider.notifier)
          .inspectBranchDeletionTarget('main');

      expect(target, isNotNull);
      expect(target!.hasRemote, isTrue);
      expect(target.remoteName, 'origin');
    } finally {
      container.dispose();
    }
  });

  test('GitNotifier 在 busy 期间挂起刷新，空闲后补一次', () async {
    final fake = _BlockingGitRepositoryService();
    final tempDir = Directory.systemTemp.createTempSync('pyrite_pending_');
    final container = ProviderContainer(
      overrides: [gitRepositoryServiceProvider.overrideWithValue(fake)],
    );

    try {
      container.read(gitProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      // 先建立 workspacePath/snapshot，否则 _rootPath() 找不到仓库根。
      await container
          .read(gitProvider.notifier)
          .refresh(workspacePath: Directory.systemTemp.path);

      final first = container
          .read(gitProvider.notifier)
          .refresh(workspacePath: tempDir.path);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(gitProvider).isBusy, isTrue);
      expect(fake.loadCalls, 1);

      await container
          .read(gitProvider.notifier)
          .refresh(workspacePath: tempDir.path);
      await container
          .read(gitProvider.notifier)
          .refresh(workspacePath: tempDir.path);
      // busy 期间不再发起新请求。
      expect(fake.loadCalls, 1);

      fake.releaseAll();
      await first;
      // 补刷新是异步的，等它真正跑完再断言。
      await _pumpUntil(() => !container.read(gitProvider).isBusy);

      // 两次挂起合并为一次补刷新。
      expect(fake.loadCalls, 2);
      expect(container.read(gitProvider).isBusy, isFalse);
    } finally {
      container.dispose();
      tempDir.deleteSync(recursive: true);
    }
  });
}

/// 轮询等待条件成立，避免依赖固定 sleep 的时序抖动。
Future<void> _pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 100; i += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

GitBranchInfo _branch(String name, {bool remote = false}) {
  return GitBranchInfo(
    name: name,
    targetSha: '0123456789abcdef',
    isCurrent: false,
    isRemote: remote,
    upstream: '',
  );
}

GitRepositorySnapshot _snapshot(String rootPath) {
  return GitRepositorySnapshot(
    rootPath: rootPath,
    gitDir: p.join(rootPath, '.git'),
    branchLabel: 'main',
    stateLabel: '空闲',
    isDetached: false,
    isEmpty: false,
    authorName: 'Pyrite Test',
    authorEmail: 'pyrite-test@example.local',
    ahead: 0,
    behind: 0,
    statusEntries: const [],
    branches: const [],
    remotes: const [],
    stashes: const [],
    tags: const [],
    submodules: const [],
    worktrees: const [],
    commits: const [],
    conflicts: const [],
    stagedPatch: '',
    unstagedPatch: '',
  );
}

/// 记录调用的 fake：只关心 provider 是否正确编排服务调用。
class _RecordingGitRepositoryService extends GitRepositoryService {
  var loadSnapshotCalls = 0;
  final deletedBranches = <({String name, bool force, bool includeRemote})>[];
  final deletedRemoteBranches = <({String remote, String branch})>[];
  final renamedBranches = <({String old, String newName})>[];
  final remoteCalls = <String>[];
  final tagCalls = <({String name, String message})>[];
  final deletedTags = <({String name, String? remote})>[];
  final blameCalls = <String>[];

  @override
  Future<GitRepositorySnapshot?> loadSnapshot(String? workspacePath) async {
    loadSnapshotCalls += 1;
    if (workspacePath == null) return null;
    return _snapshot(workspacePath);
  }

  @override
  Future<String?> discoverRoot(String? workspacePath) async => workspacePath;

  @override
  Future<GitBranchDeletionTarget> inspectBranchDeletionTarget(
    String rootPath,
    String name,
  ) async {
    return GitBranchDeletionTarget(
      name: name,
      hasLocal: true,
      hasRemote: true,
      remoteName: 'origin',
      isCurrent: true,
    );
  }

  @override
  Future<void> deleteBranch(
    String rootPath,
    String name, {
    bool force = false,
  }) async {
    deletedBranches.add((name: name, force: force, includeRemote: false));
  }

  @override
  Future<String> deleteRemoteBranch(
    String rootPath,
    String remoteName,
    String branchName,
    GitCredentialDraft draft,
  ) async {
    deletedRemoteBranches.add((remote: remoteName, branch: branchName));
    return '已删除远端分支 $remoteName/$branchName';
  }

  @override
  Future<void> renameBranch(
    String rootPath,
    String oldName,
    String newName, {
    bool force = false,
  }) async {
    renamedBranches.add((old: oldName, newName: newName));
  }

  @override
  Future<void> setRemoteUrl(String rootPath, String name, String url) async {
    remoteCalls.add('url:$name:$url');
  }

  @override
  Future<List<String>> renameRemote(
    String rootPath,
    String oldName,
    String newName,
  ) async {
    remoteCalls.add('rename:$oldName:$newName');
    return const [];
  }

  @override
  Future<void> deleteRemote(String rootPath, String name) async {
    remoteCalls.add('delete:$name');
  }

  @override
  Future<void> createTag(
    String rootPath,
    String name, {
    String? targetSpec,
    String? message,
  }) async {
    tagCalls.add((name: name, message: message ?? ''));
  }

  @override
  Future<String> deleteTag(
    String rootPath,
    String name, {
    String? remoteName,
    GitCredentialDraft draft = const GitCredentialDraft(),
  }) async {
    deletedTags.add((name: name, remote: remoteName));
    return '已删除标签 $name';
  }

  @override
  Future<List<GitBlameLine>> blame(String rootPath, String filePath) async {
    blameCalls.add(filePath);
    return const [
      GitBlameLine(
        lineStart: 1,
        lineCount: 1,
        commitSha: '0123456789abcdef',
        author: 'Pyrite Test',
        email: 'pyrite-test@example.local',
        time: null,
      ),
    ];
  }
}

/// loadSnapshot 只在 [hold] 为 true 时阻塞，用来制造一次 busy 状态。
///
/// 注意不能“永远阻塞”：补刷新会再调一次 loadSnapshot，若也阻塞，isBusy
/// 永远不会回落，测试就测不出“补一次”这个行为。
class _BlockingGitRepositoryService extends GitRepositoryService {
  final _pending = <Completer<GitRepositorySnapshot?>>[];
  var loadCalls = 0;

  /// 为 true 时下一次 loadSnapshot 挂起，直到 [releaseAll]。
  bool hold = true;

  void releaseAll() {
    hold = false;
    while (_pending.isNotEmpty) {
      _pending.removeAt(0).complete(null);
    }
  }

  @override
  Future<GitRepositorySnapshot?> loadSnapshot(String? workspacePath) async {
    loadCalls += 1;
    if (!hold) return null;
    final completer = Completer<GitRepositorySnapshot?>();
    _pending.add(completer);
    return completer.future;
  }

  @override
  Future<String?> discoverRoot(String? workspacePath) async => workspacePath;
}
