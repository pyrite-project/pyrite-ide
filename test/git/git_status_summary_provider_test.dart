import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/git/git_repository_service.dart';
import 'package:pyrite_ide/core/services/git/git_status_summary_provider.dart';

void main() {
  test('GitStatusSummary reads a branch from a normal git directory', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'pyrite_git_status_test_',
    );

    try {
      final service = GitRepositoryService();
      await service.initRepository(tempDir.path);
      await _commitFile(service, tempDir.path, 'README.md', 'main\n');
      await service.createBranch(tempDir.path, 'main');
      await service.checkoutBranch(tempDir.path, 'main');

      final nestedPath = p.join(tempDir.path, 'lib', 'src');
      Directory(nestedPath).createSync(recursive: true);

      final summary = GitStatusSummary.inspect(nestedPath);

      expect(summary, isNotNull);
      expect(summary!.rootPath, tempDir.path);
      expect(summary.branchLabel, 'main');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('GitStatusSummary reads a branch from a worktree gitdir file', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'pyrite_git_worktree_status_test_',
    );

    try {
      final mainPath = p.join(tempDir.path, 'main');
      final worktreePath = p.join(tempDir.path, 'worktree');
      Directory(mainPath).createSync();

      final service = GitRepositoryService();
      await service.initRepository(mainPath);
      await _commitFile(service, mainPath, 'README.md', 'main\n');
      await service.createBranch(mainPath, 'main');
      await service.checkoutBranch(mainPath, 'main');
      await service.createBranch(mainPath, 'feature/git');

      final repo = Repository.open(Repository.discover(startPath: mainPath));
      try {
        final ref = Reference.lookup(
          repo: repo,
          name: 'refs/heads/feature/git',
        );
        try {
          final worktree = Worktree.create(
            repo: repo,
            name: 'feature-git',
            path: worktreePath,
            ref: ref,
          );
          worktree.free();
        } finally {
          ref.free();
        }
      } finally {
        repo.free();
      }

      final summary = GitStatusSummary.inspect(worktreePath);

      expect(summary, isNotNull);
      expect(summary!.rootPath, worktreePath);
      expect(summary.branchLabel, 'feature/git');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });
}

Future<void> _commitFile(
  GitRepositoryService service,
  String rootPath,
  String relativePath,
  String contents,
) async {
  File(p.join(rootPath, relativePath)).writeAsStringSync(contents);
  await service.stage(rootPath, [relativePath]);
  await service.commit(
    rootPath,
    const GitCommitInput(
      message: 'Initial commit',
      authorName: 'Pyrite Test',
      authorEmail: 'pyrite-test@example.local',
    ),
  );
}
