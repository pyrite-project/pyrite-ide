import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_backend.dart';

/// How many project files the quick-open index keeps before it stops walking.
///
/// The palette only ever shows the best few dozen matches, so a project with
/// tens of thousands of files gains nothing from indexing all of them; the
/// bound is what keeps opening the palette cheap on a large checkout.
const int projectFileIndexLimit = 20000;

/// One file the quick-open index knows about.
class ProjectFileEntry {
  const ProjectFileEntry({
    required this.path,
    required this.relativePath,
    required this.name,
  });

  /// Absolute (though not necessarily resolved) path of the file.
  final String path;

  /// Path relative to the project root, always using `/` separators.
  final String relativePath;

  /// The file's own name, without any directory part.
  final String name;
}

/// Recursively lists the files under [root] for the command palette's quick
/// open.
///
/// The walk skips the `.git` directory and never follows symbolic links, so a
/// link pointing back at an ancestor cannot expand forever. `.gitignore` rules
/// are applied with a single [gitIgnoredPaths] call over the collected paths,
/// which avoids opening the repository once per file. Only metadata is read:
/// file contents are never touched. At most [limit] files are collected; the
/// list is sorted by [ProjectFileEntry.relativePath] so a partial index is
/// still deterministic.
///
/// Returns an empty list when [root] does not exist or cannot be listed.
Future<List<ProjectFileEntry>> scanProjectFiles(
  Directory root, {
  int limit = projectFileIndexLimit,
}) async {
  if (limit <= 0 || !await root.exists()) return const [];

  final rootPath = path.normalize(root.path);
  final candidates = <String>[];

  // Iterative walk: a deep checkout must not be able to overflow the stack,
  // and skipping `.git` has to happen before descending rather than after
  // thousands of git object files were yielded.
  final pending = <Directory>[Directory(rootPath)];
  while (pending.isNotEmpty && candidates.length < limit) {
    final directory = pending.removeLast();
    final List<FileSystemEntity> entities;
    try {
      entities = await directory.list(followLinks: false).toList();
    } on FileSystemException {
      // An unreadable directory (permissions, a mount that went away) is
      // skipped rather than failing the whole index.
      continue;
    }
    entities.sort((a, b) => a.path.compareTo(b.path));

    final childDirectories = <Directory>[];
    for (final entity in entities) {
      if (candidates.length >= limit) break;
      // `followLinks: false` reports symlinks as links; skipping them covers
      // both a link to a file and a link to a directory.
      if (entity is Link) continue;
      if (entity is Directory) {
        if (path.basename(entity.path) == '.git') continue;
        childDirectories.add(entity);
      } else if (entity is File) {
        candidates.add(path.normalize(entity.path));
      }
    }
    // Reversed so the walk visits directories in name order.
    for (var i = childDirectories.length - 1; i >= 0; i--) {
      pending.add(childDirectories[i]);
    }
  }

  if (candidates.isEmpty) return const [];

  final ignored = await gitIgnoredPaths(candidates);
  final entries = <ProjectFileEntry>[];
  for (final filePath in candidates) {
    if (ignored.contains(filePath)) continue;
    entries.add(
      ProjectFileEntry(
        path: filePath,
        relativePath: path
            .relative(filePath, from: rootPath)
            .replaceAll('\\', '/'),
        name: path.basename(filePath),
      ),
    );
  }
  entries.sort(
    (a, b) =>
        a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase()),
  );
  return entries;
}

/// Files under the current workspace root, for the command palette's quick
/// open.
///
/// Rebuilt when the workspace folder changes. A workspace that is not open
/// yields an empty list; the dialog distinguishes that case by watching
/// [fileProvider] itself.
final projectFileIndexProvider =
    FutureProvider.autoDispose<List<ProjectFileEntry>>((ref) async {
      final root = ref.watch(fileProvider);
      if (root == null) return const <ProjectFileEntry>[];
      return scanProjectFiles(root);
    });
