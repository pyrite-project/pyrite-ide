import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/services/editor/repl_completion_controller.dart';

enum ReplInteractionMode {
  unknown,
  prompt,
  continuation,
  submitting,
  passthrough,
}

class ReplInputController extends ChangeNotifier {
  ReplInputController() {
    text.addListener(_onTextChanged);
  }

  final TextEditingController text = TextEditingController();
  final List<String> _history = <String>[];
  ReplInteractionMode _mode = ReplInteractionMode.unknown;
  int? _historyIndex;
  String _historyDraft = '';
  bool _draftInHistory = false;
  bool _restoringHistory = false;

  ReplInteractionMode get mode => _mode;
  bool get isInlineEditable =>
      _mode == ReplInteractionMode.prompt ||
      _mode == ReplInteractionMode.continuation;
  bool get hasVisibleInput =>
      isInlineEditable || _mode == ReplInteractionMode.passthrough;

  void setMode(ReplInteractionMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  void reset() {
    _mode = ReplInteractionMode.unknown;
    _historyIndex = null;
    _historyDraft = '';
    _draftInHistory = false;
    text.clear();
    notifyListeners();
  }

  String? takeSubmission() {
    final value = text.text;
    if (value.trim().isEmpty) return null;
    _removeDraftHistory();
    if (_history.isEmpty || _history.last != value) {
      _history.add(value);
      if (_history.length > 500) _history.removeAt(0);
    }
    _historyIndex = null;
    _historyDraft = '';
    text.clear();
    _mode = ReplInteractionMode.submitting;
    notifyListeners();
    return value;
  }

  bool showPreviousHistory() => _moveHistory(-1);

  bool showNextHistory() => _moveHistory(1);

  void insert(String value) {
    final selection = text.selection;
    final start = selection.start < 0 ? text.text.length : selection.start;
    final end = selection.end < 0 ? start : selection.end;
    text.value = text.value.copyWith(
      text: '${text.text.substring(0, start)}$value${text.text.substring(end)}',
      selection: TextSelection.collapsed(offset: start + value.length),
      composing: TextRange.empty,
    );
  }

  void applyCompletion(ReplCompletionItem item) {
    final start = item.replaceStart.clamp(0, text.text.length);
    final end = item.replaceEnd.clamp(start, text.text.length);
    final nextText = text.text.replaceRange(start, end, item.insertText);
    _restoringHistory = true;
    text.value = text.value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(
        offset: start + item.insertText.length,
      ),
      composing: TextRange.empty,
    );
    _restoringHistory = false;
  }

  bool deleteIndentationUnit({int width = 4}) {
    final selection = text.selection;
    if (!selection.isCollapsed || selection.baseOffset <= 0) return false;
    final offset = selection.baseOffset.clamp(0, text.text.length);
    final lineStart = text.text.lastIndexOf('\n', offset - 1) + 1;
    final prefix = text.text.substring(lineStart, offset);
    if (prefix.isEmpty || prefix.trim().isNotEmpty) return false;

    var start = offset;
    if (text.text[start - 1] == '\t') {
      start--;
    } else {
      var removed = 0;
      while (start > lineStart &&
          removed < width &&
          text.text[start - 1] == ' ') {
        start--;
        removed++;
      }
      if (removed == 0) return false;
    }
    text.value = text.value.copyWith(
      text: text.text.replaceRange(start, offset, ''),
      selection: TextSelection.collapsed(offset: start),
      composing: TextRange.empty,
    );
    return true;
  }

  bool get canSubmit {
    final source = text.text;
    if (source.trim().isEmpty) return false;
    final stripped = source.trimRight();
    if (stripped.endsWith(':') || stripped.endsWith('\\')) return false;
    var round = 0;
    var square = 0;
    var curly = 0;
    var quote = '';
    var triple = false;
    var escaped = false;
    var comment = false;
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (comment) {
        if (char == '\n') comment = false;
        continue;
      }
      if (quote.isNotEmpty) {
        if (triple && source.startsWith('$quote$quote$quote', i)) {
          quote = '';
          triple = false;
          i += 2;
          continue;
        }
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (!triple && char == quote) {
          quote = '';
        }
        continue;
      }
      if (char == '#') {
        comment = true;
        continue;
      }
      if (char == "'" || char == '"') {
        quote = char;
        triple = source.startsWith('$char$char$char', i);
        if (triple) i += 2;
      } else if (char == '(') {
        round++;
      } else if (char == ')') {
        round--;
      } else if (char == '[') {
        square++;
      } else if (char == ']') {
        square--;
      } else if (char == '{') {
        curly++;
      } else if (char == '}') {
        curly--;
      }
    }
    if (quote.isNotEmpty || round > 0 || square > 0 || curly > 0) return false;
    final firstLine = source
        .split('\n')
        .map((line) => line.trim())
        .firstWhere(
          (line) => line.isNotEmpty && !line.startsWith('#'),
          orElse: () => '',
        );
    final compound = RegExp(
      r'^(?:async\s+)?(?:if|while|for|with|try|def|class)\b',
    ).hasMatch(firstLine);
    if (compound) {
      final withoutIndent = source.replaceAll(RegExp(r'[ \t]'), '');
      if (!withoutIndent.endsWith('\n\n')) return false;
    }
    return true;
  }

  bool handleEnter() {
    if (canSubmit) return true;
    final selection = text.selection;
    final offset = selection.baseOffset < 0
        ? text.text.length
        : selection.baseOffset;
    final atEnd = selection.isCollapsed && offset == text.text.length;
    final currentLine = text.text.substring(0, offset).split('\n').last;
    if (atEnd && currentLine.trim().isEmpty && text.text.contains('\n')) {
      final trimmed = text.text.replaceFirst(RegExp(r'[ \t]+$'), '');
      text.value = TextEditingValue(
        text: '$trimmed\n',
        selection: TextSelection.collapsed(offset: trimmed.length + 1),
      );
      if (canSubmit) return true;
    }
    insertIndentedNewline();
    return false;
  }

  void insertIndentedNewline() {
    final offset = text.selection.baseOffset < 0
        ? text.text.length
        : text.selection.baseOffset;
    final before = text.text.substring(0, offset);
    final line = before.split('\n').last;
    final indent = RegExp(r'^\s*').firstMatch(line)?.group(0) ?? '';
    final extra = line.trimRight().endsWith(':') ? '    ' : '';
    insert('\n$indent$extra');
  }

  @override
  void dispose() {
    text.removeListener(_onTextChanged);
    text.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!_restoringHistory) {
      _historyIndex = null;
      _removeDraftHistory();
    }
    notifyListeners();
  }

  bool _moveHistory(int direction) {
    if (_history.isEmpty || text.selection.isCollapsed == false) return false;
    final rawOffset = text.selection.baseOffset;
    final offset = rawOffset < 0
        ? text.text.length
        : rawOffset.clamp(0, text.text.length);
    final lineStart = offset == 0
        ? 0
        : text.text.lastIndexOf('\n', offset - 1) + 1;
    final lineEnd = text.text.indexOf('\n', offset);
    final end = lineEnd == -1 ? text.text.length : lineEnd;
    if (text.text.contains('\n') &&
        ((direction < 0 && offset != lineStart) ||
            (direction > 0 && offset != end))) {
      return false;
    }
    if (_historyIndex == null) {
      if (direction > 0) return false;
      _historyDraft = text.text;
      _ensureDraftHistory();
      _historyIndex = _history.length > 1 ? _history.length - 2 : 0;
    } else {
      final next = _historyIndex! + direction;
      if (next < 0 || next >= _history.length) return false;
      _historyIndex = next;
    }

    final value = _history[_historyIndex!];
    _restoringHistory = true;
    text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(
        offset: _draftInHistory && _historyIndex == _history.length - 1
            ? value.length
            : direction < 0
            ? value.length
            : 0,
      ),
    );
    _restoringHistory = false;
    notifyListeners();
    return true;
  }

  void _ensureDraftHistory() {
    if (_draftInHistory) return;
    if (_history.length >= 500) _history.removeAt(0);
    _history.add(_historyDraft);
    _draftInHistory = true;
  }

  void _removeDraftHistory() {
    if (!_draftInHistory) return;
    if (_history.isNotEmpty) _history.removeLast();
    _draftInHistory = false;
  }
}

String formatReplSubmissionEcho(String source) {
  final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  if (lines.isEmpty) return '\r\n';
  final echo = StringBuffer(lines.first);
  for (final line in lines.skip(1)) {
    echo.write('\r\n... $line');
  }
  echo.write('\r\n');
  return echo.toString();
}

class ReplPromptTracker {
  ReplPromptTracker({required this.onMode});

  final void Function(ReplInteractionMode mode) onMode;
  String _tail = '';
  String _ansiPending = '';

  void add(String data) {
    final scan = _stripAnsi('$_ansiPending$data');
    _ansiPending = scan.pending;
    final normalized =
        '$_tail'
        '${scan.visible.replaceAll('\r\n', '\n').replaceAll('\r', '\n')}';
    if (RegExp(r'(?:^|\n)>>> ?$').hasMatch(normalized)) {
      _tail = _suffix(normalized);
      onMode(ReplInteractionMode.prompt);
      return;
    }
    if (RegExp(r'(?:^|\n)\.\.\. ?$').hasMatch(normalized)) {
      _tail = _suffix(normalized);
      onMode(ReplInteractionMode.continuation);
      return;
    }
    _tail = _suffix(normalized);
  }

  void reset() {
    _tail = '';
    _ansiPending = '';
    onMode(ReplInteractionMode.unknown);
  }

  String _suffix(String value) =>
      value.length <= 32 ? value : value.substring(value.length - 32);

  _AnsiScanResult _stripAnsi(String value) {
    final visible = StringBuffer();
    var state = 0;
    var pendingStart = -1;
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      if (state == 0) {
        if (code == 0x1b) {
          state = 1;
          pendingStart = i;
        } else {
          visible.writeCharCode(code);
        }
        continue;
      }
      if (state == 1) {
        if (code == 0x5b) {
          state = 2;
        } else if (code == 0x5d) {
          state = 3;
        } else {
          state = 0;
          pendingStart = -1;
        }
        continue;
      }
      if (state == 2) {
        if (code >= 0x40 && code <= 0x7e) {
          state = 0;
          pendingStart = -1;
        }
        continue;
      }
      if (state == 3) {
        if (code == 0x07) {
          state = 0;
          pendingStart = -1;
        } else if (code == 0x1b) {
          state = 4;
        }
        continue;
      }
      if (code == 0x5c) {
        state = 0;
        pendingStart = -1;
      } else {
        state = 3;
      }
    }
    return _AnsiScanResult(
      visible: visible.toString(),
      pending: pendingStart < 0 ? '' : value.substring(pendingStart),
    );
  }
}

class _AnsiScanResult {
  const _AnsiScanResult({required this.visible, required this.pending});

  final String visible;
  final String pending;
}
