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
/// the prompt is searched for anywhere in the text, but it must be followed by
/// the end of the chunk or by whitespace — `>>>` inside prose or a string is
/// not a prompt.
bool showsWebReplPrompt(String text) {
  final index = text.lastIndexOf('>>>');
  if (index == -1) return false;
  final after = index + 3;
  if (after == text.length) return true;
  final next = text.codeUnitAt(after);
  return next == 0x20 || next == 0x0a || next == 0x0d || next == 0x09;
}
