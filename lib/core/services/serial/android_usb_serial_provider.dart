import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/serial/base_usb_serial.dart';
import 'package:usb_serial/usb_serial.dart';

class AndroidUsbSerialNotifier
    extends BaseUsbSerialNotifier<AndroidUsbSerialState> {
  UsbPort? _port;
  StreamSubscription<Uint8List>? _inputSub;

  AndroidUsbSerialNotifier(Ref ref) : super(ref, const AndroidUsbSerialState());

  @override
  Future<void> performUpdate() async {
    try {
      final devices = await UsbSerial.listDevices();
      final isOpen = _port != null;
      final portName = state.selectedPortName;

      if (isOpen && portName != null) {
        if (!devices.any((d) => d.deviceName == portName)) {
          _autoDisconnect();
          return;
        }
      }

      state = state.copyWith(
        devices: devices,
        isConnected: isOpen && portName != null,
      );
    } catch (_) {
      if (_port == null && state.isConnected) {
        state = state.copyWith(isConnected: false);
      }
    }
  }

  @override
  Future<void> refresh() async {
    try {
      final devices = await UsbSerial.listDevices();
      state = state.copyWith(devices: devices);
    } catch (_) {}
  }

  @override
  Future<void> connectPort(String deviceName) async {
    await disconnectPort();
    bindReplOnOutputCallback();
    final devices = await UsbSerial.listDevices();
    final device = devices.firstWhere(
      (d) => d.deviceName == deviceName,
      orElse: () => throw StateError('Device not found: $deviceName'),
    );
    final port = await device.create();
    if (port == null) return;
    final ok = await port.open();
    if (!ok) {
      await port.close();
      return;
    }
    await port.setPortParameters(
      state.baudRate,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );
    _port = port;
    _inputSub = port.inputStream!.listen(
      _onData,
      onError: (_) => _autoDisconnect(),
      onDone: () => _autoDisconnect(),
    );
    state = state.copyWith(
      selectedPortName: device.deviceName,
      isConnected: true,
    );
    ensureFilesystemMountedIfEnabled();
  }

  void _onData(Uint8List data) {
    handleData(data);
  }

  void _autoDisconnect() {
    final portName = state.selectedPortName;
    _inputSub?.cancel();
    _inputSub = null;
    if (_port != null) {
      _port!.close();
      _port = null;
    }
    state = state.copyWith(selectedPortName: null, isConnected: false);
    UsbSerial.listDevices().then((devices) {
      if (_port == null) {
        state = state.copyWith(devices: devices);
      }
    });
    if (state.autoReconnect && portName != null) {
      scheduleReconnect(portName);
    }
  }

  @override
  Future<void> disconnectPort() async {
    cancelReconnect();
    await _inputSub?.cancel();
    _inputSub = null;
    if (_port != null) {
      await _port!.close();
      _port = null;
    }
    state = state.copyWith(selectedPortName: null, isConnected: false);
  }

  @override
  void sendBytes(Uint8List bytes) {
    _port?.write(bytes);
  }
}

final StateNotifierProvider<AndroidUsbSerialNotifier, AndroidUsbSerialState>
androidUsbSerialProvider = StateNotifierProvider(
  (ref) => AndroidUsbSerialNotifier(ref),
);
