import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flserial/flserial.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/serial/base_usb_serial.dart';
import 'package:pyrite_ide/core/services/serial/device_status_provider.dart';
import 'package:pyrite_ide/core/services/file/board_tree.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';

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

  SerialNotifier(Ref ref) : super(ref, const SerialProviderState());

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
    await disconnectPort();
    ref.read(boardFileItemsProvider.notifier).clear();
    ref.read(deviceStatusProvider.notifier).clear();

    bindReplOnOutputCallback();
    final serial = FlSerial();
    _eventSub = serial.events.listen(_onEvent);
    final config = _serialConfig();
    final ok = await serial.open(path, config);
    if (ok) {
      _serial = serial;
      state = state.copyWith(selectedPortName: path, isConnected: true);
      if (_runConnectInitialization) ensureFilesystemMountedIfEnabled();
    } else {
      await _eventSub?.cancel();
      _eventSub = null;
      await serial.dispose();
    }
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
      case SerialEventType.error:
        break;
    }
  }

  void _autoDisconnect() {
    final portName = state.selectedPortName;
    _eventSub?.cancel();
    _eventSub = null;
    if (_serial != null) {
      _serial!.close();
      _serial!.dispose();
      _serial = null;
    }
    state = state.copyWith(clearSelectedPort: true, isConnected: false);
    FlSerial.availablePorts().then((ports) {
      if (_serial == null) {
        state = state.copyWith(portInfos: ports);
      }
    });
    if (state.autoReconnect && portName != null) {
      scheduleReconnect(portName);
    }
  }

  @override
  Future<void> disconnectPort() async {
    cancelReconnect();
    await _eventSub?.cancel();
    _eventSub = null;
    if (_serial != null) {
      await _serial!.close();
      await _serial!.dispose();
      _serial = null;
    }
    state = state.copyWith(clearSelectedPort: true, isConnected: false);
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

    // Disconnect first.
    await _eventSub?.cancel();
    _eventSub = null;
    if (_serial != null) {
      await _serial!.close();
      await _serial!.dispose();
      _serial = null;
    }

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
