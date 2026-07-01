import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/git/git_models.dart';
import 'package:pyrite_ide/core/services/git/git_repository_service.dart';

void main() {
  test(
    'GitRepositoryService handles the core local source-control flow',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'pyrite_git_service_test_',
      );

      try {
        _runGit(tempDir.path, ['init']);
        _configureIdentity(tempDir.path);

        final service = GitRepositoryService();
        final readmePath = p.join(tempDir.path, 'README.md');
        File(readmePath).writeAsStringSync('hello\n');

        var snapshot = await service.loadSnapshot(tempDir.path);
        expect(snapshot, isNotNull);
        expect(snapshot!.statusEntries.single.path, 'README.md');
        expect(snapshot.statusEntries.single.isUnstaged, isTrue);

        await service.stage(tempDir.path, ['README.md']);
        snapshot = await service.loadSnapshot(tempDir.path);
        expect(snapshot!.stagedCount, 1);

        await service.commit(
          tempDir.path,
          const GitCommitInput(
            message: 'Initial commit',
            authorName: 'Pyrite Test',
            authorEmail: 'pyrite-test@example.local',
          ),
        );

        snapshot = await service.loadSnapshot(tempDir.path);
        expect(snapshot!.statusEntries, isEmpty);
        expect(snapshot.authorName, 'Pyrite Test');
        expect(snapshot.authorEmail, 'pyrite-test@example.local');
        expect(snapshot.commits.single.summary, 'Initial commit');
        expect(
          await service.fileHistory(tempDir.path, 'README.md'),
          hasLength(1),
        );
        expect(
          (await service.blame(tempDir.path, 'README.md')).single.author,
          'Pyrite Test',
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    },
  );

  test('GitRepositoryService initializes a folder without .git', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'pyrite_git_init_test_',
    );

    try {
      final service = GitRepositoryService();

      expect(await service.loadSnapshot(tempDir.path), isNull);

      await service.initRepository(tempDir.path);
      final snapshot = await service.loadSnapshot(tempDir.path);

      expect(snapshot, isNotNull);
      expect(snapshot!.isEmpty, isTrue);
      expect(p.basename(snapshot.gitDir), '.git');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('GitRepositoryService adds a new remote', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'pyrite_git_remote_test_',
    );

    try {
      final service = GitRepositoryService();
      await service.initRepository(tempDir.path);

      await service.addRemote(
        tempDir.path,
        'origin',
        'https://example.com/pyrite/repo.git',
      );
      final snapshot = await service.loadSnapshot(tempDir.path);

      expect(snapshot!.remotes.single.name, 'origin');
      expect(
        snapshot.remotes.single.url,
        'https://example.com/pyrite/repo.git',
      );
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('GitRepositoryService switches to a remote tracking branch', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'pyrite_git_branch_test_',
    );

    try {
      final remoteDir = Directory(p.join(tempDir.path, 'remote.git'))
        ..createSync();
      final sourceDir = Directory(p.join(tempDir.path, 'source'))..createSync();
      final workDir = Directory(p.join(tempDir.path, 'work'))..createSync();

      _runGit(remoteDir.path, ['init', '--bare']);
      _runGit(sourceDir.path, ['init']);
      _runGit(sourceDir.path, ['checkout', '-b', 'main']);
      _configureIdentity(sourceDir.path);
      File(p.join(sourceDir.path, 'README.md')).writeAsStringSync('main\n');
      _runGit(sourceDir.path, ['add', 'README.md']);
      _runGit(sourceDir.path, ['commit', '-m', 'Initial commit']);
      _runGit(sourceDir.path, ['remote', 'add', 'origin', remoteDir.path]);
      _runGit(sourceDir.path, ['push', 'origin', 'main']);
      _runGit(sourceDir.path, ['checkout', '-b', 'feature/git']);
      File(
        p.join(sourceDir.path, 'feature.txt'),
      ).writeAsStringSync('feature\n');
      _runGit(sourceDir.path, ['add', 'feature.txt']);
      _runGit(sourceDir.path, ['commit', '-m', 'Feature commit']);
      _runGit(sourceDir.path, ['push', 'origin', 'feature/git']);

      final service = GitRepositoryService();
      await service.initRepository(workDir.path);
      await service.addRemote(workDir.path, 'origin', remoteDir.path);
      await service.fetch(workDir.path, 'origin', const GitCredentialDraft());
      var snapshot = await service.loadSnapshot(workDir.path);
      expect(
        snapshot!.branches.map((branch) => branch.name),
        contains('origin/feature/git'),
      );

      await service.checkoutBranch(
        workDir.path,
        'origin/feature/git',
        remote: true,
      );

      expect(
        _gitOutput(workDir.path, ['branch', '--show-current']),
        'feature/git',
      );
      snapshot = await service.loadSnapshot(workDir.path);
      expect(
        snapshot!.branches
            .singleWhere((branch) => branch.name == 'feature/git')
            .upstream,
        'origin/feature/git',
      );
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('GitRepositoryService preserves Chinese commit summaries', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'pyrite_git_utf8_test_',
    );

    try {
      _runGit(tempDir.path, ['init']);
      _configureIdentity(tempDir.path);

      final service = GitRepositoryService();
      File(p.join(tempDir.path, 'README.md')).writeAsStringSync('hello\n');
      await service.stage(tempDir.path, ['README.md']);
      await service.commit(
        tempDir.path,
        const GitCommitInput(
          message: '修复中文提交信息',
          authorName: '测试用户',
          authorEmail: 'pyrite-test@example.local',
        ),
      );
      final snapshot = await service.loadSnapshot(tempDir.path);

      expect(snapshot!.commits.single.summary, '修复中文提交信息');
      expect(snapshot.commits.single.author, '测试用户');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('GitRepositoryService discards tracked and untracked changes', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'pyrite_git_discard_test_',
    );

    try {
      _runGit(tempDir.path, ['init']);
      _configureIdentity(tempDir.path);

      final service = GitRepositoryService();
      final trackedFile = File(p.join(tempDir.path, 'tracked.txt'));
      final untrackedFile = File(p.join(tempDir.path, 'untracked.txt'));
      trackedFile.writeAsStringSync('original\n');
      await service.stage(tempDir.path, ['tracked.txt']);
      await service.commit(
        tempDir.path,
        const GitCommitInput(
          message: 'Initial commit',
          authorName: 'Pyrite Test',
          authorEmail: 'pyrite-test@example.local',
        ),
      );

      trackedFile.writeAsStringSync('changed\n');
      untrackedFile.writeAsStringSync('scratch\n');
      final snapshot = await service.loadSnapshot(tempDir.path);
      final trackedEntry = snapshot!.statusEntries.singleWhere(
        (entry) => entry.path == 'tracked.txt',
      );
      final untrackedEntry = snapshot.statusEntries.singleWhere(
        (entry) => entry.path == 'untracked.txt',
      );

      await service.discardChanges(tempDir.path, trackedEntry);
      await service.discardChanges(tempDir.path, untrackedEntry);

      expect(trackedFile.readAsStringSync(), 'original\n');
      expect(untrackedFile.existsSync(), isFalse);
      expect(
        (await service.loadSnapshot(tempDir.path))!.statusEntries,
        isEmpty,
      );
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });
}

void _runGit(String rootPath, List<String> args) {
  final result = Process.runSync('git', ['-C', rootPath, ...args]);
  if (result.exitCode != 0) {
    throw StateError(result.stderr);
  }
}

String _gitOutput(String rootPath, List<String> args) {
  final result = Process.runSync('git', ['-C', rootPath, ...args]);
  if (result.exitCode != 0) {
    throw StateError(result.stderr);
  }
  return result.stdout.toString().trim();
}

void _configureIdentity(String rootPath) {
  _runGit(rootPath, ['config', 'user.name', 'Pyrite Test']);
  _runGit(rootPath, ['config', 'user.email', 'pyrite-test@example.local']);
}
