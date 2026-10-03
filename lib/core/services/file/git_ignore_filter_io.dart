import 'dart:io';

import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as path;

Future<Set<String>> gitIgnoredPaths(Iterable<String> entityPaths) async {
  final normalizedPaths = entityPaths.map(path.normalize).toList();
  if (normalizedPaths.isEmpty) return const {};

  try {
    final startPath = Directory(normalizedPaths.first).existsSync()
        ? normalizedPaths.first
        : path.dirname(normalizedPaths.first);
    final gitDir = Repository.discover(startPath: startPath);
    final repo = Repository.open(gitDir);
    try {
      final gitRoot = path.normalize(repo.workdir);
      if (gitRoot.isEmpty) return const {};

      final relativePaths = <String, String>{};
      for (final entityPath in normalizedPaths) {
        final isInRepo =
            path.equals(gitRoot, entityPath) ||
            path.isWithin(gitRoot, entityPath);
        if (!isInRepo) continue;
        final relativePath = path
            .relative(entityPath, from: gitRoot)
            .replaceAll('\\', '/');
        relativePaths[relativePath] = entityPath;
      }
      if (relativePaths.isEmpty) return const {};

      final ignored = <String>{};
      for (final entry in relativePaths.entries) {
        if (Ignore.pathIsIgnored(repo: repo, path: entry.key)) {
          ignored.add(entry.value);
        }
      }
      return ignored;
    } finally {
      repo.free();
    }
  } catch (_) {
    return const {};
  }
}
