/// Ordering shared by the local and board file trees.
///
/// Both trees are built from whatever order the backing store reports --
/// `Directory.list` and the board's `os.listdir` alike -- which is neither
/// sorted nor stable across platforms. A file explorer is expected to read
/// folders first and then follow one consistent order, so the two builders
/// apply this one comparator instead of each inventing its own.
library;

import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/models/settings.dart';

/// Compares two sibling entries: folders before files, then by [mode].
///
/// Folders are always ordered by name, whatever the mode: they have no
/// extension to group by, and a run of folders in arrival order would be the
/// one part of the list the setting did not fix.
int compareFileTreeEntries({
  required bool firstIsFolder,
  required String firstName,
  required bool secondIsFolder,
  required String secondName,
  FileSortMode mode = FileSortMode.byName,
}) {
  if (firstIsFolder != secondIsFolder) return firstIsFolder ? -1 : 1;
  if (firstIsFolder) return _compareNames(firstName, secondName);

  switch (mode) {
    case FileSortMode.byName:
      return _compareNames(firstName, secondName);
    case FileSortMode.byType:
      final byType = _extension(firstName).compareTo(_extension(secondName));
      if (byType != 0) return byType;
      return _compareNames(firstName, secondName);
  }
}

/// Names compare case-insensitively first so `Apple` and `apple` sit next to
/// each other on every platform; the case-sensitive comparison is only a
/// tie-breaker, which keeps the order stable for names that differ solely by
/// case.
int _compareNames(String first, String second) {
  final folded = first.toLowerCase().compareTo(second.toLowerCase());
  if (folded != 0) return folded;
  return first.compareTo(second);
}

/// The lowercase extension including its dot, or an empty string.
///
/// Extensionless files therefore sort before `.py`/`.txt`, which keeps the
/// `README`-style files at the head of the file group instead of scattering
/// them between extensions.
String _extension(String name) => path.extension(name).toLowerCase();
