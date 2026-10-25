import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/file/local_backend.dart';
import 'package:pyrite_ide/core/services/git/git_debug_log.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';

final gitStatusSummaryProvider = Provider<GitStatusSummary?>((ref) {
  final workspacePath = ref.watch(localWorkspaceProvider)?.path;
  return GitStatusSummary.inspect(
    workspacePath,
    // inspect() walks a real repository synchronously; only the label needs
    // the active locale, so translation is injected instead of threading a
    // Ref through the walk.
    fallbackBranchLabel: translate(ref, I18nKey.gitStatusSummaryFallback),
  );
});

class GitStatusSummary {
  const GitStatusSummary({required this.rootPath, required this.branchLabel});

  final String rootPath;
  final String branchLabel;

  static GitStatusSummary? inspect(
    String? workspacePath, {
    String? fallbackBranchLabel,
  }) {
    final label =
        fallbackBranchLabel ?? I18nKey.gitStatusSummaryFallback.fallback;
    try {
      GitDebugLog.log(
        'GitStatusSummary.inspect start workspace=$workspacePath',
      );
      if (workspacePath == null || workspacePath.isEmpty) return null;
      final normalizedPath = p.normalize(workspacePath);
      final startPath = Directory(normalizedPath).existsSync()
          ? normalizedPath
          : p.dirname(normalizedPath);
      GitDebugLog.log('GitStatusSummary.discover start startPath=$startPath');
      final gitDir = Repository.discover(startPath: startPath);
      GitDebugLog.log('GitStatusSummary.discover end gitDir=$gitDir');
      GitDebugLog.log('GitStatusSummary.open start gitDir=$gitDir');
      final repo = Repository.open(gitDir);

      try {
        GitDebugLog.log(
          'GitStatusSummary.open end path=${repo.path} workdir=${repo.workdir}',
        );
        final summary = GitStatusSummary(
          rootPath: _rootPath(repo, gitDir),
          branchLabel: _branchLabel(repo, label),
        );
        GitDebugLog.log(
          'GitStatusSummary.inspect end root=${summary.rootPath} '
          'branch=${summary.branchLabel}',
        );
        return summary;
      } finally {
        GitDebugLog.log('GitStatusSummary.free start gitDir=$gitDir');
        repo.free();
        GitDebugLog.log('GitStatusSummary.free end gitDir=$gitDir');
      }
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitStatusSummary.inspect failed workspace=$workspacePath',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static String _rootPath(Repository repo, String gitDir) {
    final workdir = repo.workdir;
    if (workdir.isEmpty) return p.normalize(p.dirname(gitDir));
    return p.normalize(workdir);
  }

  static String _branchLabel(Repository repo, String fallbackBranchLabel) {
    try {
      if (repo.isEmpty) return fallbackBranchLabel;
      final head = repo.head;
      try {
        if (head.isBranch) return head.shorthand;
        return head.target.sha.substring(0, 7);
      } finally {
        head.free();
      }
    } catch (_) {
      return fallbackBranchLabel;
    }
  }
}
