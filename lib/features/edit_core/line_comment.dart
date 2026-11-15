// Pure logic for toggling line comments in the editor.
//
// Kept free of Flutter dependencies so it can be unit tested directly.

/// Matches an optional comment marker directly after a line's leading
/// whitespace. The first group captures the whitespace so it can be preserved
/// when the marker is removed.
final RegExp _leadingWhitespace = RegExp(r'^(\s*)');

/// Result of toggling line comments over a block of lines.
class LineCommentToggleResult {
  const LineCommentToggleResult(this.lines, this.deltas);

  /// Transformed lines; join them with '\n' to build the replacement block.
  final List<String> lines;

  /// Per-line length delta (new length minus old length), used to map
  /// selection offsets onto the transformed block.
  final List<int> deltas;
}

/// Toggles line comments over [lines] using the [marker] prefix (for example
/// `#`, `//` or `--`).
///
/// Lines are uncommented (marker plus one optional space removed, keeping
/// indentation) when every non-blank line already carries a marker; otherwise
/// each non-blank line gains one right after its indentation. Whitespace-only
/// lines are left untouched.
///
/// Returns null when there is nothing to change.
LineCommentToggleResult? toggleLineComments(
  List<String> lines, {
  String marker = '#',
}) {
  if (lines.isEmpty) return null;
  final markerRegExp = RegExp(r'^(\s*)' + RegExp.escape(marker) + r' ?');

  var contentCount = 0;
  var commentedCount = 0;
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    contentCount++;
    if (markerRegExp.hasMatch(line)) commentedCount++;
  }
  final uncomment = contentCount > 0 && commentedCount == contentCount;

  final newLines = <String>[];
  final deltas = <int>[];
  var changed = false;
  for (final line in lines) {
    String newLine;
    if (uncomment) {
      newLine = line.replaceFirstMapped(
        markerRegExp,
        (match) => match.group(1)!,
      );
    } else if (line.trim().isEmpty) {
      newLine = line;
    } else {
      newLine = line.replaceFirstMapped(
        _leadingWhitespace,
        (match) => '${match.group(0)}$marker ',
      );
    }
    changed |= newLine != line;
    newLines.add(newLine);
    deltas.add(newLine.length - line.length);
  }

  // A lone blank current line still gains a fresh marker so Ctrl+/ starts a
  // comment instead of doing nothing.
  if (!changed && !uncomment && lines.length == 1) {
    final newLine = '${lines.first}$marker ';
    return LineCommentToggleResult(
      [newLine],
      [newLine.length - lines.first.length],
    );
  }

  if (!changed) return null;
  return LineCommentToggleResult(newLines, deltas);
}

/// Maps [offset] in the original line block to its position after
/// [toggleLineComments] was applied.
///
/// [blockStart] is the buffer offset of the first line, [blockEnd] the offset
/// just past the last line's text (its line break is not part of the block),
/// and [separators] the line breaks between consecutive [oldLines]. A caret
/// past [blockEnd] shifts by the block's net size change.
///
/// Each preceding line contributes its *new* length plus its separator, so the
/// result is a real buffer offset rather than a sum of deltas. Offsets between
/// the `\r` and `\n` of a CRLF break are snapped to that line's end.
int mapCommentToggleOffset({
  required int offset,
  required int blockStart,
  required int blockEnd,
  required List<String> oldLines,
  required List<String> separators,
  required List<int> deltas,
}) {
  var growth = 0;
  for (final delta in deltas) {
    growth += delta;
  }
  if (offset >= blockEnd) return offset + growth;

  var remaining = offset - blockStart;
  if (remaining < 0) remaining = 0;
  var index = 0;
  while (index < oldLines.length - 1) {
    if (remaining <= oldLines[index].length) break;
    final span = oldLines[index].length + separators[index].length;
    if (remaining < span) {
      // Between the '\r' and '\n' of a CRLF break: treat it as the line end
      // rather than inventing a position inside the new break.
      remaining = oldLines[index].length;
      break;
    }
    remaining -= span;
    index++;
  }

  var shift = 0;
  for (var i = 0; i < index; i++) {
    shift += oldLines[i].length + separators[i].length + deltas[i];
  }
  final newLength = oldLines[index].length + deltas[index];
  var local = remaining + deltas[index];
  if (local < 0) local = 0;
  if (local > newLength) local = newLength;
  return blockStart + shift + local;
}
