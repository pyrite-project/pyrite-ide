import 'package:flutter/foundation.dart';

/// Incremental, display-oriented transcript for the interactive REPL.
///
/// The device protocol is handled before this layer. This buffer only turns
/// terminal-like text controls into a stable document that Flutter can lay out
/// and select without a second terminal grid.
class ReplTranscriptController extends ChangeNotifier {
  final List<String> _lines = <String>[''];
  int _ansiState = 0;
  bool _pendingCarriageReturn = false;
  String? _carriageReturnOriginalLine;
  bool _changed = false;

  String get text => _lines.join('\n');

  bool get isEmpty => _lines.length == 1 && _lines.first.isEmpty;

  int get lineCount => _lines.length;

  void append(String data) {
    if (data.isEmpty) return;
    for (final rune in data.runes) {
      _appendRune(rune);
    }
    if (_changed) {
      _changed = false;
      notifyListeners();
    }
  }

  void clear() {
    _lines
      ..clear()
      ..add('');
    _ansiState = 0;
    _pendingCarriageReturn = false;
    _carriageReturnOriginalLine = null;
    notifyListeners();
  }

  void _appendRune(int rune) {
    if (_pendingCarriageReturn) {
      _pendingCarriageReturn = false;
      if (rune == 0x0a) {
        _lines[_lines.length - 1] = _carriageReturnOriginalLine ?? '';
        _carriageReturnOriginalLine = null;
        _lines.add('');
        _changed = true;
        return;
      }
      _carriageReturnOriginalLine = null;
    }

    if (_ansiState != 0) {
      _consumeAnsiRune(rune);
      return;
    }

    switch (rune) {
      case 0x1b: // ESC
        _ansiState = 1;
        return;
      case 0x0a: // LF
        _lines.add('');
        _changed = true;
        return;
      case 0x0d: // CR: wait to distinguish CRLF from a line rewrite.
        if (!_pendingCarriageReturn) {
          _carriageReturnOriginalLine = _lines.last;
        }
        if (_lines.last.isNotEmpty) {
          _lines[_lines.length - 1] = '';
          _changed = true;
        }
        _pendingCarriageReturn = true;
        return;
      case 0x08: // BS
        final current = _lines.last;
        if (current.isNotEmpty) {
          _lines[_lines.length - 1] = String.fromCharCodes(
            current.runes.take(current.runes.length - 1),
          );
          _changed = true;
        }
        return;
      case 0x07: // BEL
      case 0x00: // NUL
        return;
    }

    if (rune >= 0x20 || rune == 0x09) {
      _lines[_lines.length - 1] += String.fromCharCode(rune);
      _changed = true;
    }
  }

  void _consumeAnsiRune(int rune) {
    if (_ansiState == 1) {
      if (rune == 0x5b) {
        _ansiState = 2; // CSI
      } else if (rune == 0x5d) {
        _ansiState = 3; // OSC
      } else {
        _ansiState = 0;
      }
      return;
    }

    if (_ansiState == 2) {
      if (rune >= 0x40 && rune <= 0x7e) _ansiState = 0;
      return;
    }

    // OSC sequences terminate with BEL or ESC followed by '\\'.
    if (rune == 0x07) {
      _ansiState = 0;
    } else if (rune == 0x1b) {
      _ansiState = 4;
    } else if (_ansiState == 4 && rune == 0x5c) {
      _ansiState = 0;
    }
  }
}
