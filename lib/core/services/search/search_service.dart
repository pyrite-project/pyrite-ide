import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/file/local_backend.dart';

/// Files larger than this are skipped from content search to avoid reading
/// huge binaries into memory.
const int maxSearchFileSize = 5 * 1024 * 1024;

/// How many leading bytes are sampled to decide whether a file is binary.
const int binaryProbeSize = 8192;

/// Search query plus the toggles that shape how the pattern is compiled.
class SearchOptions {
  const SearchOptions({
    this.pattern = '',
    this.isRegExp = false,
    this.caseSensitive = false,
    this.wholeWord = false,
    this.replaceText = '',
  });

  final String pattern;
  final bool isRegExp;
  final bool caseSensitive;
  final bool wholeWord;

  /// Replacement text used by the cross-file replace action.
  final String replaceText;

  bool get isEmpty => pattern.isEmpty;

  SearchOptions copyWith({
    String? pattern,
    bool? isRegExp,
    bool? caseSensitive,
    bool? wholeWord,
    String? replaceText,
  }) => SearchOptions(
    pattern: pattern ?? this.pattern,
    isRegExp: isRegExp ?? this.isRegExp,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    wholeWord: wholeWord ?? this.wholeWord,
    replaceText: replaceText ?? this.replaceText,
  );

  /// Compiles the pattern into a [RegExp].
  ///
  /// In plain-text mode the user input is escaped first; in regex mode it is
  /// used verbatim. Whole-word wrapping is only applied in plain-text mode,
  /// because adding `\b` around an arbitrary regular expression (alternations,
  /// anchors, groups) would change its meaning.
  ///
  /// [multiLine] makes `^` and `$` anchor at line boundaries. Whole-content
  /// matching uses it so anchored patterns keep the per-line semantics the
  /// result list presents.
  RegExp toRegExp({bool multiLine = false}) {
    var source = isRegExp ? pattern : RegExp.escape(pattern);
    if (wholeWord && !isRegExp) {
      source = r'\b' + source + r'\b';
    }
    return RegExp(source, caseSensitive: caseSensitive, multiLine: multiLine);
  }
}

/// One matched line inside a file.
class SearchMatch {
  const SearchMatch({
    required this.lineIndex,
    required this.lineText,
    required this.ranges,
  });

  /// Zero-based line number.
  final int lineIndex;

  /// The (line-ending normalized) text of the matched line.
  final String lineText;

  /// Inclusive-exclusive match spans within [lineText].
  final List<(int start, int end)> ranges;
}

/// All matches found in a single file.
class FileSearchResult {
  const FileSearchResult({required this.filePath, required this.matches});

  final String filePath;
  final List<SearchMatch> matches;

  int get matchCount => matches.length;
}

/// A file's path plus its line-ending normalized text, produced by
/// [scanProject] and consumed by [matchFiles].
typedef ScannedFile = ({String path, String content});

/// Progress snapshot emitted while a search runs.
class SearchProgress {
  const SearchProgress({
    required this.scanned,
    required this.total,
    required this.matchedFiles,
    required this.matchedLines,
  });

  final int scanned;
  final int total;
  final int matchedFiles;
  final int matchedLines;
}

/// Cooperative cancellation token for a running search/replace.
class SearchCancelToken {
  bool cancelled = false;
}

bool _isInsideGitDir(String normalizedPath) =>
    path.split(normalizedPath).contains('.git');

Future<bool> _isBinary(File file) async {
  List<int> bytes;
  try {
    bytes = await file.openRead(0, binaryProbeSize).first;
  } catch (_) {
    return false;
  }
  if (bytes.isEmpty) return false;
  // NUL byte presence is the standard "this is not text" heuristic.
  for (final byte in bytes) {
    if (byte == 0) return true;
  }
  return false;
}

Future<String?> _safeRead(File file) async {
  try {
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

String _normalizeContent(String content) =>
    content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

/// Walks [root] once and reads every searchable file's text content.
///
/// This is the slow, disk-bound half of a search. It skips the `.git`
/// directory, files excluded by `.gitignore` (via [gitIgnoredPaths]),
/// binaries, and files larger than [maxSearchFileSize]. Line endings are
/// normalized to `\n` so CRLF projects behave like LF ones. The result is
/// cached by the caller and re-matched in memory by [matchFiles], so typing or
/// toggling match options never repeats this walk.
Future<List<ScannedFile>> scanProject(
  Directory root, {
  SearchCancelToken? cancel,
  void Function(int scanned, int total)? onProgress,
}) async {
  final filePaths = <String>[];

  // `followLinks: false` because a recursive walk does not detect cycles: one
  // symlink pointing back at an ancestor would expand forever and leave the
  // search stuck in `running` with no way out but a restart.
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (cancel?.cancelled ?? false) return const [];
    if (entity is! File) continue;
    final normalized = path.normalize(entity.path);
    if (_isInsideGitDir(normalized)) continue;
    filePaths.add(normalized);
  }

  final ignored = await gitIgnoredPaths(filePaths);
  final candidates = filePaths.where((p) => !ignored.contains(p)).toList();

  final files = <ScannedFile>[];
  var scanned = 0;

  for (final filePath in candidates) {
    if (cancel?.cancelled ?? false) break;
    scanned++;

    final file = File(filePath);
    try {
      if (await file.length() > maxSearchFileSize) {
        onProgress?.call(scanned, candidates.length);
        continue;
      }
      if (await _isBinary(file)) {
        onProgress?.call(scanned, candidates.length);
        continue;
      }
    } catch (_) {
      continue;
    }

    final content = await _safeRead(file);
    if (content != null) {
      files.add((path: filePath, content: _normalizeContent(content)));
    }
    onProgress?.call(scanned, candidates.length);
  }

  return files;
}

/// Pure in-memory match over scanned files — the fast half of a search.
///
/// Uses [RegExp.allMatches] on the whole content and only builds line offsets
/// for files that actually match, so the vast majority of files in a project
/// cost a single regex sweep and nothing else. Matches are grouped per line
/// into the [SearchMatch] structure the results list renders.
List<FileSearchResult> matchFiles(
  List<ScannedFile> files,
  SearchOptions options,
) {
  if (options.isEmpty) return const [];
  final regex = options.toRegExp(multiLine: true);
  final results = <FileSearchResult>[];

  for (final scanned in files) {
    final content = scanned.content;
    // Fast reject: no match anywhere means no line bookkeeping for this file.
    if (!regex.hasMatch(content)) continue;

    final fileMatches = _collectLineMatches(content, regex);
    if (fileMatches.isNotEmpty) {
      results.add(
        FileSearchResult(filePath: scanned.path, matches: fileMatches),
      );
    }
  }

  return results;
}

/// Index of the line containing [offset], given the file's line-start offsets.
int _lineIndexFor(List<int> lineStarts, int offset) {
  var low = 0;
  var high = lineStarts.length - 1;
  while (low < high) {
    final mid = (low + high + 1) >> 1;
    if (lineStarts[mid] <= offset) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low;
}

List<SearchMatch> _collectLineMatches(String content, RegExp regex) {
  // Only paid by files that match, unlike the previous whole-file
  // `split('\n')` which ran for every candidate.
  final lineStarts = <int>[0];
  for (var i = 0; i < content.length; i++) {
    if (content.codeUnitAt(i) == 0x0A) lineStarts.add(i + 1);
  }

  String lineText(int line) {
    final start = lineStarts[line];
    final end = line + 1 < lineStarts.length
        ? lineStarts[line + 1] - 1
        : content.length;
    return content.substring(start, end);
  }

  final byLine = <int, List<(int start, int end)>>{};
  for (final match in regex.allMatches(content)) {
    if (match.start == match.end) continue;
    final line = _lineIndexFor(lineStarts, match.start);
    final lineStart = lineStarts[line];
    // Measured arithmetically rather than via `lineText(line).length`: the
    // substring would be allocated once per match just to be discarded, and
    // the length is exactly the span between the two offsets.
    final lineEnd = line + 1 < lineStarts.length
        ? lineStarts[line + 1] - 1
        : content.length;
    final length = lineEnd - lineStart;
    final start = match.start - lineStart;
    var end = match.end - lineStart;
    // A match may span lines (e.g. [\s\S]); display clamps it to its first
    // line so the highlight stays inside [lineText].
    if (end > length) end = length;
    if (end <= start) continue;
    (byLine[line] ??= []).add((start, end));
  }

  final lines = byLine.keys.toList()..sort();
  final matches = <SearchMatch>[];
  for (final line in lines) {
    final ranges = byLine[line]!..sort((a, b) => a.$1.compareTo(b.$1));
    matches.add(
      SearchMatch(lineIndex: line, lineText: lineText(line), ranges: ranges),
    );
  }
  return matches;
}

/// Recursively searches [root] for [options.pattern].
///
/// Composed of a [scanProject] walk plus an in-memory [matchFiles] pass;
/// kept for callers (and tests) that want the whole pipeline in one call.
Future<List<FileSearchResult>> searchInDirectory(
  Directory root,
  SearchOptions options, {
  SearchCancelToken? cancel,
  void Function(SearchProgress progress)? onProgress,
}) async {
  if (options.isEmpty) return const [];

  final files = await scanProject(
    root,
    cancel: cancel,
    onProgress: (scanned, total) => onProgress?.call(
      SearchProgress(
        scanned: scanned,
        total: total,
        matchedFiles: 0,
        matchedLines: 0,
      ),
    ),
  );
  if (cancel?.cancelled ?? false) return const [];

  final results = matchFiles(files, options);
  var matchedLines = 0;
  for (final result in results) {
    matchedLines += result.matchCount;
  }
  onProgress?.call(
    SearchProgress(
      scanned: files.length,
      total: files.length,
      matchedFiles: results.length,
      matchedLines: matchedLines,
    ),
  );
  return results;
}

/// Replaces every occurrence of the pattern in the files that currently hold
/// matches ([results]), writing each changed file back to disk.
///
/// Returns the total number of replacements made. Files are re-read from disk
/// so line endings are preserved. In regex mode `$1` style group references
/// are honored. Skips files that cannot be read.
Future<int> replaceAllInResults(
  List<FileSearchResult> results,
  SearchOptions options, {
  SearchCancelToken? cancel,
  void Function(int done, int total)? onProgress,
}) async {
  if (options.isEmpty || results.isEmpty) return 0;

  final regex = options.toRegExp(multiLine: true);
  var totalReplacements = 0;
  var done = 0;

  for (final fileResult in results) {
    if (cancel?.cancelled ?? false) break;
    final file = File(fileResult.filePath);
    final content = await _safeRead(file);
    if (content == null) {
      done++;
      onProgress?.call(done, results.length);
      continue;
    }

    var occurrences = 0;
    for (final match in regex.allMatches(content)) {
      if (match.start != match.end) occurrences++;
    }
    if (occurrences == 0) {
      done++;
      onProgress?.call(done, results.length);
      continue;
    }

    final newContent = _replaceContent(content, regex, options);
    if (newContent != content) {
      try {
        await file.writeAsString(newContent);
        totalReplacements += occurrences;
      } catch (_) {
        // Leave the file untouched if writing fails (permissions, etc.).
      }
    }
    done++;
    onProgress?.call(done, results.length);
  }

  return totalReplacements;
}

/// Replaces the [occurrenceIndex]-th (0-based, file-internal) match of the
/// pattern in [filePath], writing the file back to disk. The file is matched
/// against its raw on-disk content, so line endings are preserved.
///
/// Returns `true` when a replacement was written. The ordinal (not an offset)
/// locates the match because cached content is line-ending normalized and its
/// offsets therefore differ from the raw file.
Future<bool> replaceOneOccurrence(
  String filePath,
  SearchOptions options,
  int occurrenceIndex,
) async {
  if (options.isEmpty) return false;
  final file = File(filePath);
  final content = await _safeRead(file);
  if (content == null) return false;

  final regex = options.toRegExp(multiLine: true);
  var index = 0;
  RegExpMatch? target;
  for (final match in regex.allMatches(content)) {
    if (match.start == match.end) continue;
    if (index == occurrenceIndex) {
      target = match;
      break;
    }
    index++;
  }
  if (target == null) return false;

  final replacement = _expandReplacement(target, options);
  final newContent =
      content.substring(0, target.start) +
      replacement +
      content.substring(target.end);
  try {
    await file.writeAsString(newContent);
    return true;
  } catch (_) {
    return false;
  }
}

/// Expands [options.replaceText] for one [match].
///
/// In regex mode, `$1`, `$2`, … references are expanded against the match's
/// capture groups (Dart's [String.replaceAll] does not perform this expansion
/// for a [RegExp]). In plain-text mode the replacement is verbatim, so `$1`
/// is inserted literally.
///
/// A `$` followed by digits that do not name a capture group is kept as
/// written. `int.tryParse` rather than `int.parse` matters here: the digits
/// come straight from the user's replacement text, and `$12345678901234567890`
/// overflows a 64-bit int, so parsing it would throw and abort the whole
/// replace instead of inserting the literal text the user typed.
String _expandReplacement(Match match, SearchOptions options) {
  if (!options.isRegExp) return options.replaceText;
  return options.replaceText.replaceAllMapped(RegExp(r'\$(\d+)'), (group) {
    final reference = group.group(0)!;
    final index = int.tryParse(group.group(1)!);
    if (index == null) return reference;
    if (index == 0) return match.group(0) ?? '';
    if (index > match.groupCount) return reference;
    return match.group(index) ?? '';
  });
}

/// Replaces every match of [regex] in [content] with [options.replaceText].
///
/// Both modes go through [regex] rather than `String.replaceAll(pattern, …)`:
/// the pattern the user saw in the results list was produced by
/// [SearchOptions.toRegExp], which folds in case-insensitivity and the
/// whole-word `\b` wrapping. Replacing with the raw literal would edit
/// substrings that were never shown as matches — `cat` would also rewrite
/// `concat` — and would silently miss case-differing hits.
String _replaceContent(String content, RegExp regex, SearchOptions options) {
  return content.replaceAllMapped(
    regex,
    (match) => _expandReplacement(match, options),
  );
}
