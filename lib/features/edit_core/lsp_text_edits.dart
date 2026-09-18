/// Pure helpers for working with LSP results on raw document text.
///
/// Kept free of Flutter/controller dependencies so they can be unit tested.
library;

/// Extracts the identifier characters surrounding [offset].
String symbolAtOffset(String text, int offset) {
  if (text.isEmpty) return '';
  var start = offset.clamp(0, text.length).toInt();
  var end = start;
  bool isWordChar(int codeUnit) =>
      (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
      (codeUnit >= 0x41 && codeUnit <= 0x5A) || // A-Z
      (codeUnit >= 0x61 && codeUnit <= 0x7A) || // a-z
      codeUnit == 0x5F; // _
  while (start > 0 && isWordChar(text.codeUnitAt(start - 1))) {
    start--;
  }
  while (end < text.length && isWordChar(text.codeUnitAt(end))) {
    end++;
  }
  return text.substring(start, end);
}

/// Applies an unordered list of LSP text edits ([List<TextEdit>] JSON maps)
/// to [text] and returns the resulting string.
///
/// Edits are converted to offsets, sorted by descending start position, and
/// applied back-to-front so earlier replacements never invalidate later
/// offsets. Invalid ranges (non-map, out-of-bounds, or start > end) are
/// skipped.
String applyLspTextEdits(String text, List<dynamic> edits) {
  final replacements = <({int start, int end, String text})>[];
  for (final edit in edits.whereType<Map>()) {
    final range = edit['range'];
    if (range is! Map) continue;
    final start = lspPositionToOffset(text, range['start']);
    final end = lspPositionToOffset(text, range['end']);
    if (start == null || end == null || start > end) continue;
    replacements.add((
      start: start,
      end: end,
      text: edit['newText'] is String ? edit['newText'] as String : '',
    ));
  }
  replacements.sort((a, b) => b.start.compareTo(a.start));
  for (final replacement in replacements) {
    text = text.replaceRange(
      replacement.start,
      replacement.end,
      replacement.text,
    );
  }
  return text;
}

/// Converts an LSP `{line, character}` position map to a UTF-16 offset in
/// [text], or `null` when the position is malformed or outside the document.
///
/// Handles `\n` line endings plus `\r\n` documents: a character index beyond
/// a line's content (excluding its CR) is rejected rather than spilling onto
/// the next line.
int? lspPositionToOffset(String text, dynamic position) {
  if (position is! Map) return null;
  final lineValue = position['line'];
  final charValue = position['character'];
  // Type-check before casting: a malformed value must yield null instead of
  // throwing a cast error.
  if (lineValue is! num || charValue is! num) return null;
  final line = lineValue.toInt();
  final character = charValue.toInt();
  if (line < 0 || character < 0) return null;
  var lineStart = 0;
  for (var currentLine = 0; currentLine < line; currentLine++) {
    final lineEnd = text.indexOf('\n', lineStart);
    if (lineEnd < 0) return null;
    lineStart = lineEnd + 1;
  }
  var lineEnd = text.indexOf('\n', lineStart);
  if (lineEnd < 0) lineEnd = text.length;
  if (lineEnd > lineStart && text.codeUnitAt(lineEnd - 1) == 13) lineEnd--;
  if (character > lineEnd - lineStart) return null;
  return lineStart + character;
}
