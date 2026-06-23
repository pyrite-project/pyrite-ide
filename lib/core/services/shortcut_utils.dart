import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

String activatorToString(SingleActivator activator) {
  final parts = <String>[];
  if (activator.control) parts.add('Ctrl');
  if (activator.shift) parts.add('Shift');
  if (activator.alt) parts.add('Alt');
  if (activator.meta) parts.add('Meta');
  parts.add(_keyLabel(activator.trigger));
  return parts.join('+');
}

SingleActivator stringToActivator(String str) {
  final parts = str.split('+').map((s) => s.trim()).toList();
  final control = parts.remove('Ctrl') || parts.remove('ctrl');
  final shift = parts.remove('Shift') || parts.remove('shift');
  final alt = parts.remove('Alt') || parts.remove('alt');
  final meta = parts.remove('Meta') || parts.remove('meta') || parts.remove('Cmd') || parts.remove('cmd');
  final keyLabel = parts.isNotEmpty ? parts.last : 'enter';
  final key = _resolveKey(keyLabel);
  return SingleActivator(key, control: control, shift: shift, alt: alt, meta: meta);
}

String _keyLabel(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.enter) return 'Enter';
  if (key == LogicalKeyboardKey.escape) return 'Esc';
  if (key == LogicalKeyboardKey.space) return 'Space';
  if (key == LogicalKeyboardKey.tab) return 'Tab';
  if (key == LogicalKeyboardKey.backspace) return 'Backspace';
  if (key == LogicalKeyboardKey.delete) return 'Delete';
  return key.keyLabel;
}

LogicalKeyboardKey _resolveKey(String label) {
  switch (label.toLowerCase()) {
    case 'enter': return LogicalKeyboardKey.enter;
    case 'escape': case 'esc': return LogicalKeyboardKey.escape;
    case 'space': return LogicalKeyboardKey.space;
    case 'tab': return LogicalKeyboardKey.tab;
    case 'backspace': return LogicalKeyboardKey.backspace;
    case 'delete': case 'del': return LogicalKeyboardKey.delete;
    case 'a': return LogicalKeyboardKey.keyA;
    case 'b': return LogicalKeyboardKey.keyB;
    case 'c': return LogicalKeyboardKey.keyC;
    case 'd': return LogicalKeyboardKey.keyD;
    case 'e': return LogicalKeyboardKey.keyE;
    case 'f': return LogicalKeyboardKey.keyF;
    case 'g': return LogicalKeyboardKey.keyG;
    case 'h': return LogicalKeyboardKey.keyH;
    case 'i': return LogicalKeyboardKey.keyI;
    case 'j': return LogicalKeyboardKey.keyJ;
    case 'k': return LogicalKeyboardKey.keyK;
    case 'l': return LogicalKeyboardKey.keyL;
    case 'm': return LogicalKeyboardKey.keyM;
    case 'n': return LogicalKeyboardKey.keyN;
    case 'o': return LogicalKeyboardKey.keyO;
    case 'p': return LogicalKeyboardKey.keyP;
    case 'q': return LogicalKeyboardKey.keyQ;
    case 'r': return LogicalKeyboardKey.keyR;
    case 's': return LogicalKeyboardKey.keyS;
    case 't': return LogicalKeyboardKey.keyT;
    case 'u': return LogicalKeyboardKey.keyU;
    case 'v': return LogicalKeyboardKey.keyV;
    case 'w': return LogicalKeyboardKey.keyW;
    case 'x': return LogicalKeyboardKey.keyX;
    case 'y': return LogicalKeyboardKey.keyY;
    case 'z': return LogicalKeyboardKey.keyZ;
    case '0': return LogicalKeyboardKey.digit0;
    case '1': return LogicalKeyboardKey.digit1;
    case '2': return LogicalKeyboardKey.digit2;
    case '3': return LogicalKeyboardKey.digit3;
    case '4': return LogicalKeyboardKey.digit4;
    case '5': return LogicalKeyboardKey.digit5;
    case '6': return LogicalKeyboardKey.digit6;
    case '7': return LogicalKeyboardKey.digit7;
    case '8': return LogicalKeyboardKey.digit8;
    case '9': return LogicalKeyboardKey.digit9;
    case 'f1': return LogicalKeyboardKey.f1;
    case 'f2': return LogicalKeyboardKey.f2;
    case 'f3': return LogicalKeyboardKey.f3;
    case 'f4': return LogicalKeyboardKey.f4;
    case 'f5': return LogicalKeyboardKey.f5;
    case 'f6': return LogicalKeyboardKey.f6;
    case 'f7': return LogicalKeyboardKey.f7;
    case 'f8': return LogicalKeyboardKey.f8;
    case 'f9': return LogicalKeyboardKey.f9;
    case 'f10': return LogicalKeyboardKey.f10;
    case 'f11': return LogicalKeyboardKey.f11;
    case 'f12': return LogicalKeyboardKey.f12;
    default: return LogicalKeyboardKey.enter;
  }
}


