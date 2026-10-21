import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flserial/flserial.dart';
import 'package:pyrite_ide/core/services/device/board_identity.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';

/// One open serial port.
///
/// The IDE used to keep a single [FlSerial] handle and closed it before opening
/// the next port, so a second board could never stay connected. A session owns
/// its own handle and subscription; the code that talks to "the device" keeps
/// addressing the active session, which is why the rest of the app did not have
/// to change.
class SerialSession {
  SerialSession({
    required this.id,
    required this.portPath,
    required this.serial,
    required this.events,
    required this.baudRate,
    this.identity,
  });

  /// Stable identity for this open handle. A port that is closed and reopened
  /// gets a new id, so a stale reference cannot address the new handle.
  final String id;

  final String portPath;
  final FlSerial serial;
  final StreamSubscription<SerialEvent> events;
  final int baudRate;

  /// Best-effort identification from the port's USB ids, when the platform
  /// exposes them.
  final BoardIdentity? identity;

  /// When the handle opened, used to order the session list deterministically.
  final DateTime openedAt = DateTime.now();

  /// Whether this session is the one the rest of the IDE is talking to.
  bool isActive = false;

  /// Reports the reset strategy this session's board responds to.
  ///
  /// Falls back to "no host-side reset" when the port could not be identified,
  /// which matches the previous default for unknown boards.
  HardwareResetStrategy get resetStrategy =>
      identity?.resetStrategy.toHardware() ?? HardwareResetStrategy.disabled;

  Future<void> dispose() async {
    await events.cancel();
    try {
      await serial.close();
    } catch (_) {
      // A handle whose port already vanished throws here; the session is gone
      // either way, and failing to close must not block closing the next one.
    }
    await serial.dispose();
  }
}

extension on BoardResetStrategy {
  HardwareResetStrategy toHardware() => switch (this) {
    BoardResetStrategy.none => HardwareResetStrategy.disabled,
    BoardResetStrategy.dtrPulse => HardwareResetStrategy.dtrPulse,
    BoardResetStrategy.rtsPulse => HardwareResetStrategy.rtsPulse,
    BoardResetStrategy.esp32 => HardwareResetStrategy.esp32,
    BoardResetStrategy.reopenPort => HardwareResetStrategy.esp32,
  };
}

/// Every serial port the IDE currently holds open.
///
/// Exactly one session is active. Inactive sessions keep their handle and
/// subscription alive — that is the whole point, a second board stays connected
/// and keeps running — but their data is discarded rather than rendered into
/// the single REPL: the console has one transcript and mixing two boards'
/// output into it would make both unreadable. Switching the active session is
/// what moves the console.
class SerialSessionRegistry extends ChangeNotifier {
  final Map<String, SerialSession> _sessions = <String, SerialSession>{};
  int _nextId = 0;

  /// Open sessions, oldest first.
  List<SerialSession> get sessions {
    final list = _sessions.values.toList()
      ..sort((a, b) => a.openedAt.compareTo(b.openedAt));
    return List.unmodifiable(list);
  }

  SerialSession? get activeSession =>
      _sessions.values.where((session) => session.isActive).firstOrNull;

  SerialSession? sessionForPort(String portPath) {
    for (final session in _sessions.values) {
      if (session.portPath == portPath) return session;
    }
    return null;
  }

  bool isPortOpen(String portPath) => sessionForPort(portPath) != null;

  /// Registers [session] and makes it the active one.
  ///
  /// Any previous active session is demoted, not closed: connecting to a second
  /// port must not drop the first board.
  void adopt(SerialSession session) {
    _sessions[session.id] = session;
    setActive(session.id);
  }

  /// Builds a session for [port] around an already-open [serial] handle.
  SerialSession create({
    required String portPath,
    required FlSerial serial,
    required StreamSubscription<SerialEvent> events,
    required int baudRate,
    BoardIdentity? identity,
  }) {
    final session = SerialSession(
      id: 'serial-session-${_nextId++}',
      portPath: portPath,
      serial: serial,
      events: events,
      baudRate: baudRate,
      identity: identity,
    );
    return session;
  }

  /// Makes [id] the active session. Returns false when it is not open.
  bool setActive(String? id) {
    if (id != null && !_sessions.containsKey(id)) return false;
    var changed = false;
    for (final session in _sessions.values) {
      final shouldBeActive = session.id == id;
      if (session.isActive != shouldBeActive) {
        session.isActive = shouldBeActive;
        changed = true;
      }
    }
    if (changed) notifyListeners();
    return true;
  }

  /// Removes [id] and closes its handle.
  ///
  /// Closing the active session promotes the oldest remaining one so the IDE
  /// never ends up with open ports and no active device.
  Future<SerialSession?> close(String id) async {
    final session = _sessions.remove(id);
    if (session == null) return null;
    final wasActive = session.isActive;
    session.isActive = false;
    await session.dispose();
    if (wasActive) {
      final remaining = sessions;
      if (remaining.isNotEmpty) {
        remaining.first.isActive = true;
      }
    }
    notifyListeners();
    return session;
  }

  Future<void> closeAll() async {
    final all = _sessions.values.toList();
    _sessions.clear();
    for (final session in all) {
      session.isActive = false;
      await session.dispose();
    }
    notifyListeners();
  }
}
