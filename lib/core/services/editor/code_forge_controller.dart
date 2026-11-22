import 'dart:convert';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/services.dart';

int indentationBackspaceCount(String beforeCaret, {required int tabSize}) {
  final spaces = RegExp(r' +$').firstMatch(beforeCaret)?.group(0)!.length ?? 0;
  if (spaces > 0) return spaces % tabSize == 0 ? tabSize : 1;
  final tabs = RegExp(r'\t+$').firstMatch(beforeCaret)?.group(0)!.length ?? 1;
  return tabs.clamp(1, tabSize);
}

class PyriteCodeForgeController extends CodeForgeController {
  PyriteCodeForgeController({super.lspConfig});

  /// Binds an opened path without letting a strict UTF-8 read abort the open.
  ///
  /// The engine setter records the path and then re-reads the file as strict
  /// UTF-8. Callers that decoded the bytes themselves (encoding picker, binary
  /// fallback, headless restore) install the buffer immediately after this
  /// assignment, so the second read only throws for content they already
  /// handled. When nothing follows — the editor widget assigning the path on
  /// its own — keep a malformed-tolerant decode and mark the buffer read-only
  /// so bytes that cannot be re-encoded are never written back.
  ///
  /// `File.readAsString` reports a decoding failure as [FileSystemException],
  /// so the fallback distinguishes it from a genuinely unreadable path by
  /// reading the bytes again: that read rethrows when the file cannot be
  /// opened at all.
  @override
  set openedFile(String? file) {
    try {
      super.openedFile = file;
    } on FileSystemException {
      if (file == null) rethrow;
      final List<int> bytes = File(file).readAsBytesSync();
      text = utf8.decode(bytes, allowMalformed: true);
      readOnly = true;
    }
  }

  @override
  void backspace() {
    final caret = selection.extentOffset;
    if (readOnly || isComposingActive || !selection.isCollapsed || caret == 0) {
      super.backspace();
      return;
    }

    final lineStart = getLineStartOffset(getLineAtOffset(caret));
    final beforeCaret = text.substring(lineStart, caret);
    if (!RegExp(r'^[ \t]+$').hasMatch(beforeCaret)) {
      super.backspace();
      return;
    }

    final count = indentationBackspaceCount(beforeCaret, tabSize: tabSize);
    final start = caret - count;
    replaceRange(start, caret, '');
    setSelectionSilently(TextSelection.collapsed(offset: start));
  }
}
