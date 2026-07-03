import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/file/local_workspace_provider.dart';

final gitStatusSummaryProvider = Provider<GitStatusSummary?>((ref) {
  final workspacePath = ref.watch(localWorkspaceProvider)?.path;
  return GitStatusSummary.inspect(workspacePath);
});

class GitStatusSummary {
  const GitStatusSummary({required this.rootPath, required this.branchLabel});

  final String rootPath;
  final String branchLabel;

  static GitStatusSummary? inspect(String? workspacePath) {
    try {
      final rootPath = _discoverRoot(workspacePath);
      if (rootPath == null) return null;

      final gitDir = _resolveGitDir(rootPath);
      if (gitDir == null) return null;

      return GitStatusSummary(
        rootPath: rootPath,
        branchLabel: _readHeadLabel(gitDir) ?? 'Git 仓库',
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static String? _discoverRoot(String? workspacePath) {
    if (workspacePath == null || workspacePath.isEmpty) return null;

    var current = p.normalize(workspacePath);
    if (!Directory(current).existsSync()) {
      current = p.dirname(current);
    }

    while (true) {
      final dotGitPath = p.join(current, '.git');
      final dotGitType = FileSystemEntity.typeSync(dotGitPath);
      if (dotGitType == FileSystemEntityType.directory ||
          dotGitType == FileSystemEntityType.file) {
        return current;
      }

      final parent = p.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
  }

  static String? _resolveGitDir(String rootPath) {
    final dotGitPath = p.join(rootPath, '.git');
    final dotGitType = FileSystemEntity.typeSync(dotGitPath);
    if (dotGitType == FileSystemEntityType.directory) {
      return dotGitPath;
    }
    if (dotGitType != FileSystemEntityType.file) return null;

    final contents = File(dotGitPath).readAsStringSync();
    final match = RegExp(
      r'^gitdir:\s*(.+)\s*$',
      multiLine: true,
    ).firstMatch(contents);
    final gitDirPath = match?.group(1)?.trim();
    if (gitDirPath == null || gitDirPath.isEmpty) return null;

    return p.normalize(
      p.isAbsolute(gitDirPath) ? gitDirPath : p.join(rootPath, gitDirPath),
    );
  }

  static String? _readHeadLabel(String gitDir) {
    final headPath = p.join(gitDir, 'HEAD');
    if (!File(headPath).existsSync()) return null;

    final head = File(headPath).readAsStringSync().trim();
    const branchPrefix = 'ref: refs/heads/';
    const refPrefix = 'ref: refs/';
    if (head.startsWith(branchPrefix)) {
      return head.substring(branchPrefix.length);
    }
    if (head.startsWith(refPrefix)) {
      return head.substring(refPrefix.length);
    }
    if (head.length >= 7) return head.substring(0, 7);
    return head.isEmpty ? null : head;
  }
}
