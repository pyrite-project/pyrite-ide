import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
        _runGit(tempDir.path, ['config', 'user.name', 'Pyrite Test']);
        _runGit(tempDir.path, [
          'config',
          'user.email',
          'pyrite-test@example.local',
        ]);

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
}

void _runGit(String rootPath, List<String> args) {
  final result = Process.runSync('git', ['-C', rootPath, ...args]);
  if (result.exitCode != 0) {
    throw StateError(result.stderr);
  }
}
