// Pure logic for toggling Python-style line comments in the editor.
//
// Kept free of Flutter dependencies so it can be unit tested directly.

/// Matches an optional `#` comment marker directly after a line's leading
/// whitespace. The first group captures the whitespace so it can be
/// preserved when the marker is removed.
final RegExp _commentMarker = RegExp(r'^(\s*)# ?');

/// Result of toggling line comments over a block of lines.
class LineCommentToggleResult {
  const LineCommentToggleResult(this.lines, this.deltas);

  /// Transformed lines; join them with '\n' to build the replacement block.
  final List<String> lines;

  /// Per-line length delta (new length minus old length), used to map
  /// selection offsets onto the transformed block.
  final List<int> deltas;
}

/// Toggles Python-style `#` comments over [lines].
///
/// Lines are uncommented (marker plus one optional space removed, keeping
/// indentation) when every non-blank line already carries a marker;
/// otherwise each non-blank line gains one right after its indentation.
/// Whitespace-only lines are left untouched.
///
/// Returns null when there is nothing to change.
LineCommentToggleResult? toggleLineComments(List<String> lines) {
  if (lines.isEmpty) return null;

  var contentCount = 0;
  var commentedCount = 0;
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    contentCount++;
    if (_commentMarker.hasMatch(line)) commentedCount++;
  }
  final uncomment = contentCount > 0 && commentedCount == contentCount;

  final newLines = <String>[];
  final deltas = <int>[];
  var changed = false;
  for (final line in lines) {
    String newLine;
    if (uncomment) {
      newLine = line.replaceFirstMapped(
        _commentMarker,
        (match) => match.group(1)!,
      );
    } else if (line.trim().isEmpty) {
      newLine = line;
    } else {
      newLine = line.replaceFirstMapped(
        RegExp(r'^\s*'),
        (match) => '${match.group(0)}# ',
      );
    }
    changed |= newLine != line;
    newLines.add(newLine);
    deltas.add(newLine.length - line.length);
  }

  // A lone blank current line still gains a fresh marker so Ctrl+/ starts a
  // comment instead of doing nothing.
  if (!changed && !uncomment && lines.length == 1) {
    final newLine = '${lines.first}# ';
    return LineCommentToggleResult(
      [newLine],
      [newLine.length - lines.first.length],
    );
  }

  if (!changed) return null;
  return LineCommentToggleResult(newLines, deltas);
}
