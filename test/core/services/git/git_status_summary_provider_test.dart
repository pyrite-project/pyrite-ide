import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/git/git_repository_service.dart';
import 'package:pyrite_ide/core/services/git/git_status_summary_provider.dart';

void main() {
  test('GitStatusSummary reads a branch from a normal git directory', () async {
    final tempDir = _realTempDir('pyrite_git_status_test_');

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
      // macOS 上 Directory.systemTemp 位于 /var/...，而 git2dart 报告的
      // workdir 是解析过符号链接的 /private/var/...。两者指向同一个目录，
      // 这里把期望值也解析一遍再比较；生产代码返回真实路径是对的，不需要改。
      expect(summary!.rootPath, _resolved(tempDir.path));
      expect(summary.branchLabel, 'main');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('GitStatusSummary reads a branch from a worktree gitdir file', () async {
    final tempDir = _realTempDir('pyrite_git_worktree_status_test_');

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
      // 同上：worktree 路径也实拍在系统临时目录里，需要先解析符号链接
      // 才能和 git2dart 报告的 workdir 比较。
      expect(summary!.rootPath, _resolved(worktreePath));
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

/// 解析符号链接后的真实路径。
///
/// `Directory.systemTemp` 在 macOS 上返回 `/var/...`，它是 `/private/var/...`
/// 的符号链接；git2dart 报告的是 libgit2 解析过的真实路径。断言里先归一化
/// 期望值，避免把“同一个目录的两种写法”当成 bug。
String _resolved(String path) => Directory(path).resolveSymbolicLinksSync();

/// A new temporary directory, by its real path.
///
/// Git reports the repository root with symlinks resolved, and on macOS the
/// system temp directory sits behind one (`/var` is `/private/var`).
Directory _realTempDir(String prefix) => Directory(
  Directory.systemTemp.createTempSync(prefix).resolveSymbolicLinksSync(),
);
