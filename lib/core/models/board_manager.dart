import 'package:flutter/foundation.dart';
import 'package:flserial/serial_scanner.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:pyrite_ide/core/services/serial/base_usb_serial.dart';

class DesktopUsbSerialState extends UsbSerialState {
  const DesktopUsbSerialState({
    this.portInfos = const [],
    super.selectedPortName,
    super.isConnected,
    super.baudRate,
    super.autoReconnect,
  });

  List<String> get portNames => portInfos.map((p) => p.path).toList();

  final List<SerialPortInfo> portInfos;

  @override
  DesktopUsbSerialState copyWith({
    List<SerialPortInfo>? portInfos,
    String? selectedPortName,
    bool? isConnected,
    int? baudRate,
    bool? autoReconnect,
  }) {
    return DesktopUsbSerialState(
      portInfos: portInfos ?? this.portInfos,
      selectedPortName: selectedPortName ?? this.selectedPortName,
      isConnected: isConnected ?? this.isConnected,
      baudRate: baudRate ?? this.baudRate,
      autoReconnect: autoReconnect ?? this.autoReconnect,
    );
  }
}

class AndroidUsbSerialState extends UsbSerialState {
  const AndroidUsbSerialState({
    this.devices = const [],
    super.selectedPortName,
    super.isConnected,
    super.baudRate,
    super.autoReconnect,
  });

  final List<UsbDevice> devices;

  @override
  AndroidUsbSerialState copyWith({
    List<UsbDevice>? devices,
    String? selectedPortName,
    bool? isConnected,
    int? baudRate,
    bool? autoReconnect,
  }) {
    return AndroidUsbSerialState(
      devices: devices ?? this.devices,
      selectedPortName: selectedPortName ?? this.selectedPortName,
      isConnected: isConnected ?? this.isConnected,
      baudRate: baudRate ?? this.baudRate,
      autoReconnect: autoReconnect ?? this.autoReconnect,
    );
  }
}

typedef SerialDataCallback = void Function(Uint8List data);
