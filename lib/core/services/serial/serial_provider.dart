import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flserial/flserial.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/device/board_identity.dart';
import 'package:pyrite_ide/core/services/device/board_identity_provider.dart';
import 'package:pyrite_ide/core/services/serial/base_usb_serial.dart';
import 'package:pyrite_ide/core/services/serial/device_status_provider.dart';
import 'package:pyrite_ide/core/services/file/board_tree.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';
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

class SerialNotifier extends BaseUsbSerialNotifier<SerialProviderState> {
  FlSerial? _serial;
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
      final ports = await FlSerial.availablePorts();
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
        portInfos: ports,
        isConnected: isOpen && portName != null,
      );
    } catch (_) {
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
    } catch (_) {
      return Future.value(true);
    }
  }

  @override
  Future<void> refresh() async {
    try {
      final ports = await FlSerial.availablePorts();
      state = state.copyWith(portInfos: ports);
    } catch (_) {}
  }

  @override
  Future<void> connectPort(String path) async {
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

    // USB VID/PID identification runs before the port is opened so the first
    // handshake already uses the right baud rate and reset strategy. Explicit
    // user settings are never overwritten here.
    applyBoardDefaultsOnConnect(ref, path: path);

    bindReplOnOutputCallback();
    final serial = FlSerial();
    _eventSub = serial.events.listen(_onEvent);
    final config = _serialConfig();
    final ok = await serial.open(path, config);
    if (ok) {
      final session = sessions.create(
        portPath: path,
        serial: serial,
        events: _eventSub!,
        baudRate: state.baudRate,
        identity: _identityForPort(path),
      );
      _serial = serial;
      sessions.adopt(session);
      state = state.copyWith(selectedPortName: path, isConnected: true);
      sendCommand('\x03', chunked: false);
      if (_runConnectInitialization) ensureFilesystemMountedIfEnabled();
    } else {
      await _eventSub?.cancel();
      _eventSub = null;
      await serial.dispose();
    }
  }

  /// Identity of [portPath] from the last port scan.
  ///
  /// The scan runs every few seconds, so the entry is normally present by the
  /// time the user connects; a missing entry simply means "unidentified".
  BoardIdentity? _identityForPort(String portPath) {
    for (final port in state.portInfos) {
      if (port.path == portPath) return identifyPort(port);
    }
    return null;
  }

  SerialConfig _serialConfig() => SerialConfig(
    baudRate: state.baudRate,
    dataBits: 8,
    stopBits: 1,
    parity: 0,
    flowControl: 0,
  );

  void _onEvent(SerialEvent event) {
    switch (event.type) {
      case SerialEventType.connected:
        state = state.copyWith(isConnected: true);
      case SerialEventType.disconnected:
        _autoDisconnect();
      case SerialEventType.data:
        final data = event.data as Uint8List;
        handleData(data);
      case SerialEventType.lineStatusChanged:
        break;
      case SerialEventType.error:
        debugPrint('[serial] transport error: ${event.data}');
        _autoDisconnect();
    }
  }

  void _autoDisconnect() {
    resetReplOutputDecoder();
    final portName = state.selectedPortName;
    final active = sessions.activeSession;
    // The handle is already gone: drop the session rather than disposing it
    // again, and only then fall back to whatever session remains.
    if (active != null) {
      unawaited(closeSessionFor(active.portPath, notify: true));
    } else {
      _eventSub?.cancel();
      _eventSub = null;
      _serial = null;
      state = state.copyWith(clearSelectedPort: true, isConnected: false);
    }
    FlSerial.availablePorts().then((ports) {
      if (!state.isConnected) {
        state = state.copyWith(portInfos: ports);
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
    resetReplOutputDecoder();
    cancelReconnect();
    final active = sessions.activeSession;
    if (active != null) {
      await sessions.close(active.id);
    } else {
      await _eventSub?.cancel();
      _eventSub = null;
      if (_serial != null) {
        await _serial!.close();
        await _serial!.dispose();
        _serial = null;
      }
    }
    if (sessions.activeSession == null) {
      state = state.copyWith(clearSelectedPort: true, isConnected: false);
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
        debugPrint(
          '[serial] hardware reset unsupported: strategy=$strategy '
          'dtr=${capabilities.dtr} rts=${capabilities.rts}',
        );
        return false;
      }

      debugPrint(
        '[serial] hardware reset start: strategy=$strategy '
        'dtr=${capabilities.dtr} rts=${capabilities.rts}',
      );
      await applyHardwareResetSequence(
        strategy,
        setDtr: (active) async {
          debugPrint('[serial] hardware reset line DTR=$active');
          await serial.setDTR(active);
        },
        setRts: (active) async {
          debugPrint('[serial] hardware reset line RTS=$active');
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
      debugPrint('[serial] hardware reset pulse complete');
      return true;
    } catch (error) {
      debugPrint('[serial] hardware reset failed: $error');
      // Disconnect explicitly so subsequent operations fail fast instead of
      // repeatedly timing out behind a stale connected state.
      await disconnectPort();
      return false;
    }
  }

  Future<bool> _refreshSerialHandleAfterReset(String portName) async {
    debugPrint('[serial] refreshing serial handle after hardware reset');
    await _eventSub?.cancel();
    _eventSub = null;

    final previous = _serial;
    _serial = null;
    state = state.copyWith(isConnected: false);
    if (previous != null) {
      await previous.close();
      await previous.dispose();
    }

    const attempts = 34;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      if (attempt > 1) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }

      final replacement = FlSerial();
      final replacementSub = replacement.events.listen(_onEvent);
      try {
        if (await replacement.open(portName, _serialConfig())) {
          _serial = replacement;
          _eventSub = replacementSub;
          state = state.copyWith(selectedPortName: portName, isConnected: true);
          debugPrint(
            '[serial] serial handle refreshed after $attempt attempt(s)',
          );
          return true;
        }
      } catch (error) {
        debugPrint(
          '[serial] serial handle refresh attempt $attempt failed: $error',
        );
      }
      await replacementSub.cancel();
      await replacement.dispose();
    }

    debugPrint('[serial] serial handle refresh timed out');
    return false;
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

    debugPrint('[serial] reconnecting at $newBaud baud');

    // Close this port's session (not every port) before reopening it at the
    // new rate: a baud change only concerns the board being retuned, and the
    // other boards must stay connected.
    await closeSessionFor(portName, notify: false);
    await _eventSub?.cancel();
    _eventSub = null;
    _serial = null;

    // Update the baud rate in state.
    state = state.copyWith(baudRate: newBaud);

    // Reconnect with the new baud rate.
    _runConnectInitialization = initializeDevice;
    try {
      await connectPort(portName);
    } finally {
      _runConnectInitialization = true;
    }
    return state.isConnected;
  }
}

final StateNotifierProvider<SerialNotifier, SerialProviderState>
serialProvider = StateNotifierProvider((ref) => SerialNotifier(ref));
