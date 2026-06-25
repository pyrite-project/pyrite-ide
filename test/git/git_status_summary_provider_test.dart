import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/git/git_status_summary_provider.dart';

void main() {
  test('GitStatusSummary reads a branch from a normal git directory', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'pyrite_git_status_test_',
    );

    try {
      Directory(p.join(tempDir.path, '.git')).createSync();
      File(
        p.join(tempDir.path, '.git', 'HEAD'),
      ).writeAsStringSync('ref: refs/heads/main\n');
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

  test('GitStatusSummary reads a branch from a worktree gitdir file', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'pyrite_git_worktree_status_test_',
    );

    try {
      final worktreePath = p.join(tempDir.path, 'worktree');
      final gitDirPath = p.join(tempDir.path, 'gitdir');
      Directory(worktreePath).createSync();
      Directory(gitDirPath).createSync();
      File(
        p.join(worktreePath, '.git'),
      ).writeAsStringSync('gitdir: ../gitdir\n');
      File(
        p.join(gitDirPath, 'HEAD'),
      ).writeAsStringSync('ref: refs/heads/feature/git\n');

      final summary = GitStatusSummary.inspect(worktreePath);

      expect(summary, isNotNull);
      expect(summary!.rootPath, worktreePath);
      expect(summary.branchLabel, 'feature/git');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });
}
