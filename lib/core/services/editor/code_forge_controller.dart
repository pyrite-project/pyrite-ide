import 'package:code_forge/code_forge.dart';
import 'package:flutter/services.dart';

int indentationBackspaceCount(String beforeCaret, {required int tabSize}) {
  final spaces = RegExp(r' +$').firstMatch(beforeCaret)?.group(0)!.length ?? 0;
  if (spaces > 0) return spaces % tabSize == 0 ? tabSize : spaces % tabSize;
  final tabs = RegExp(r'\t+$').firstMatch(beforeCaret)?.group(0)!.length ?? 1;
  return tabs.clamp(1, tabSize);
}

class PyriteCodeForgeController extends CodeForgeController {
  PyriteCodeForgeController({super.lspConfig});

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
