/// Expansion of LSP snippet syntax into plain text, plus where the caret should
/// land afterwards.
///
/// A completion with `insertTextFormat: 2` carries placeholders like
/// `foo(${1:a}, ${2:b})$0`. Inserted verbatim, the user gets literal `${1:a}`
/// in the REPL and a MicroPython `SyntaxError` for their trouble. The REPL used
/// to work around that by inserting only the label, which is worse in a
/// different way: the call comes out with no arguments at all, so the user has
/// to retype the exact shape they were just offered.
///
/// So the snippet is expanded instead: placeholders are replaced by their
/// default text (or an empty string when they have none), and the caret is
/// placed on the first placeholder the user is meant to type over.
///
/// This is deliberately not a full snippet engine — no mirroring, no linked
/// tabstops, no transformation. Those matter in a rich text editor with a
/// selection widget; the REPL is a Python console where the defaults carry the
/// shape of the call and typing over the first argument is the whole
/// interaction. What matters here is that the inserted text is valid Python.
library;

/// A snippet reduced to what the input needs: the text to insert, and the
/// range inside it the caret should select afterwards.
typedef ResolvedSnippet = ({String text, int selectionStart, int selectionEnd});

/// Expands [snippet] into a [ResolvedSnippet].
///
/// Returns null when the snippet contains no placeholder, which means there is
/// nothing to select afterwards and the caller should insert the text as-is.
ResolvedSnippet? expandLspSnippet(String snippet) {
  final buffer = StringBuffer();
  var selectionStart = -1;
  var selectionEnd = -1;
  var i = 0;

  while (i < snippet.length) {
    final char = snippet[i];

    // `\$` escapes a literal `$`, so `\$name` inserts `$name` rather than being
    // read as a placeholder.
    if (char == r'\' && i + 1 < snippet.length && snippet[i + 1] == r'$') {
      buffer.write(r'$');
      i += 2;
      continue;
    }

    final placeholder = char == r'$' ? _readPlaceholder(snippet, i + 1) : null;
    if (placeholder == null) {
      buffer.write(char);
      i++;
      continue;
    }

    if (selectionStart < 0) {
      selectionStart = buffer.length;
      selectionEnd = selectionStart + placeholder.text.length;
    }
    buffer.write(placeholder.text);
    i = placeholder.next;
  }

  if (selectionStart < 0) return null;
  return (
    text: buffer.toString(),
    selectionStart: selectionStart,
    selectionEnd: selectionEnd,
  );
}

/// One placeholder: its default text, and the index just past it.
typedef _Placeholder = ({String text, int next});

/// Reads the placeholder starting at [start], which is the index just after a
/// `$`.
///
/// Returns null when there is no placeholder there — a bare `$` in the middle of
/// a string, or a malformed `${` — so the caller emits the `$` as literal text
/// rather than dropping the rest of the snippet.
_Placeholder? _readPlaceholder(String snippet, int start) {
  if (start >= snippet.length) return null;

  if (snippet[start] == '{') {
    final close = _matchingBrace(snippet, start);
    if (close == null) return null;
    final body = snippet.substring(start + 1, close);
    // The default text may itself contain an escaped colon; only the first
    // unescaped one separates it from the placeholder name.
    final colon = _unescapedIndexOf(body, ':');
    return (
      text: colon == null ? '' : body.substring(colon + 1),
      next: close + 1,
    );
  }

  // The bare `$name` / `$0` form has no default text, so it expands to nothing.
  // `$0` in particular is the final caret position every snippet ends with, and
  // leaving it literal would put `$0` into the user's Python.
  if (!_isNameStart(snippet[start]) && !_isDigit(snippet[start])) return null;
  var cursor = start;
  while (cursor < snippet.length && _isNamePart(snippet[cursor])) {
    cursor++;
  }
  return (text: '', next: cursor);
}

bool _isNameStart(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 95;
}

bool _isNamePart(String c) => _isNameStart(c) || _isDigit(c);

bool _isDigit(String c) {
  final code = c.codeUnitAt(0);
  return code >= 48 && code <= 57;
}

/// Index of the `}` matching the `{` at [open], honouring nesting and
/// backslash escapes. Null when the brace is never closed.
int? _matchingBrace(String value, int open) {
  var depth = 0;
  for (var i = open; i < value.length; i++) {
    if (value[i] == r'\' && i + 1 < value.length && value[i + 1] == r'$') {
      i++;
      continue;
    }
    if (value[i] == '{') depth++;
    if (value[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

/// Index of the first [target] in [value] that is not backslash-escaped.
int? _unescapedIndexOf(String value, String target) {
  for (var i = 0; i < value.length; i++) {
    if (value[i] == r'\' && i + 1 < value.length) {
      i++;
      continue;
    }
    if (value[i] == target) return i;
  }
  return null;
}
