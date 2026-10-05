import 'dart:io' show Platform;

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
///
/// The keys themselves live in [CodeForgeKeyboardShortcuts] inside code_forge
/// so the editor widget owns its own bindings; these are the human-readable
/// spellings of those defaults, and the two must be changed together.
String goToDefinitionShortcutLabel() => 'F12';

String goToImplementationShortcutLabel() =>
    usesCommandShortcut ? 'Cmd+F12' : 'Ctrl+F12';

String findReferencesShortcutLabel() =>
    usesCommandShortcut ? 'Cmd+Shift+F12' : 'Shift+F12';

String renameShortcutLabel() => 'F2';

String toggleBlockCommentShortcutLabel() =>
    usesCommandShortcut ? 'Cmd+Shift+/' : 'Ctrl+Shift+/';

String formatDocumentShortcutLabel() =>
    usesCommandShortcut ? 'Cmd+Shift+F' : 'Shift+Alt+F';

String addCursorShortcutLabel() =>
    usesCommandShortcut ? 'Cmd+Alt+Down' : 'Ctrl+Alt+Down';

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

/// Display names for the keys whose Flutter `keyLabel` is not the name this
/// module uses: either a symbol that cannot be parsed back ("↑", "Page Up"),
/// or a spelling worth pinning down instead of inheriting Flutter's.
///
/// Both directions of the shortcut round-trip read this one table —
/// [_keyLabel] prints these names and [_resolveKey] parses their lowercase
/// form — so the two lists can never drift apart and a recorded shortcut
/// always round-trips.
/// The map is `final`, not `const`: `LogicalKeyboardKey` overrides `==`, which
/// a const map key may not.
final Map<LogicalKeyboardKey, String> _namedKeys = {
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.escape: 'Esc',
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.backspace: 'Backspace',
  LogicalKeyboardKey.delete: 'Delete',
  LogicalKeyboardKey.arrowUp: 'ArrowUp',
  LogicalKeyboardKey.arrowDown: 'ArrowDown',
  LogicalKeyboardKey.arrowLeft: 'ArrowLeft',
  LogicalKeyboardKey.arrowRight: 'ArrowRight',
  LogicalKeyboardKey.home: 'Home',
  LogicalKeyboardKey.end: 'End',
  LogicalKeyboardKey.pageUp: 'PageUp',
  LogicalKeyboardKey.pageDown: 'PageDown',
  LogicalKeyboardKey.insert: 'Insert',
};

/// Spellings [_resolveKey] accepts beyond the lowercase canonical names in
/// [_namedKeys], so shortcuts persisted by older builds keep parsing.
const Map<String, LogicalKeyboardKey> _keyNameAliases = {
  'escape': LogicalKeyboardKey.escape,
  'del': LogicalKeyboardKey.delete,
};

String _keyLabel(LogicalKeyboardKey key) => _namedKeys[key] ?? key.keyLabel;

LogicalKeyboardKey? _resolveKey(String label) {
  final name = label.toLowerCase();
  final alias = _keyNameAliases[name];
  if (alias != null) return alias;
  for (final entry in _namedKeys.entries) {
    if (entry.value.toLowerCase() == name) return entry.key;
  }
  switch (name) {
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
