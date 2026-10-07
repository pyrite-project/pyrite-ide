import 'dart:io';

import 'package:path/path.dart' as path;

/// The canonical spelling of a local file path: lexically normalized and, on
/// Windows, with an uppercased drive letter.
///
/// File paths act as identity keys across the editor — tab lookup, the editor
/// controller map, unsaved-change baselines — and those are compared by exact
/// string. Language servers frequently return URIs with a lowercase drive
/// (`file:///e:/...`) while file pickers and directory scans report `E:\`,
/// so an unnormalized spelling makes the same file open a second tab instead
/// of reusing the existing one.
String canonicalLocalPath(String filePath) =>
    canonicalLocalPathFor(filePath, path.Style.platform);

/// [canonicalLocalPath] against an explicit [path.Style], so tests can cover
/// both platform branches on either host.
String canonicalLocalPathFor(String filePath, path.Style style) {
  final normalized = path.Context(style: style).normalize(filePath);
  if (style != path.Style.windows) return normalized;
  final isDrivePath =
      normalized.length >= 2 &&
      normalized.codeUnitAt(1) == 0x3A /* ':' */ &&
      _isAsciiLetter(normalized.codeUnitAt(0));
  if (!isDrivePath) return normalized;
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

bool _isAsciiLetter(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7A);

/// Whether the host filesystem treats path casing as insignificant.
///
/// Only Windows does; macOS and Linux keep case-sensitive paths, where
/// `Foo.py` and `foo.py` really are two different files and folding them
/// together would merge two legitimate tabs into one.
bool get pathCaseInsensitive => Platform.isWindows;

/// An identity key for "this same file", independent of how the path was
/// spelled.
///
/// [canonicalLocalPath] only normalizes lexically, which leaves two ways for
/// one file to look like two:
///
/// * a symlink or Windows junction — `link/main.py` and `real/main.py` are the
///   same inode reached by different routes;
/// * directory-name casing on Windows, where `C:\Users\Foo\a.py` and
///   `C:\Users\foo\a.py` are one file.
///
/// Tab identity is otherwise an exact string comparison, so both spellings
/// would open a second tab holding the same document — two unsaved baselines,
/// two undo stacks, and whichever saved last silently wins. Resolving the
/// symlink chain and folding case collapses them onto one key.
///
/// Deliberately not cached: the answer changes when a file is created, deleted
/// or re-pointed, and every caller is already doing IO of its own.
String openFileIdentity(String filePath) =>
    openFileIdentityFor(filePath, path.Style.platform);

/// [openFileIdentity] with an explicit [path.Style], for tests.
///
/// [caseInsensitive] is overridden separately so both branches can be covered
/// from any host.
String openFileIdentityFor(
  String filePath,
  path.Style style, {
  bool? caseInsensitive,
  String Function(String path)? resolveLinks,
}) {
  final canonical = canonicalLocalPathFor(filePath, style);
  final resolver = resolveLinks ?? _resolveSymbolicLinksSync;
  final resolved = resolver(canonical);
  final fold = caseInsensitive ?? (style == path.Style.windows);
  return fold ? resolved.toLowerCase() : resolved;
}

/// Resolves the symlink chain, falling back to the input when the target does
/// not exist.
///
/// A not-yet-created file (a new tab, or one whose external delete we have not
/// noticed yet) has no link chain to follow, and the lexical spelling is the
/// best identity available for it.
String _resolveSymbolicLinksSync(String canonicalPath) {
  try {
    return File(canonicalPath).resolveSymbolicLinksSync();
  } catch (_) {
    return canonicalPath;
  }
}
