import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';

/// Inbound frame the host sends when a captured editor key is pressed.
const String editorKeyEventCommand = 'ide.editor.key';

/// How long the host waits for a plugin to answer a captured key.
///
/// The press is already suppressed at this point, so the window is short: a
/// plugin that cannot answer in time simply loses the key instead of freezing
/// the editor.
const Duration editorKeyReplyTimeout = Duration(milliseconds: 300);

/// Turns a Flutter key label into the canonical capture name.
///
/// Mirrors `pyrite_sdk.api.editor.keys.normalize_key_name` so a plugin can
/// write `"tab"` / `"escape"` / `"arrowDown"` regardless of the platform.
/// `"Tab"` → `"tab"`, `"Arrow Down"` → `"arrowDown"`, `"A"` → `"a"`.
String normalizeEditorKeyName(String label) {
  final parts = label
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '';
  final head = parts.first;
  if (parts.length == 1 && head.length == 1) return head.toLowerCase();
  final buffer = StringBuffer(head.toLowerCase());
  for (final part in parts.skip(1)) {
    if (part.isEmpty) continue;
    buffer
      ..write(part.substring(0, 1).toUpperCase())
      ..write(part.substring(1).toLowerCase());
  }
  return buffer.toString();
}

/// The capture name of [event], e.g. `"tab"`.
String editorKeyEventName(KeyEvent event) =>
    normalizeEditorKeyName(event.logicalKey.keyLabel);

/// One plugin session's set of hijacked keys.
class EditorKeyCapture {
  EditorKeyCapture({
    required this.pluginId,
    required this.sessionId,
    required this.manager,
  });

  final String pluginId;
  final String sessionId;
  final PluginRunManager manager;
  final Set<String> keys = <String>{};

  bool get isEmpty => keys.isEmpty;
}

/// Registry of editor keys a plugin has taken over.
///
/// A plugin captures a key only while it owns something on screen — an inline
/// (FIM) completion, for example — and releases it as soon as it does not.
/// While a key is captured the editor's own action is suppressed and every
/// press is forwarded to the owning plugin, which answers whether it consumed
/// it.
class EditorKeyCaptureRegistry extends ChangeNotifier {
  final Map<String, EditorKeyCapture> _bySession = <String, EditorKeyCapture>{};

  /// True when any plugin currently owns a key.
  bool get hasCaptures => _bySession.isNotEmpty;

  /// Registers [keys] for the plugin session behind [manager].
  void capture(PluginRunManager manager, Iterable<String> keys) {
    if (keys.isEmpty) return;
    final entry = _bySession.putIfAbsent(
      manager.sessionId,
      () => EditorKeyCapture(
        pluginId: manager.pluginId,
        sessionId: manager.sessionId,
        manager: manager,
      ),
    );
    entry.keys.addAll(keys.map(normalizeEditorKeyName));
    notifyListeners();
  }

  /// Hands [keys] back to the editor, or every key when [keys] is null.
  void release(PluginRunManager manager, Iterable<String>? keys) {
    final entry = _bySession[manager.sessionId];
    if (entry == null) return;
    if (keys == null) {
      entry.keys.clear();
    } else {
      entry.keys.removeAll(keys.map(normalizeEditorKeyName));
    }
    if (entry.isEmpty) _bySession.remove(manager.sessionId);
    notifyListeners();
  }

  /// Drops every capture owned by a session (plugin stopped or restarted).
  void releaseSession(String sessionId) {
    if (_bySession.remove(sessionId) == null) return;
    notifyListeners();
  }

  /// Drops every capture owned by a plugin.
  void releasePlugin(String pluginId) {
    final stale = _bySession.entries
        .where((entry) => entry.value.pluginId == pluginId)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (stale.isEmpty) return;
    for (final sessionId in stale) {
      _bySession.remove(sessionId);
    }
    notifyListeners();
  }

  /// The session that owns [name], if any.
  EditorKeyCapture? ownerOf(String name) {
    final wanted = normalizeEditorKeyName(name);
    for (final entry in _bySession.values) {
      if (entry.keys.contains(wanted)) return entry;
    }
    return null;
  }

  /// True when the editor must hand [event] to a plugin instead of acting.
  bool isCaptured(KeyEvent event) => ownerOf(editorKeyEventName(event)) != null;

  /// Keys whose forward is still waiting for the plugin's reply.
  ///
  /// A held key repeats roughly every 30 ms while the reply window is 300 ms,
  /// so without this a single hold would queue about ten overlapping requests
  /// per key and let the plugin answer them out of order.
  final Set<String> _inFlight = <String>{};

  /// Called by the editor for every key press, before the engine acts on it.
  ///
  /// Returns true when the press was forwarded to a plugin. Captured keys are
  /// always suppressed, so the plugin is responsible for the fallback action
  /// when it answers `handled: false`.
  bool interceptKeyEvent(KeyEvent event) {
    final name = editorKeyEventName(event);
    if (name.isEmpty) return false;
    final owner = ownerOf(name);
    if (owner == null) return false;
    // The release carries no new intent — the press was already forwarded —
    // but it must still be swallowed or the editor would act on half a
    // keystroke the plugin has taken over.
    if (event is KeyUpEvent) return true;
    if (_inFlight.contains(name)) return true;
    final keyboard = HardwareKeyboard.instance;
    _inFlight.add(name);
    unawaited(
      _forward(
        owner,
        name,
        event,
        shift: keyboard.isShiftPressed,
        control: keyboard.isControlPressed,
        alt: keyboard.isAltPressed,
        meta: keyboard.isMetaPressed,
      ).whenComplete(() => _inFlight.remove(name)),
    );
    return true;
  }

  Future<void> _forward(
    EditorKeyCapture owner,
    String name,
    KeyEvent event, {
    required bool shift,
    required bool control,
    required bool alt,
    required bool meta,
  }) async {
    try {
      await owner.manager.sendAndWaitReply(
        makeEnvelope(
          type: editorKeyEventCommand,
          payload: <String, dynamic>{
            'key': name,
            'label': event.logicalKey.keyLabel,
            'character': event.character,
            'shift': shift,
            'control': control,
            'alt': alt,
            'meta': meta,
            'isDown': event is KeyDownEvent,
            'isRepeat': event is KeyRepeatEvent,
          },
        ),
        timeout: editorKeyReplyTimeout,
        connectIfNeeded: false,
      );
    } catch (_) {
      // A plugin that fails to answer simply loses the key; the editor stays
      // responsive either way.
    }
  }
}

final ChangeNotifierProvider<EditorKeyCaptureRegistry>
editorKeyCaptureProvider = ChangeNotifierProvider<EditorKeyCaptureRegistry>(
  (ref) => EditorKeyCaptureRegistry(),
);
