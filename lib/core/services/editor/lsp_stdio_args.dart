/// Splits a user-typed command line into argv entries.
///
/// The stdio LSP field is a single text box, so a path with a space in it —
/// `--config "C:/my dir/pyrightconfig.json"` — has to survive the split. A
/// plain `split(' ')` hands the server two broken halves instead of one
/// argument, which is why this parser understands the quoting a shell user
/// would naturally type.
///
/// Supported syntax, kept deliberately small because the field is not a shell:
///
/// * whitespace separates arguments,
/// * `'…'` keeps everything literal inside,
/// * `"…"` keeps everything literal inside except `\"`, `\\` and `\$`,
/// * `\ `, `\"`, `\'` and `\\` escape a single character outside quotes.
///
/// Nothing is expanded: no variables, globs, command substitution or
/// redirection. An unterminated quote does not throw — the remainder becomes
/// the final argument, so a half-typed value still starts the server.
List<String> splitLspStdioArgs(String input) {
  final args = <String>[];
  final current = StringBuffer();
  var inSingle = false;
  var inDouble = false;
  var hasContent = false;
  var escaped = false;

  void flush() {
    if (!hasContent) return;
    args.add(current.toString());
    current.clear();
    hasContent = false;
  }

  for (final rune in input.runes) {
    if (escaped) {
      current.writeCharCode(rune);
      hasContent = true;
      escaped = false;
      continue;
    }

    final char = String.fromCharCode(rune);

    if (inSingle) {
      if (char == "'") {
        inSingle = false;
      } else {
        current.write(char);
        hasContent = true;
      }
      continue;
    }

    if (inDouble) {
      if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inDouble = false;
      } else {
        current.write(char);
        hasContent = true;
      }
      continue;
    }

    if (char == "'" || char == '"') {
      // A quote starts a quoted run even when it follows literal text, which is
      // how `--name=foo-"bar baz"` behaves in a shell.
      hasContent = true;
      if (char == "'") {
        inSingle = true;
      } else {
        inDouble = true;
      }
      continue;
    }

    if (char == r'\') {
      escaped = true;
      hasContent = true;
      continue;
    }

    if (char == ' ' || char == '\t' || char == '\n' || char == '\r') {
      flush();
      continue;
    }

    current.write(char);
    hasContent = true;
  }

  // A trailing backslash is a literal backslash: the user asked for one
  // character, not for the parser to swallow it.
  if (escaped) current.write(r'\');

  flush();

  return args;
}
