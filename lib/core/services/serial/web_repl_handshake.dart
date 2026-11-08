/// Recognising the two WebREPL handshake prompts.
///
/// The WebREPL transport gives no framing for the interactive console: the
/// device just prints text, so the client has to recognise the password
/// prompt and the first REPL prompt inside ordinary output. The previous
/// implementation used `contains('OK')`, which fires on any echo that happens
/// to contain those two letters — `os.remove('x')` printing `OK`, a filename,
/// a docstring — and marks the session connected while the device is still
/// asking for a password.
///
/// These helpers match the prompt shapes instead of substrings:
///
/// * the password prompt is the word `Password:` at the start of a line,
/// * the REPL prompt is `>>> ` (or `>>>` at the very end of what has arrived
///   so far, because the trailing space can land in the next websocket frame).
library;

import 'dart:convert';

/// True when [text] contains the WebREPL password prompt.
bool awaitsWebReplPassword(String text) {
  for (final line in const LineSplitter().convert(text)) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('Password:')) return true;
  }
  return false;
}

/// True when [text] shows the interactive REPL prompt `>>>`.
///
/// A line may carry output before the prompt (`MPY: soft reboot\r\n>>> `), so
/// the prompt is searched for anywhere in the text, but it has to start a line
/// and be followed by the end of the chunk or by whitespace. Both halves of that
/// rule matter: `>>>` inside prose or a string is not a prompt, and neither is
/// the one in an echoed command such as `>>> print(">>>")` — the prompt itself
/// is the occurrence at the start of the line, which the previous
/// last-occurrence-wins search skipped straight past.
bool showsWebReplPrompt(String text) {
  var searchFrom = text.length;
  while (searchFrom > 0) {
    final index = text.lastIndexOf('>>>', searchFrom - 1);
    if (index < 0) return false;
    searchFrom = index;
    if (index > 0) {
      final before = text.codeUnitAt(index - 1);
      if (before != 0x0a && before != 0x0d) continue;
    }
    final after = index + 3;
    if (after == text.length) return true;
    final next = text.codeUnitAt(after);
    if (next == 0x20 || next == 0x0a || next == 0x0d || next == 0x09) {
      return true;
    }
  }
  return false;
}
