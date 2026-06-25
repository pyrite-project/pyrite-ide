import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/git/git_repository_service.dart';

void main() {
  test('GitRepositoryService handles the core local source-control flow', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'pyrite_git_service_test_',
    );

    try {
      final repo = Repository.init(path: tempDir.path);
      final config = repo.config;
      config['user.name'] = 'Pyrite Test';
      config['user.email'] = 'pyrite-test@example.local';
      repo.free();

      final service = GitRepositoryService();
      final readmePath = p.join(tempDir.path, 'README.md');
      File(readmePath).writeAsStringSync('hello\n');

      var snapshot = service.loadSnapshot(tempDir.path);
      expect(snapshot, isNotNull);
      expect(snapshot!.statusEntries.single.path, 'README.md');
      expect(snapshot.statusEntries.single.isUnstaged, isTrue);

      service.stage(tempDir.path, ['README.md']);
      snapshot = service.loadSnapshot(tempDir.path);
      expect(snapshot!.stagedCount, 1);

      service.commit(
        tempDir.path,
        const GitCommitInput(
          message: 'Initial commit',
          authorName: 'Pyrite Test',
          authorEmail: 'pyrite-test@example.local',
        ),
      );

      snapshot = service.loadSnapshot(tempDir.path);
      expect(snapshot!.statusEntries, isEmpty);
      expect(snapshot.authorName, 'Pyrite Test');
      expect(snapshot.authorEmail, 'pyrite-test@example.local');
      expect(snapshot.commits.single.summary, 'Initial commit');
      expect(service.fileHistory(tempDir.path, 'README.md'), hasLength(1));
      expect(
        service.blame(tempDir.path, 'README.md').single.author,
        'Pyrite Test',
      );
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });
}
