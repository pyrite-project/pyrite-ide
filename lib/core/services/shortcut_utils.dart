import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether the platform's primary editor modifier is Command (Apple platforms)
/// instead of Control.
bool get usesCommandShortcut => Platform.isMacOS || Platform.isIOS;

/// Activators that open the editor find bar on this platform.
///
/// Uses Cmd on Apple platforms and Ctrl elsewhere so the same physical
/// shortcut position works consistently.
List<SingleActivator> findActivators() => [
  if (usesCommandShortcut)
    const SingleActivator(LogicalKeyboardKey.keyF, meta: true)
  else
    const SingleActivator(LogicalKeyboardKey.keyF, control: true),
];

/// Activators that open the editor find-and-replace bar.
///
/// On Apple platforms Alt is added so Cmd+H keeps the conventional
/// "hide window" system shortcut.
List<SingleActivator> replaceActivators() => [
  if (usesCommandShortcut)
    const SingleActivator(LogicalKeyboardKey.keyH, meta: true, alt: true)
  else
    const SingleActivator(LogicalKeyboardKey.keyH, control: true),
];

/// Activators that toggle the line comment.
List<SingleActivator> toggleCommentActivators() => [
  const SingleActivator(LogicalKeyboardKey.slash, control: true),
  const SingleActivator(LogicalKeyboardKey.slash, meta: true),
];

String findShortcutLabel() => usesCommandShortcut ? 'Cmd+F' : 'Ctrl+F';

String replaceShortcutLabel() => usesCommandShortcut ? 'Cmd+Alt+H' : 'Ctrl+H';

String toggleCommentShortcutLabel() => usesCommandShortcut ? 'Cmd+/' : 'Ctrl+/';

/// Labels for the editor shortcuts that are registered inline in
/// `EditCore.build` rather than through [CodeForgeKeyboardShortcuts].
///
/// The editor context menu shows these in the description column, so keeping
/// them here means a binding and its label change together. Items with no
/// keyboard shortcut pass an empty description rather than a placeholder, which
/// used to render the literal text "LSP" where a key should be.
String goToDefinitionShortcutLabel() => 'F12';

String renameShortcutLabel() => 'F2';

String activatorToString(SingleActivator activator) {
  final parts = <String>[];
  if (activator.control) parts.add('Ctrl');
  if (activator.shift) parts.add('Shift');
  if (activator.alt) parts.add('Alt');
  if (activator.meta) parts.add('Command');
  parts.add(_keyLabel(activator.trigger));
  return parts.join('+');
}

/// Parses a recorded shortcut string such as `Ctrl+Shift+S`.
///
/// Returns null when the key name is not recognised. This used to fall back to
/// [LogicalKeyboardKey.enter] silently, which meant a shortcut recorded on a
/// key outside the hardcoded list below (F13, an arrow key, a media key)
/// quietly became Enter and fired on every confirm.
SingleActivator? stringToActivator(String str) {
  final parts = str.split('+').map((s) => s.trim()).toList();
  final control = parts.remove('Ctrl') || parts.remove('ctrl');
  final shift = parts.remove('Shift') || parts.remove('shift');
  final alt = parts.remove('Alt') || parts.remove('alt');
  final meta =
      parts.remove('Meta') ||
      parts.remove('meta') ||
      parts.remove('Cmd') ||
      parts.remove('cmd') ||
      parts.remove('Command') ||
      parts.remove('command');
  if (parts.isEmpty) {
    debugPrint(
      'shortcut_utils: ignored shortcut "$str" because it names no key',
    );
    return null;
  }
  final key = _resolveKey(parts.last);
  if (key == null) {
    debugPrint(
      'shortcut_utils: ignored shortcut "$str" because '
      '"${parts.last}" is not a known key name',
    );
    return null;
  }
  return SingleActivator(
    key,
    control: control,
    shift: shift,
    alt: alt,
    meta: meta,
  );
}

String _keyLabel(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.enter) return 'Enter';
  if (key == LogicalKeyboardKey.escape) return 'Esc';
  if (key == LogicalKeyboardKey.space) return 'Space';
  if (key == LogicalKeyboardKey.tab) return 'Tab';
  if (key == LogicalKeyboardKey.backspace) return 'Backspace';
  if (key == LogicalKeyboardKey.delete) return 'Delete';
  // Flutter's keyLabel for the navigation keys is a symbol ("↑", "Page Up"),
  // which _resolveKey cannot parse back. Spell them out so a recorded
  // shortcut round-trips.
  if (key == LogicalKeyboardKey.arrowUp) return 'ArrowUp';
  if (key == LogicalKeyboardKey.arrowDown) return 'ArrowDown';
  if (key == LogicalKeyboardKey.arrowLeft) return 'ArrowLeft';
  if (key == LogicalKeyboardKey.arrowRight) return 'ArrowRight';
  if (key == LogicalKeyboardKey.home) return 'Home';
  if (key == LogicalKeyboardKey.end) return 'End';
  if (key == LogicalKeyboardKey.pageUp) return 'PageUp';
  if (key == LogicalKeyboardKey.pageDown) return 'PageDown';
  if (key == LogicalKeyboardKey.insert) return 'Insert';
  return key.keyLabel;
}

LogicalKeyboardKey? _resolveKey(String label) {
  switch (label.toLowerCase()) {
    case 'enter':
      return LogicalKeyboardKey.enter;
    case 'escape':
    case 'esc':
      return LogicalKeyboardKey.escape;
    case 'space':
      return LogicalKeyboardKey.space;
    case 'tab':
      return LogicalKeyboardKey.tab;
    case 'backspace':
      return LogicalKeyboardKey.backspace;
    case 'delete':
    case 'del':
      return LogicalKeyboardKey.delete;
    case 'arrowup':
      return LogicalKeyboardKey.arrowUp;
    case 'arrowdown':
      return LogicalKeyboardKey.arrowDown;
    case 'arrowleft':
      return LogicalKeyboardKey.arrowLeft;
    case 'arrowright':
      return LogicalKeyboardKey.arrowRight;
    case 'home':
      return LogicalKeyboardKey.home;
    case 'end':
      return LogicalKeyboardKey.end;
    case 'pageup':
      return LogicalKeyboardKey.pageUp;
    case 'pagedown':
      return LogicalKeyboardKey.pageDown;
    case 'insert':
      return LogicalKeyboardKey.insert;
    case 'a':
      return LogicalKeyboardKey.keyA;
    case 'b':
      return LogicalKeyboardKey.keyB;
    case 'c':
      return LogicalKeyboardKey.keyC;
    case 'd':
      return LogicalKeyboardKey.keyD;
    case 'e':
      return LogicalKeyboardKey.keyE;
    case 'f':
      return LogicalKeyboardKey.keyF;
    case 'g':
      return LogicalKeyboardKey.keyG;
    case 'h':
      return LogicalKeyboardKey.keyH;
    case 'i':
      return LogicalKeyboardKey.keyI;
    case 'j':
      return LogicalKeyboardKey.keyJ;
    case 'k':
      return LogicalKeyboardKey.keyK;
    case 'l':
      return LogicalKeyboardKey.keyL;
    case 'm':
      return LogicalKeyboardKey.keyM;
    case 'n':
      return LogicalKeyboardKey.keyN;
    case 'o':
      return LogicalKeyboardKey.keyO;
    case 'p':
      return LogicalKeyboardKey.keyP;
    case 'q':
      return LogicalKeyboardKey.keyQ;
    case 'r':
      return LogicalKeyboardKey.keyR;
    case 's':
      return LogicalKeyboardKey.keyS;
    case 't':
      return LogicalKeyboardKey.keyT;
    case 'u':
      return LogicalKeyboardKey.keyU;
    case 'v':
      return LogicalKeyboardKey.keyV;
    case 'w':
      return LogicalKeyboardKey.keyW;
    case 'x':
      return LogicalKeyboardKey.keyX;
    case 'y':
      return LogicalKeyboardKey.keyY;
    case 'z':
      return LogicalKeyboardKey.keyZ;
    case '0':
      return LogicalKeyboardKey.digit0;
    case '1':
      return LogicalKeyboardKey.digit1;
    case '2':
      return LogicalKeyboardKey.digit2;
    case '3':
      return LogicalKeyboardKey.digit3;
    case '4':
      return LogicalKeyboardKey.digit4;
    case '5':
      return LogicalKeyboardKey.digit5;
    case '6':
      return LogicalKeyboardKey.digit6;
    case '7':
      return LogicalKeyboardKey.digit7;
    case '8':
      return LogicalKeyboardKey.digit8;
    case '9':
      return LogicalKeyboardKey.digit9;
    case 'f1':
      return LogicalKeyboardKey.f1;
    case 'f2':
      return LogicalKeyboardKey.f2;
    case 'f3':
      return LogicalKeyboardKey.f3;
    case 'f4':
      return LogicalKeyboardKey.f4;
    case 'f5':
      return LogicalKeyboardKey.f5;
    case 'f6':
      return LogicalKeyboardKey.f6;
    case 'f7':
      return LogicalKeyboardKey.f7;
    case 'f8':
      return LogicalKeyboardKey.f8;
    case 'f9':
      return LogicalKeyboardKey.f9;
    case 'f10':
      return LogicalKeyboardKey.f10;
    case 'f11':
      return LogicalKeyboardKey.f11;
    case 'f12':
      return LogicalKeyboardKey.f12;
    default:
      return null;
  }
}
