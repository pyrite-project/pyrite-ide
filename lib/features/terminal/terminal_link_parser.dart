/// Parsing of clickable references out of terminal output.
///
/// A terminal has no document model: the only thing the widget can read is the
/// cell buffer. Links are therefore recovered by scanning the text of one
/// buffer line, which means the scanner has to be a plain function over a
/// string — that keeps it unit-testable without a rendering host, and keeps the
/// widget's only job to feed it the right line.
///
/// Two kinds survive a scan:
///  * `http(s)://…` URLs,
///  * `path.to/file.py:12` / `path.py:12:4` / Windows `C:\dir\file:12`.
///
/// A Python traceback (`File "main.py", line 12`) is also recognised because
/// terminal output is where a traceback usually lands, and it means the same
/// thing as `main.py:12`.
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:xterm/xterm.dart';

enum TerminalLinkKind { url, file }

/// One clickable span of terminal text.
///
/// [start] and [end] are cell columns of the host line (end exclusive), not
/// UTF-16 offsets: the buffer line is converted with
/// [terminalLineCellText] so both coordinates coincide, and a click only has a
/// cell column to offer.
class TerminalLink {
  const TerminalLink({
    required this.kind,
    required this.text,
    required this.start,
    required this.end,
    this.url,
    this.path,
    this.line,
    this.column,
  });

  final TerminalLinkKind kind;

  /// The exact substring that was recognised, for menu labels and debugging.
  final String text;

  final int start;
  final int end;

  /// Set for [TerminalLinkKind.url].
  final String? url;

  /// Set for [TerminalLinkKind.file]. Relative paths stay relative here; the
  /// widget resolves them against the workspace root.
  final String? path;

  /// 1-based, as terminals print them.
  final int? line;

  /// 1-based, as terminals print them (`path:line:column` only).
  final int? column;

  @override
  String toString() =>
      'TerminalLink($kind, $start..$end, ${url ?? path}, line=$line, col=$column)';
}

/// Builds a one-character-per-cell rendering of [line].
///
/// Terminal cells, not code points, are the coordinate system a click produces
/// (`TerminalView.onTapUp` hands out a [CellOffset]). Making the string have
/// exactly one character per column means a parsed text offset can be compared
/// against a clicked column directly, which removes an entire class of
/// off-by-width bugs around CJK text.
///
/// Two deliberate replacements keep the invariant:
///  * the second cell of a wide character is empty in the buffer, so it becomes
///    a space (the wide glyph itself still occupies its first cell),
///  * characters above the BMP would add a second UTF-16 unit and shift every
///    following offset, so they become a space too. Links are ASCII in
///    practice, and a stray emoji must not move the URL after it.
String terminalLineCellText(BufferLine line) {
  final text = StringBuffer();
  for (var column = 0; column < line.length; column++) {
    final codePoint = line.getCodePoint(column);
    if (codePoint == 0 || codePoint > 0xffff) {
      text.write(' ');
      continue;
    }
    text.writeCharCode(codePoint);
  }
  return text.toString();
}

/// URLs stop at whitespace and at the delimiters terminals commonly wrap output
/// in (`<…>`, quotes, brackets, braces, pipes, backslashes, carets).
final RegExp _urlPattern = RegExp(
  r'''https?://[^\s<>"'`\[\]{}|\\^]+''',
  caseSensitive: false,
);

/// Python/MicroPython traceback frame form.
final RegExp _tracebackPattern = RegExp(r'''File "([^"]+)", line (\d+)''');

/// `C:\dir\file.py:12(:4)` — kept separate from the portable form because the
/// drive letter itself contains a colon and would otherwise split the path.
final RegExp _windowsPathPattern = RegExp(
  r'''([A-Za-z]:[\\/][^\s:]+):(\d+)(?::(\d+))?''',
);

/// Portable `dir/file.py:12(:4)` and bare `file.py:12`.
///
/// The colon is excluded from the path character class so the greedy group can
/// never swallow the separator; the engine backtracks from the last path
/// character to the `:digits` suffix.
final RegExp _portablePathPattern = RegExp(
  r'''([\w.~/\\-]+):(\d+)(?::(\d+))?''',
);

/// True when [candidate] plausibly names a file rather than a clock time or a
/// plain number that happens to have a decimal point.
bool _looksLikePath(String candidate) {
  if (candidate.isEmpty) return false;
  if (!candidate.contains('.') &&
      !candidate.contains('/') &&
      !candidate.contains(r'\')) {
    return false;
  }
  // `12.30:45` is a timestamp, not a file.
  if (RegExp(r'^[\d.]+$').hasMatch(candidate)) return false;
  return true;
}

/// Strips punctuation that a sentence put after the URL but the URL does not
/// own: a trailing period, comma, or an unbalanced closing bracket.
String _trimUrl(String raw) {
  var end = raw.length;
  while (end > 0) {
    final char = raw[end - 1];
    if (const {' ', '.', ',', ';', ':', '!', '?'}.contains(char)) {
      end--;
      continue;
    }
    if (char == ')' || char == ']' || char == '}') {
      final open = switch (char) {
        ')' => '(',
        ']' => '[',
        _ => '{',
      };
      final body = raw.substring(0, end);
      if (_countChar(body, char) > _countChar(body, open)) {
        end--;
        continue;
      }
    }
    break;
  }
  return raw.substring(0, end);
}

int _countChar(String text, String char) {
  var count = 0;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == char) count++;
  }
  return count;
}

/// Extracts every clickable reference from [text], ordered by position.
///
/// URLs are collected first so a port in `https://host:8080/…` is never re-read
/// as a file reference; later candidates that overlap an already accepted span
/// are dropped rather than reported twice.
///
/// A bare `host:port` without a scheme (`example.com:8080`) is indistinguishable
/// from `file:line` — both are `name:digits`. It is treated as a file reference
/// because compiler and traceback output, the common case in a terminal, always
/// uses that shape, and clicking it reports "file not found" rather than doing
/// something harmful.
List<TerminalLink> parseTerminalLinks(String text) {
  if (text.isEmpty) return const [];

  final links = <TerminalLink>[];

  bool overlaps(int start, int end) {
    for (final link in links) {
      if (start < link.end && end > link.start) return true;
    }
    return false;
  }

  for (final match in _urlPattern.allMatches(text)) {
    final url = _trimUrl(match.group(0)!);
    if (url.length <= 'https://'.length) continue;
    final start = match.start;
    links.add(
      TerminalLink(
        kind: TerminalLinkKind.url,
        text: url,
        start: start,
        end: start + url.length,
        url: url,
      ),
    );
  }

  for (final match in _tracebackPattern.allMatches(text)) {
    final file = match.group(1)!.trim();
    final line = int.tryParse(match.group(2)!);
    if (file.isEmpty || line == null || line <= 0) continue;
    if (overlaps(match.start, match.end)) continue;
    links.add(
      TerminalLink(
        kind: TerminalLinkKind.file,
        text: match.group(0)!,
        start: match.start,
        end: match.end,
        path: file,
        line: line,
      ),
    );
  }

  for (final pattern in [_windowsPathPattern, _portablePathPattern]) {
    for (final match in pattern.allMatches(text)) {
      final file = match.group(1)!.trim();
      final line = int.tryParse(match.group(2)!);
      final column = match.groupCount >= 3
          ? int.tryParse(match.group(3) ?? '')
          : null;
      if (line == null || line <= 0) continue;
      if (!_looksLikePath(file)) continue;
      if (overlaps(match.start, match.end)) continue;
      links.add(
        TerminalLink(
          kind: TerminalLinkKind.file,
          text: match.group(0)!,
          start: match.start,
          end: match.end,
          path: file,
          line: line,
          column: column != null && column > 0 ? column : null,
        ),
      );
    }
  }

  links.sort((a, b) => a.start.compareTo(b.start));
  return links;
}

/// Returns the link covering [column] on a line, or null when the click landed
/// on ordinary output.
TerminalLink? terminalLinkAtCell(List<TerminalLink> links, int column) {
  for (final link in links) {
    if (column >= link.start && column < link.end) return link;
  }
  return null;
}

/// Maps a relative reference printed by a program onto a real file.
///
/// A program prints paths relative to its own working directory, which the IDE
/// does not know. The workspace root is the only stable anchor, so it is tried
/// first, then the raw path (covers absolute paths and a terminal started
/// inside the project). `~` is expanded because shell output prints it
/// literally.
///
/// [exists] is injected so the resolution rules can be tested without touching
/// the filesystem.
String? resolveTerminalLinkPath({
  required String reference,
  required bool Function(String candidate) exists,
  String? workspaceRoot,
  String? homeDirectory,
}) {
  var trimmed = reference.trim();
  if (trimmed.isEmpty) return null;

  final home =
      homeDirectory ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (home != null && trimmed == '~') {
    // A bare `~` is the home directory itself; taking `substring(2)` of a
    // one-character string is what used to throw here.
    trimmed = home;
  } else if (home != null &&
      (trimmed.startsWith('~/') || trimmed.startsWith(r'~\'))) {
    trimmed = path.join(home, trimmed.substring(2));
  }

  final candidates = <String>[];
  if (path.isAbsolute(trimmed)) {
    candidates.add(path.normalize(trimmed));
  } else {
    if (workspaceRoot != null && workspaceRoot.isNotEmpty) {
      candidates.add(path.normalize(path.join(workspaceRoot, trimmed)));
    }
    candidates.add(path.normalize(trimmed));
  }

  for (final candidate in candidates) {
    if (exists(candidate)) return candidate;
  }
  return null;
}
