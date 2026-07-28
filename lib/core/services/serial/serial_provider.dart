import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flserial/flserial.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/serial/base_usb_serial.dart';
import 'package:pyrite_ide/core/services/serial/device_status_provider.dart';
import 'package:pyrite_ide/core/services/file/board_tree.dart';

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
    final config = SerialConfig(
      baudRate: state.baudRate,
      dataBits: 8,
      stopBits: 1,
      parity: 0,
      flowControl: 0,
    );
    final ok = await serial.open(path, config);
    if (ok) {
      _serial = serial;
      state = state.copyWith(selectedPortName: path, isConnected: true);
      ensureFilesystemMountedIfEnabled();
    } else {
      await _eventSub?.cancel();
      _eventSub = null;
      await serial.dispose();
    }
  }

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
    state = state.copyWith(selectedPortName: null, isConnected: false);
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
    state = state.copyWith(selectedPortName: null, isConnected: false);
  }

  @override
  void sendBytes(Uint8List bytes) {
    _serial?.write(bytes);
  }
}

final StateNotifierProvider<SerialNotifier, SerialProviderState>
    serialProvider = StateNotifierProvider(
  (ref) => SerialNotifier(ref),
);
