import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Name of the ignore list read from the local workspace root.
///
/// The file is a plain list of workspace-relative paths, one per line: `#`
/// starts a comment and blank lines are skipped. It only changes what the sync
/// preview pre-selects — nothing is deleted, and every ignored row can still be
/// ticked by hand.
const String syncIgnoreFileName = '.pyrsyncignore';

/// One parsed line of a `.pyrsyncignore` file.
///
/// Matching keeps the parts of `.gitignore` that matter for a flat path list:
/// * `*` matches inside one path segment, `**` spans segments, `?` matches a
///   single character;
/// * a pattern without a `/` matches at any depth, so `build` also covers
///   `sub/build`;
/// * a pattern that matches a directory also matches everything below it, so
///   `build` covers `build/out.bin` without needing a trailing `/*`.
class SyncIgnorePattern {
  SyncIgnorePattern._(this.pattern, this._matcher);

  /// Normalized text of the line this pattern was built from.
  final String pattern;

  final RegExp _matcher;

  /// Parses one line, returning `null` for blanks and comments.
  static SyncIgnorePattern? tryParse(String line) {
    // Windows-authored files use `\` separators; treat them as `/` so the same
    // list works on every platform the IDE runs on.
    var text = line.trim().replaceAll('\\', '/');
    if (text.isEmpty || text.startsWith('#')) return null;
    // Every path compared against a pattern is relative to the sync root, so a
    // leading `/` or `./` only restates that.
    while (text.startsWith('/')) {
      text = text.substring(1);
    }
    while (text.startsWith('./')) {
      text = text.substring(2);
    }
    // A trailing slash marks a directory; matching a directory already covers
    // its contents, so the marker does not change the semantics here.
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.isEmpty) return null;

    final anchored = text.contains('/');
    final buffer = StringBuffer('^');
    // Unanchored patterns match a path segment at any depth.
    if (!anchored) buffer.write(r'(?:.*/)?');
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char == '*') {
        final doubleStar = index + 1 < text.length && text[index + 1] == '*';
        if (!doubleStar) {
          buffer.write(r'[^/]*');
          continue;
        }
        index++;
        if (index + 1 < text.length && text[index + 1] == '/') {
          // `**/` also matches zero directories.
          index++;
          buffer.write(r'(?:.*/)?');
        } else {
          buffer.write('.*');
        }
      } else if (char == '?') {
        buffer.write(r'[^/]');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    // Anything below a matched directory is matched too.
    buffer.write(r'(?:/.*)?$');
    return SyncIgnorePattern._(text, RegExp(buffer.toString()));
  }

  /// Whether [relativePath] is this pattern or lives below it.
  bool matches(String relativePath) => _matcher.hasMatch(relativePath);

  @override
  String toString() => 'SyncIgnorePattern($pattern)';
}

/// The paths a workspace asked the sync preview to leave alone.
class SyncIgnoreRules {
  const SyncIgnoreRules(this.patterns);

  const SyncIgnoreRules.empty() : patterns = const <SyncIgnorePattern>[];

  /// Patterns in file order; empty means "nothing was configured".
  final List<SyncIgnorePattern> patterns;

  bool get isEmpty => patterns.isEmpty;

  bool get isNotEmpty => patterns.isNotEmpty;

  /// Whether [relativePath] should start the preview unchecked.
  ///
  /// The `.pyrsyncignore` file itself is always ignored: it configures the IDE,
  /// it is not part of the program the board should run.
  bool shouldIgnore(String relativePath) {
    final normalized = _normalizeRelative(relativePath);
    if (normalized.isEmpty) return false;
    if (normalized == syncIgnoreFileName) return true;
    for (final pattern in patterns) {
      if (pattern.matches(normalized)) return true;
    }
    return false;
  }

  /// Parses the whole file. Malformed lines are dropped instead of aborting the
  /// parse, so one bad line cannot disable the rest of the list.
  static SyncIgnoreRules parse(String content) {
    final patterns = <SyncIgnorePattern>[];
    for (final line in const LineSplitter().convert(content)) {
      final pattern = SyncIgnorePattern.tryParse(line);
      if (pattern != null) patterns.add(pattern);
    }
    return SyncIgnoreRules(patterns);
  }

  @override
  String toString() => 'SyncIgnoreRules(${patterns.length} patterns)';
}

String _normalizeRelative(String relativePath) {
  var normalized = relativePath.replaceAll('\\', '/');
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  if (normalized.startsWith('/')) normalized = normalized.substring(1);
  return normalized;
}

/// Reads `<localRoot>/.pyrsyncignore`.
///
/// A missing file is the normal case and yields no rules. An unreadable file
/// degrades to "no rules" after a log line: aborting the sync would be a worse
/// failure than running it with the ignore list unapplied, and the preview
/// still lists every path so the user can see what is about to move.
Future<SyncIgnoreRules> loadSyncIgnoreRules(String localRoot) async {
  final file = File(path.join(localRoot, syncIgnoreFileName));
  try {
    if (!await file.exists()) return const SyncIgnoreRules.empty();
    // `allowMalformed` keeps a stray byte from turning the whole ignore list
    // into an exception; paths are ASCII in practice. A leading BOM is absorbed
    // by the per-line trim in [SyncIgnorePattern.tryParse].
    final content = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    return SyncIgnoreRules.parse(content);
  } on FileSystemException catch (error) {
    debugPrint('[sync] cannot read $syncIgnoreFileName: $error');
    return const SyncIgnoreRules.empty();
  }
}
