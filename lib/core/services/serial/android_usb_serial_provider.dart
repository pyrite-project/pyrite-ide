import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/serial/repl_io.dart';
import 'package:pyrite_ide/core/services/serial/serial_repl_gate_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_data_callbacks_provider.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/file/board_filesystem_mount.dart';
import 'package:pyrite_ide/core/services/periodic_task/provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:usb_serial/usb_serial.dart';

class AndroidUsbSerialNotifier extends StateNotifier<AndroidUsbSerialState> {
  final Ref ref;
  UsbDevice? _device;
  UsbPort? _port;
  StreamSubscription<Uint8List>? _inputSub;
  Timer? _reconnectTimer;

  AndroidUsbSerialNotifier(this.ref) : super(const AndroidUsbSerialState());

  void registerUpdateTask() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(periodicTaskManagerProvider)
          .registerTask(
            name: "port_message_update",
            interval: const Duration(seconds: 1),
            callback: () => _update(),
          );
    });
  }

  Future<void> _update() async {
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

  Future<void> refresh() async {
    try {
      final devices = await UsbSerial.listDevices();
      state = state.copyWith(devices: devices);
    } catch (_) {}
  }

  Future<void> connectPort(UsbDevice device) async {
    await dicconnectPort();
    bindReplOnOutputCallback();
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
    _device = device;
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
    _ensureFilesystemMountedIfEnabled();
  }

  void _onData(Uint8List data) {
    if (!ref.read(serialReplIoPausedProvider)) {
      try {
        repl.write(utf8.decode(data));
      } catch (_) {}
    }
    for (final cb in ref.read(serialDataCallbacksProvider)) {
      try {
        cb(data);
      } catch (_) {}
    }
  }

  void _autoDisconnect() {
    final device = _device;
    final portName = state.selectedPortName;
    _inputSub?.cancel();
    _inputSub = null;
    if (_port != null) {
      _port!.close();
      _port = null;
    }
    _device = null;
    state = state.copyWith(selectedPortName: null, isConnected: false);
    UsbSerial.listDevices().then((devices) {
      if (_port == null) {
        state = state.copyWith(devices: devices);
      }
    });
    if (state.autoReconnect && device != null && portName != null) {
      _scheduleReconnect(device);
    }
  }

  Future<void> dicconnectPort() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _inputSub?.cancel();
    _inputSub = null;
    if (_port != null) {
      await _port!.close();
      _port = null;
    }
    _device = null;
    state = state.copyWith(selectedPortName: null, isConnected: false);
  }

  void _scheduleReconnect(UsbDevice device) {
    _reconnectTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_port != null) {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        return;
      }
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
      _device = device;
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
      bindReplOnOutputCallback();
      _ensureFilesystemMountedIfEnabled();
    });
  }

  void setBaudRate(int value) {
    state = state.copyWith(baudRate: value);
  }

  void setAutoReconnect(bool value) {
    state = state.copyWith(autoReconnect: value);
  }

  void _ensureFilesystemMountedIfEnabled() {
    if (!ref.read(ensureBoardFilesystemOnConnect)) return;
    unawaited(ensureBoardFilesystemMountedOnce(ref));
  }

  void sendBytes(Uint8List bytes) {
    _port?.write(bytes);
  }

  void sendCommand(String command, {bool chunked = true}) {
    if (_port == null) return;
    final data = utf8.encode(command);
    if (chunked && data.length > 64) {
      _sendChunked(Uint8List.fromList(data));
    } else {
      _port!.write(Uint8List.fromList(data));
    }
  }

  void _sendChunked(Uint8List data) async {
    const chunkSize = 32;
    for (int i = 0; i < data.length; i += chunkSize) {
      if (_port == null) return;
      final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
      await _port!.write(data.sublist(i, end));
      await Future.delayed(const Duration(milliseconds: 1));
    }
  }

  void bindReplOnOutputCallback() {
    repl.onOutput = (String data) {
      if (ref.read(serialReplIoPausedProvider)) return;
      final encode = ref.read(chineseToUnicodeConversion);
      sendCommand(encode ? ReplInputEncoder.encode(data) : data);
    };
  }
}

final StateNotifierProvider<AndroidUsbSerialNotifier, AndroidUsbSerialState>
androidUsbSerialProvider = StateNotifierProvider(
  (ref) => AndroidUsbSerialNotifier(ref),
);
