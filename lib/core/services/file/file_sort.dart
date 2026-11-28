/// Ordering shared by the local and board file trees.
///
/// Both trees are built from whatever order the backing store reports --
/// `Directory.list` and the board's `os.listdir` alike -- which is neither
/// sorted nor stable across platforms. A file explorer is expected to follow
/// one consistent order, so the two builders apply this one comparator
/// instead of each inventing its own.
library;

import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/models/settings.dart';

/// Compares two sibling entries according to [mode].
///
/// [FileSortMode.byName] is a plain case-insensitive name sort over
/// everything, folders interleaved with files exactly like the raw listing a
/// file manager shows in name order. Forcing folders to the top here instead
/// would group the list by kind in both modes and make the two settings look
/// identical.
///
/// [FileSortMode.byType] groups by kind: folders as their own kind first,
/// then files grouped by extension, alphabetical within each group -- what a
/// file manager's type order shows.
int compareFileTreeEntries({
  required bool firstIsFolder,
  required String firstName,
  required bool secondIsFolder,
  required String secondName,
  FileSortMode mode = FileSortMode.byName,
}) {
  switch (mode) {
    case FileSortMode.byName:
      return _compareNames(firstName, secondName);
    case FileSortMode.byType:
      if (firstIsFolder != secondIsFolder) return firstIsFolder ? -1 : 1;
      if (firstIsFolder) return _compareNames(firstName, secondName);
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
