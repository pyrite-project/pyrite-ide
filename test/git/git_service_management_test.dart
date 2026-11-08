import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/git/git_isolate_runner.dart';
import 'package:pyrite_ide/core/services/git/git_models.dart';
import 'package:pyrite_ide/core/services/git/git_repository_service.dart';

void main() {
  group('分支管理', () {
    test('deleteBranch 删除已合并分支并保留当前分支', () async {
      final env = await _TestRepository.create();
      try {
        await env.service.deleteBranch(env.root, 'feature');

        final snapshot = await env.service.loadSnapshot(env.root);
        expect(
          snapshot!.branches.map((branch) => branch.name),
          containsAll(<String>['main']),
        );
        expect(
          snapshot.branches.map((branch) => branch.name),
          isNot(contains('feature')),
        );
      } finally {
        await env.dispose();
      }
    });

    test('deleteBranch 拒绝删除当前分支', () async {
      final env = await _TestRepository.create();
      try {
        await expectLater(
          env.service.deleteBranch(env.root, 'main'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('当前分支'),
            ),
          ),
        );
      } finally {
        await env.dispose();
      }
    });

    test('deleteBranch 未合并分支需要 force', () async {
      final env = await _TestRepository.create();
      try {
        await env.service.createBranch(env.root, 'unmerged');
        await env.service.checkoutBranch(env.root, 'unmerged');
        env.writeFile('unmerged.txt', 'only on branch\n');
        await env.service.stage(env.root, ['unmerged.txt']);
        await env.commit('branch commit');
        await env.service.checkoutBranch(env.root, 'main');

        await expectLater(
          env.service.deleteBranch(env.root, 'unmerged'),
          throwsA(isA<StateError>()),
        );

        await env.service.deleteBranch(env.root, 'unmerged', force: true);
        final snapshot = await env.service.loadSnapshot(env.root);
        expect(
          snapshot!.branches.map((branch) => branch.name),
          isNot(contains('unmerged')),
        );
      } finally {
        await env.dispose();
      }
    });

    test('deleteBranch 对不存在的分支给出可读错误', () async {
      final env = await _TestRepository.create();
      try {
        await expectLater(
          env.service.deleteBranch(env.root, 'ghost'),
          throwsA(
            isA<ArgumentError>().having(
              (error) => '${error.message}',
              'message',
              contains('分支不存在'),
            ),
          ),
        );
      } finally {
        await env.dispose();
      }
    });

    test('renameBranch 重命名普通分支与当前分支', () async {
      final env = await _TestRepository.create();
      try {
        await env.service.renameBranch(env.root, 'feature', 'feature-2');
        var snapshot = await env.service.loadSnapshot(env.root);
        expect(
          snapshot!.branches.map((branch) => branch.name),
          containsAll(<String>['main', 'feature-2']),
        );

        // 当前分支重命名：libgit2 会把 HEAD 迁移到新名字。
        await env.service.renameBranch(env.root, 'main', 'trunk');
        snapshot = await env.service.loadSnapshot(env.root);
        expect(snapshot!.branchLabel, 'trunk');
        expect(
          snapshot.branches.where((branch) => branch.isCurrent).single.name,
          'trunk',
        );
      } finally {
        await env.dispose();
      }
    });

    test('renameBranch 校验新名称与重名', () async {
      final env = await _TestRepository.create();
      try {
        await env.service.renameBranch(env.root, 'feature', 'feature');
        await expectLater(
          env.service.renameBranch(env.root, 'feature', 'main'),
          throwsA(
            anyOf(
              isA<GitRepositoryFailure>(),
              isA<GitRepositoryFailureError>(),
              isA<Error>(),
            ),
          ),
        );
        await expectLater(
          env.service.renameBranch(env.root, 'missing', 'other'),
          throwsA(isA<ArgumentError>()),
        );
      } finally {
        await env.dispose();
      }
    });

    test('本地分支列表带 upstream 与 ahead/behind', () async {
      final env = await _TestRepository.createWithRemote();
      try {
        await env.service.push(env.root, 'origin', const GitCredentialDraft());
        // 推送后本地分支应记录 upstream=origin/main，且 0/0。
        var snapshot = await env.service.loadSnapshot(env.root);
        final main = snapshot!.branches.singleWhere(
          (branch) => !branch.isRemote && branch.name == 'main',
        );
        expect(main.upstream, 'origin/main');
        expect(main.hasUpstream, isTrue);
        expect(main.ahead, 0);
        expect(main.behind, 0);
        expect(main.trackingLabel, '↑0 ↓0');

        // 本地再提交一次，ahead 应为 1。
        env.writeFile('README.md', 'second\n');
        await env.commit('local commit');
        snapshot = await env.service.loadSnapshot(env.root);
        final updated = snapshot!.branches.singleWhere(
          (branch) => !branch.isRemote && branch.name == 'main',
        );
        expect(updated.ahead, 1);
        expect(updated.behind, 0);
      } finally {
        await env.dispose();
      }
    });

    test('inspectBranchDeletionTarget 报告两侧存在情况', () async {
      final env = await _TestRepository.createWithRemote();
      try {
        await env.service.push(env.root, 'origin', const GitCredentialDraft());
        await env.service.createBranch(env.root, 'local-only');

        final mainTarget = await env.service.inspectBranchDeletionTarget(
          env.root,
          'main',
        );
        expect(mainTarget.name, 'main');
        expect(mainTarget.hasLocal, isTrue);
        expect(mainTarget.hasRemote, isTrue);
        expect(mainTarget.remoteName, 'origin');
        expect(mainTarget.remoteBranchName, 'origin/main');
        expect(mainTarget.isCurrent, isTrue);

        final localOnly = await env.service.inspectBranchDeletionTarget(
          env.root,
          'local-only',
        );
        expect(localOnly.hasLocal, isTrue);
        expect(localOnly.hasRemote, isFalse);
        expect(localOnly.isCurrent, isFalse);
      } finally {
        await env.dispose();
      }
    });

    test('deleteRemoteBranch 删除远端分支并清理 tracking ref', () async {
      final env = await _TestRepository.createWithRemote();
      try {
        // helper 已创建 feature；直接切过去推送到远端即可。
        await env.service.checkoutBranch(env.root, 'feature');
        await env.service.push(env.root, 'origin', const GitCredentialDraft());
        await env.service.checkoutBranch(env.root, 'main');

        var snapshot = await env.service.loadSnapshot(env.root);
        expect(
          snapshot!.branches.map((branch) => branch.name),
          contains('origin/feature'),
        );

        final message = await env.service.deleteRemoteBranch(
          env.root,
          'origin',
          'feature',
          const GitCredentialDraft(),
        );
        expect(message, contains('feature'));

        snapshot = await env.service.loadSnapshot(env.root);
        expect(
          snapshot!.branches.map((branch) => branch.name),
          isNot(contains('origin/feature')),
        );
      } finally {
        await env.dispose();
      }
    });
  });

  group('tag 管理', () {
    test('createTag 无 message 保持 lightweight', () async {
      final env = await _TestRepository.create();
      try {
        await env.service.createTag(env.root, 'v1.0');
        final snapshot = await env.service.loadSnapshot(env.root);
        final tag = snapshot!.tags.singleWhere((item) => item.name == 'v1.0');
        expect(tag.isAnnotated, isFalse);
        expect(tag.message, isEmpty);
      } finally {
        await env.dispose();
      }
    });

    test('createTag 带 message 创建 annotated tag', () async {
      final env = await _TestRepository.create();
      try {
        await env.service.createTag(
          env.root,
          'v1.1',
          message: 'Release 1.1\n\n- notes',
        );
        final snapshot = await env.service.loadSnapshot(env.root);
        final tag = snapshot!.tags.singleWhere((item) => item.name == 'v1.1');
        expect(tag.isAnnotated, isTrue);
        // 只保留首行，避免 tag 列表被多行消息撑开。
        expect(tag.message, 'Release 1.1');
      } finally {
        await env.dispose();
      }
    });

    test('deleteTag 删除本地 tag，同时对 mark 的 legacy tag 生效', () async {
      final env = await _TestRepository.create();
      try {
        await env.service.createTag(env.root, 'legacy');
        expect(
          (await env.service.loadSnapshot(env.root))!.tags.map((t) => t.name),
          contains('legacy'),
        );

        final message = await env.service.deleteTag(env.root, 'legacy');
        expect(message, contains('legacy'));
        expect(
          (await env.service.loadSnapshot(env.root))!.tags.map((t) => t.name),
          isNot(contains('legacy')),
        );
      } finally {
        await env.dispose();
      }
    });

    test('deleteTag 同时删除远端 tag', () async {
      final env = await _TestRepository.createWithRemote();
      try {
        await env.service.createTag(env.root, 'v2.0');
        await env.service.pushTag(
          env.root,
          'origin',
          'v2.0',
          const GitCredentialDraft(),
        );

        final message = await env.service.deleteTag(
          env.root,
          'v2.0',
          remoteName: 'origin',
        );
        expect(message, contains('origin'));
        expect(
          (await env.service.loadSnapshot(env.root))!.tags.map((t) => t.name),
          isNot(contains('v2.0')),
        );
        // 远端 tag 也应被删除。
        expect(await env.remoteTagNames('origin'), isNot(contains('v2.0')));
      } finally {
        await env.dispose();
      }
    });
  });

  group('remote 管理', () {
    test('setRemoteUrl 同时更新 fetch 与 push URL', () async {
      final env = await _TestRepository.createWithRemote();
      try {
        await env.service.setRemoteUrl(
          env.root,
          'origin',
          'https://example.test/repo.git',
        );
        final snapshot = await env.service.loadSnapshot(env.root);
        final remote = snapshot!.remotes.singleWhere(
          (item) => item.name == 'origin',
        );
        expect(remote.url, 'https://example.test/repo.git');
        expect(remote.pushUrl, 'https://example.test/repo.git');
      } finally {
        await env.dispose();
      }
    });

    test('renameRemote 迁移配置与 remote-tracking ref', () async {
      final env = await _TestRepository.createWithRemote();
      try {
        await env.service.push(env.root, 'origin', const GitCredentialDraft());
        final untracked = await env.service.renameRemote(
          env.root,
          'origin',
          'upstream',
        );
        expect(untracked, isEmpty);

        final snapshot = await env.service.loadSnapshot(env.root);
        expect(
          snapshot!.remotes.map((remote) => remote.name),
          contains('upstream'),
        );
        expect(
          snapshot.remotes.map((remote) => remote.name),
          isNot(contains('origin')),
        );
        expect(
          snapshot.branches.map((branch) => branch.name),
          contains('upstream/main'),
        );
      } finally {
        await env.dispose();
      }
    });

    test('deleteRemote 移除远端与 tracking 分支', () async {
      final env = await _TestRepository.createWithRemote();
      try {
        await env.service.push(env.root, 'origin', const GitCredentialDraft());
        await env.service.deleteRemote(env.root, 'origin');

        final snapshot = await env.service.loadSnapshot(env.root);
        expect(snapshot!.remotes, isEmpty);
        expect(snapshot.branches.where((branch) => branch.isRemote), isEmpty);
      } finally {
        await env.dispose();
      }
    });

    test('remote 操作对不存在的名称给出可读错误', () async {
      final env = await _TestRepository.createWithRemote();
      try {
        await expectLater(
          env.service.deleteRemote(env.root, 'ghost'),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          env.service.renameRemote(env.root, 'ghost', 'other'),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          env.service.setRemoteUrl(env.root, 'origin', '   '),
          throwsA(isA<ArgumentError>()),
        );
      } finally {
        await env.dispose();
      }
    });
  });

  group('blame 与超时', () {
    test('expandGitBlameLines 按行展开 hunk 并补齐缺失行', () {
      final hunks = [
        const GitBlameLine(
          lineStart: 1,
          lineCount: 2,
          commitSha: 'aaaaaaaaaaaaaaaa',
          author: 'A',
          email: 'a@example.local',
          time: null,
        ),
        const GitBlameLine(
          lineStart: 4,
          lineCount: 1,
          commitSha: 'bbbbbbbbbbbbbbbb',
          author: 'B',
          email: 'b@example.local',
          time: null,
        ),
      ];

      final lines = expandGitBlameLines(hunks, lineCount: 5);

      expect(lines, hasLength(5));
      expect(lines[0].lineStart, 1);
      expect(lines[0].lineCount, 1);
      expect(lines[0].author, 'A');
      expect(lines[1].author, 'A');
      // 第 3 行没有 blame 信息：保留占位行，序号不能错位。
      expect(lines[2].lineStart, 3);
      expect(lines[2].author, isEmpty);
      expect(lines[3].author, 'B');
      expect(lines[4].author, isEmpty);
    });

    test('GitBlameLine 暴露短 sha 与行区间', () {
      const line = GitBlameLine(
        lineStart: 10,
        lineCount: 3,
        commitSha: '0123456789abcdef',
        author: 'A',
        email: '',
        time: null,
      );
      expect(line.shortSha, '0123456');
      expect(line.lineEnd, 12);
    });

    test('blame 返回可按行渲染的数据', () async {
      final env = await _TestRepository.create();
      try {
        env.writeFile('README.md', 'one\ntwo\nthree\n');
        await env.commit('blame me');
        final blame = await env.service.blame(env.root, 'README.md');
        expect(blame, isNotEmpty);
        expect(blame.first.author, 'Pyrite Test');
        expect(blame.first.commitSha, hasLength(40));
        final expanded = expandGitBlameLines(blame, lineCount: 3);
        expect(expanded, hasLength(3));
        expect(expanded.every((line) => line.commitSha.isNotEmpty), isTrue);
      } finally {
        await env.dispose();
      }
    });

    test('runGitJob 在超时后抛出 TimeoutException', () async {
      // 在 isolate 内忙等：Completer/ReceivePort 不可跨 isolate 发送，不能用
      // “主 isolate 挂起 future”的方式模拟慢任务。
      await expectLater(
        runGitJob<void>(
          () async {
            final stopwatch = Stopwatch()..start();
            while (stopwatch.elapsedMilliseconds < 3000) {
              // busy wait
            }
            return null;
          },
          timeout: const Duration(milliseconds: 80),
          debugLabel: 'timeout test',
          describeError: (error, stack) =>
              GitJobFailure(code: 'other', message: '$error', stack: '$stack'),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('runGitJob 保留自定义异常分类', () async {
      try {
        await runGitJob<void>(
          () async {
            throw const GitCheckoutBlockedException(message: 'm', paths: []);
          },
          timeout: const Duration(seconds: 5),
          describeError: (error, stack) => GitJobFailure(
            code: error is GitCheckoutBlockedException ? 'blocked' : 'other',
            message: '$error',
            stack: '$stack',
          ),
        );
        fail('应当抛出');
      } on GitJobFailureException catch (error) {
        expect(error.failure.code, 'blocked');
      }
    });

    test('构造函数注入的 commandTimeout 会透传给服务', () {
      final service = GitRepositoryService(
        commandTimeout: const Duration(seconds: 3),
      );
      expect(service.commandTimeout, const Duration(seconds: 3));
    });
  });
}

/// 建仓辅助：统一走真实 service，保证测试覆盖真实 libgit2 行为。
class _TestRepository {
  _TestRepository._(this.root, this.service, this._tempDir);

  final String root;
  final GitRepositoryService service;
  final Directory _tempDir;

  static Future<_TestRepository> create() async {
    final tempDir = Directory.systemTemp.createTempSync(
      'pyrite_git_management_test_',
    );
    final service = GitRepositoryService();
    await service.initRepository(tempDir.path);
    _configureIdentity(tempDir.path);
    final repository = _TestRepository._(tempDir.path, service, tempDir);
    repository.writeFile('README.md', 'hello\n');
    await repository.commit('Initial commit');
    await service.createBranch(tempDir.path, 'main');
    await service.checkoutBranch(tempDir.path, 'main');
    await service.createBranch(tempDir.path, 'feature');
    return repository;
  }

  /// 额外建一个 bare 仓库作为 origin，用于 remote/branch/tag 的远端测试。
  ///
  /// bare 仓库放在**独立**临时目录：放在工作区里会被 status 当成未跟踪目录。
  static Future<_TestRepository> createWithRemote() async {
    final repository = await create();
    final bareDir = Directory.systemTemp.createTempSync('pyrite_git_origin_');
    final bare = Repository.init(path: bareDir.path, bare: true);
    bare.free();
    final barePath = p.normalize(bareDir.path);
    await repository.service.addRemote(repository.root, 'origin', barePath);
    repository._barePath = barePath;
    repository._bareTempDir = bareDir;
    return repository;
  }

  String? _barePath;
  Directory? _bareTempDir;

  void writeFile(String relativePath, String contents) {
    File(p.join(root, relativePath)).writeAsStringSync(contents);
  }

  Future<void> commit(String message) async {
    await service.stage(root, ['README.md']);
    await service.commit(
      root,
      GitCommitInput(
        message: message,
        authorName: 'Pyrite Test',
        authorEmail: 'pyrite-test@example.local',
      ),
    );
  }

  /// 通过临时 clone 读取远端 tag 列表，避免依赖被测服务的实现。
  Future<List<String>> remoteTagNames(String remoteName) async {
    final barePath = _barePath;
    if (barePath == null) return const [];
    final probe = Directory.systemTemp.createTempSync('pyrite_git_probe_');
    try {
      final repo = Repository.clone(
        url: barePath,
        localPath: p.join(probe.path, 'clone'),
      );
      try {
        return repo.tags;
      } finally {
        repo.free();
      }
    } finally {
      probe.deleteSync(recursive: true);
    }
  }

  Future<void> dispose() async {
    final bareTempDir = _bareTempDir;
    if (bareTempDir != null && bareTempDir.existsSync()) {
      bareTempDir.deleteSync(recursive: true);
    }
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  }
}

void _configureIdentity(String rootPath) {
  final gitDir = Repository.discover(startPath: rootPath);
  final repo = Repository.open(gitDir);
  try {
    final config = repo.config;
    try {
      config['user.name'] = 'Pyrite Test';
      config['user.email'] = 'pyrite-test@example.local';
      config['core.autocrlf'] = false;
    } finally {
      config.free();
    }
  } finally {
    repo.free();
  }
}
