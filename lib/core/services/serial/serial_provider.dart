import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flserial/flserial.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/file/board_tree.dart';
import 'package:pyrite_ide/core/services/logging/app_log.dart';
import 'package:pyrite_ide/core/services/serial/base_usb_serial.dart';
import 'package:pyrite_ide/core/services/serial/device_status_provider.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';
import 'package:pyrite_ide/core/services/serial/port_catalog/serial_port_catalog.dart';
import 'package:pyrite_ide/core/services/serial/serial_session_registry.dart';

final DynamicLibrary? _kernel32 = Platform.isWindows
    ? DynamicLibrary.open('kernel32.dll')
    : null;

final _createFileW = _kernel32
    ?.lookupFunction<
      IntPtr Function(
        Pointer<Utf16>,
        Uint32,
        Uint32,
        Pointer,
        Uint32,
        Uint32,
        IntPtr,
      ),
      int Function(Pointer<Utf16>, int, int, Pointer, int, int, int)
    >('CreateFileW');

final _closeHandle = _kernel32
    ?.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

final _getLastError = _kernel32
    ?.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

/// Creates the native transport for each open attempt. Tests override it to
/// stand in for the OS serial port.
final serialPortFactoryProvider = Provider<FlSerial Function()>(
  (ref) => FlSerial.new,
);

/// Thrown by [SerialNotifier.connectPort] when the OS refuses to open [path].
class SerialOpenException implements Exception {
  const SerialOpenException(this.path, this.cause);

  final String path;

  /// Why the port could not be opened, or `null` when the platform gave no
  /// reason.
  final SerialOpenError? cause;

  @override
  String toString() =>
      'Cannot open serial port $path: ${cause ?? 'no reason reported'}';
}

class SerialNotifier extends BaseUsbSerialNotifier<SerialProviderState> {
  FlSerial? _serial;
  final SerialPortCatalog _catalog = SerialPortCatalog();
  StreamSubscription<SerialEvent>? _eventSub;
  bool _runConnectInitialization = true;

  /// Every open port, not just the active one.
  ///
  /// The notifier keeps its single-handle fields as a view onto the active
  /// session: the whole app addresses "the device", and rewriting those call
  /// sites would gain nothing a session registry does not already provide.
  final SerialSessionRegistry sessions = SerialSessionRegistry();

  SerialNotifier(Ref ref) : super(ref, const SerialProviderState()) {
    sessions.addListener(_onSessionsChanged);
  }

  /// Mirrors the active session into this notifier's state.
  ///
  /// A session that disappears (unplugged, closed from the device page) has to
  /// clear `isConnected`, otherwise every device operation would keep waiting
  /// on a handle that no longer exists.
  void _onSessionsChanged() {
    final active = sessions.activeSession;
    if (active == null) {
      _serial = null;
      _eventSub = null;
      if (state.isConnected || state.selectedPortName != null) {
        state = state.copyWith(clearSelectedPort: true, isConnected: false);
      }
      return;
    }
    _serial = active.serial;
    _eventSub = active.events;
    if (state.selectedPortName != active.portPath || !state.isConnected) {
      state = state.copyWith(
        selectedPortName: active.portPath,
        isConnected: true,
        baudRate: active.baudRate,
      );
    }
  }

  @override
  Future<void> performUpdate() async {
    try {
      final ports = await _catalog.scan();
      final isOpen = _serial != null;
      final portName = state.selectedPortName;

      if (isOpen && portName != null) {
        if (ports.any((p) => p.path == portName)) {
          if (!await _portExistsOnSystem(portName)) {
            _autoDisconnect();
            return;
          }
        } else {
          _autoDisconnect();
          return;
        }
      }

      state = state.copyWith(
        ports: ports,
        isConnected: isOpen && portName != null,
      );
    } catch (error) {
      // Runs on a timer, so this stays at debug: a port scan that keeps
      // failing would otherwise write a warning every tick.
      AppLog.d(
        'serial',
        'port scan failed during update; keeping the previous list',
        error: error,
      );
      if (_serial == null && state.isConnected) {
        state = state.copyWith(isConnected: false);
      }
    }
  }

  Future<bool> _portExistsOnSystem(String portName) {
    if (_createFileW == null) return Future.value(true);
    try {
      final path = '\\\\.\\$portName';
      final wide = path.toNativeUtf16(allocator: malloc);
      final handle = _createFileW!(wide, 0, 3, nullptr, 3, 0x80, 0);
      malloc.free(wide);

      const int invalidHandleValue = -1;
      if (handle == invalidHandleValue) {
        final error = _getLastError!();
        return Future.value(error != 2 && error != 1617);
      }

      _closeHandle!(handle);
      return Future.value(true);
    } catch (error) {
      // Answering "still present" keeps the connection: a probe that cannot
      // run is not evidence the port vanished.
      AppLog.d(
        'serial',
        'existence probe failed for $portName, assuming present',
        error: error,
      );
      return Future.value(true);
    }
  }

  @override
  Future<void> refresh() async {
    try {
      final ports = await _catalog.scan(refreshMetadata: true);
      state = state.copyWith(ports: ports);
    } catch (error) {
      // The visible symptom is an empty or stale port list; without this line
      // it looks like the machine has no serial ports at all.
      AppLog.w(
        'serial',
        'refreshing the serial port list failed',
        error: error,
      );
    }
  }

  @override
  Future<void> connectPort(String path) async {
    final cycle = Stopwatch()..start();
    // Connecting a second port must not drop the first board: a session is
    // opened alongside the existing ones and only becomes the one the IDE
    // talks to. Re-connecting an already open port just switches to it.
    final existing = sessions.sessionForPort(path);
    if (existing != null) {
      sessions.setActive(existing.id);
      await _afterActiveChanged();
      return;
    }
    await closeSessionFor(path, notify: false);
    ref.read(boardFileItemsProvider.notifier).clear();
    ref.read(deviceStatusProvider.notifier).clear();

    bindReplOnOutputCallback();
    final serial = ref.read(serialPortFactoryProvider)();
    // flserial events carry no port identity. The subscription this closure is
    // bound to supplies it, so two open boards cannot feed each other's data
    // into the REPL or a running transaction.
    final subscription = serial.events.listen((event) => _onEvent(path, event));
    _eventSub = subscription;
    final config = _serialConfig();
    final ok = await serial.open(path, config);
    if (ok) {
      final session = sessions.create(
        portPath: path,
        serial: serial,
        events: subscription,
        baudRate: state.baudRate,
      );
      _serial = serial;
      sessions.adopt(session);
      state = state.copyWith(selectedPortName: path, isConnected: true);
      // A connection is the first thing a bug report needs: which port, at
      // which rate, how long the open took, and how many sessions are open.
      AppLog.i(
        'serial',
        'connected $path at ${state.baudRate} baud in '
            '${cycle.elapsedMilliseconds}ms sessions=${sessions.sessions.length}',
      );
      sendCommand('\x03', chunked: false);
      if (_runConnectInitialization) ensureFilesystemMountedIfEnabled();
    } else {
      final error = serial.lastOpenError;
      await subscription.cancel();
      if (identical(_eventSub, subscription)) {
        _eventSub = sessions.activeSession?.events;
      }
      await serial.dispose();
      // The exception carries this too, but only to the one caller that
      // happens to catch it; the log keeps the reason for the next reader.
      AppLog.w(
        'serial',
        'open $path failed after ${cycle.elapsedMilliseconds}ms: '
            '${error ?? 'no reason reported'}',
      );
      throw SerialOpenException(path, error);
    }
  }

  SerialConfig _serialConfig() => SerialConfig(
    baudRate: state.baudRate,
    dataBits: 8,
    stopBits: 1,
    parity: 0,
    flowControl: 0,
  );

  /// Routes one event from [portPath]'s subscription.
  ///
  /// `SerialEvent` has no port identity, so the port is captured where the
  /// subscription is created. Only the active session's transport may move
  /// this notifier's state or feed the REPL; an inactive board keeps its
  /// handle but its bytes are discarded.
  void _onEvent(String portPath, SerialEvent event) {
    final session = sessions.sessionForPort(portPath);
    final isActive = sessions.activeSession?.portPath == portPath;
    switch (event.type) {
      case SerialEventType.connected:
        if (isActive) {
          state = state.copyWith(isConnected: true);
        }
      case SerialEventType.disconnected:
        if (session != null) {
          unawaited(_handleTransportLost(session));
        }
      case SerialEventType.data:
        if (isActive) {
          handleData(event.data as Uint8List);
        }
      case SerialEventType.lineStatusChanged:
        break;
      case SerialEventType.error:
        AppLog.e('serial', 'transport error on $portPath', error: event.data);
        if (session != null) {
          unawaited(_handleTransportLost(session));
        }
    }
  }

  /// Drops the one session whose transport went away.
  ///
  /// A board that is merely open in the background must not take the active
  /// board down with it: only [session] is closed. When it was the active
  /// session, the registry promotes the oldest remaining one, and automatic
  /// reconnection targets the port that was actually lost.
  Future<void> _handleTransportLost(SerialSession session) async {
    final wasActive = session.isActive;
    AppLog.w(
      'serial',
      'transport lost on ${session.portPath}; dropping its session',
    );
    if (wasActive) resetReplOutputDecoder();
    await sessions.close(session.id);
    if (!wasActive) return;
    _catalog.scan().then((ports) {
      if (!state.isConnected) {
        state = state.copyWith(ports: ports);
      }
    });
    if (state.autoReconnect) {
      scheduleReconnect(session.portPath);
    }
  }

  void _autoDisconnect() {
    final active = sessions.activeSession;
    if (active != null) {
      unawaited(_handleTransportLost(active));
      return;
    }
    AppLog.w('serial', 'transport lost; dropping the active session');
    resetReplOutputDecoder();
    final portName = state.selectedPortName;
    _eventSub?.cancel();
    _eventSub = null;
    _serial = null;
    state = state.copyWith(clearSelectedPort: true, isConnected: false);
    _catalog.scan().then((ports) {
      if (!state.isConnected) {
        state = state.copyWith(ports: ports);
      }
    });
    if (state.autoReconnect && portName != null) {
      scheduleReconnect(portName);
    }
  }

  /// Closes the session for [portPath], if one exists.
  ///
  /// Called both by explicit disconnects and by an unplug; `notify` is off for
  /// the reconnect path that immediately opens a replacement session.
  Future<void> closeSessionFor(String portPath, {bool notify = true}) async {
    final session = sessions.sessionForPort(portPath);
    if (session == null) return;
    if (notify) resetReplOutputDecoder();
    await sessions.close(session.id);
  }

  /// Closes every open port.
  ///
  /// Separate from [disconnectPort] so the single-device call sites keep the
  /// meaning they had: "drop the device I am talking to".
  Future<void> disconnectAllPorts() async {
    resetReplOutputDecoder();
    cancelReconnect();
    await sessions.closeAll();
    state = state.copyWith(clearSelectedPort: true, isConnected: false);
  }

  /// Switches which open session the IDE talks to.
  void activateSession(String id) {
    if (!sessions.setActive(id)) return;
    unawaited(_afterActiveChanged());
  }

  /// Re-syncs device-scoped caches after the active session changed.
  ///
  /// The board file tree and the status panel describe one device; leaving the
  /// previous board's listing on screen after a switch would show files that
  /// live on the other board.
  Future<void> _afterActiveChanged() async {
    final active = sessions.activeSession;
    if (active == null) return;
    state = state.copyWith(
      selectedPortName: active.portPath,
      isConnected: true,
      baudRate: active.baudRate,
    );
    ref.read(boardFileItemsProvider.notifier).clear();
    ref.read(deviceStatusProvider.notifier).clear();
    sendCommand('\x03', chunked: false);
  }

  @override
  Future<void> disconnectPort() async {
    final portName = state.selectedPortName;
    AppLog.i('serial', 'disconnect requested port=$portName');
    resetReplOutputDecoder();
    cancelReconnect();
    final active = sessions.activeSession;
    if (active != null) {
      await sessions.close(active.id);
    } else {
      await _clearUnregisteredTransport();
    }
    if (sessions.activeSession == null) {
      state = state.copyWith(clearSelectedPort: true, isConnected: false);
    }
  }

  /// Releases the notifier's mirror when no session owns it.
  Future<void> _clearUnregisteredTransport() async {
    await _eventSub?.cancel();
    _eventSub = null;
    final stale = _serial;
    _serial = null;
    if (stale != null) {
      await stale.close();
      await stale.dispose();
    }
  }

  @override
  void sendBytes(Uint8List bytes) {
    _serial?.write(bytes);
  }

  /// Applies the explicitly selected DTR/RTS sequence and waits for the device
  /// to leave reset.
  ///
  /// A successful reset does not imply that a REPL prompt will appear: a board
  /// may immediately execute boot.py/main.py or remain silent. Returns false
  /// only when the transport/sequence is unsupported or a control-line change
  /// fails.
  Future<bool> hardwareReset(HardwareResetStrategy strategy) async {
    final serial = _serial;
    final portName = state.selectedPortName;
    if (serial == null ||
        portName == null ||
        strategy == HardwareResetStrategy.disabled) {
      return false;
    }
    try {
      final capabilities = await serial.getControlCapabilities();
      if (strategy == HardwareResetStrategy.dtrPulse && !capabilities.dtr ||
          strategy == HardwareResetStrategy.rtsPulse && !capabilities.rts ||
          strategy == HardwareResetStrategy.esp32 &&
              (!capabilities.dtr || !capabilities.rts)) {
        AppLog.w(
          'serial',
          'hardware reset unsupported: strategy=$strategy '
              'dtr=${capabilities.dtr} rts=${capabilities.rts}',
        );
        return false;
      }

      AppLog.i(
        'serial',
        'hardware reset start: strategy=$strategy '
            'dtr=${capabilities.dtr} rts=${capabilities.rts}',
      );
      await applyHardwareResetSequence(
        strategy,
        setDtr: (active) async {
          AppLog.d('serial', 'reset line DTR=$active');
          await serial.setDTR(active);
        },
        setRts: (active) async {
          AppLog.d('serial', 'reset line RTS=$active');
          await serial.setRTS(active);
        },
      );

      // Keep the existing serial session alive so boot output is not lost and
      // do not send Ctrl-C/Ctrl-B or require ">>>": boot.py/main.py may
      // intentionally keep running after reset and a valid application may
      // produce no output.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      // Any selected sequence may reset an ESP32-S3 native USB CDC/JTAG port.
      // Windows often keeps the same COM name while the existing handle
      // silently becomes stale. Always refresh the handle so trying another
      // strategy cannot poison the next reset attempt.
      final reopened = await _refreshSerialHandleAfterReset(portName);
      if (!reopened) {
        throw StateError('Serial port did not return after hardware reset');
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
      AppLog.i('serial', 'hardware reset pulse complete');
      return true;
    } catch (error) {
      AppLog.w('serial', 'hardware reset failed', error: error);
      // Disconnect the reset board explicitly so subsequent operations fail
      // fast instead of repeatedly timing out behind a stale connected state.
      // Closing by port keeps a second open board untouched even when the
      // failed reset has already promoted it to active.
      await closeSessionFor(portName);
      if (sessions.activeSession == null) {
        await _clearUnregisteredTransport();
        state = state.copyWith(clearSelectedPort: true, isConnected: false);
      }
      return false;
    }
  }

  Future<bool> _refreshSerialHandleAfterReset(String portName) async {
    AppLog.d('serial', 'refreshing serial handle after hardware reset');
    final session = sessions.sessionForPort(portName);
    if (session == null) return false;

    var attempts = 0;
    // Nothing may address the invalid handle while it is being replaced; the
    // registry notification re-points the mirror once a transport exists.
    _serial = null;
    state = state.copyWith(isConnected: false);
    // The registry closes the invalid handle and installs the replacement in
    // one step, so nothing can keep addressing the disposed transport.
    final reopened = await sessions.replaceTransport(session.id, () async {
      const maxAttempts = 34;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        attempts = attempt;
        if (attempt > 1) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }

        final replacement = ref.read(serialPortFactoryProvider)();
        final replacementSub = replacement.events.listen(
          (event) => _onEvent(portName, event),
        );
        try {
          if (await replacement.open(portName, _serialConfig())) {
            return SerialTransport(serial: replacement, events: replacementSub);
          }
        } catch (error) {
          AppLog.w(
            'serial',
            'serial handle refresh attempt $attempt failed',
            error: error,
          );
        }
        await replacementSub.cancel();
        await replacement.dispose();
      }
      return null;
    });

    if (!reopened) {
      AppLog.w('serial', 'serial handle refresh timed out');
      return false;
    }
    AppLog.d('serial', 'serial handle refreshed after $attempts attempt(s)');
    return true;
  }

  /// Reconnect to the current port at a different baud rate.
  ///
  /// This is used when the device's baud rate needs to be changed during
  /// the connection process (e.g., after detecting a non-115200 device).
  Future<bool> reconnectAtBaud(
    int newBaud, {
    bool initializeDevice = true,
  }) async {
    final portName = state.selectedPortName;
    if (portName == null) return false;

    AppLog.i('serial', 'reconnecting at $newBaud baud');

    // Close this port's session (not every port) before reopening it at the
    // new rate: a baud change only concerns the board being retuned, and the
    // other boards must stay connected. The registry notification has already
    // moved `_serial`/`_eventSub` to the remaining active session, if any.
    await closeSessionFor(portName, notify: false);
    // No board remains open, so the app is disconnected until the reopen
    // succeeds. Another active session (a second board) keeps its state.
    if (sessions.activeSession == null) {
      state = state.copyWith(clearSelectedPort: true, isConnected: false);
    }

    // Update the baud rate in state.
    state = state.copyWith(baudRate: newBaud);

    // Reconnect with the new baud rate.
    _runConnectInitialization = initializeDevice;
    try {
      await connectPort(portName);
    } on SerialOpenException catch (error) {
      AppLog.w('serial', 'reconnect at $newBaud baud failed', error: error);
      return false;
    } finally {
      _runConnectInitialization = true;
    }
    return state.isConnected;
  }
}

final StateNotifierProvider<SerialNotifier, SerialProviderState>
serialProvider = StateNotifierProvider(SerialNotifier.new);
