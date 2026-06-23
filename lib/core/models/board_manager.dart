import 'package:flutter/foundation.dart';
import 'package:flserial/serial_scanner.dart';
import 'package:usb_serial/usb_serial.dart';

class DesktopUsbSerialState {
  const DesktopUsbSerialState({
    this.portInfos = const [],
    this.selectedPortName,
    this.isConnected = false,
    this.baudRate = 115200,
    this.autoReconnect = false,
  });

  List<String> get portNames => portInfos.map((p) => p.path).toList();

  final List<SerialPortInfo> portInfos;
  final String? selectedPortName;
  final bool isConnected;
  final int baudRate;
  final bool autoReconnect;

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

class AndroidUsbSerialState {
  const AndroidUsbSerialState({
    this.devices = const [],
    this.selectedPortName,
    this.isConnected = false,
    this.baudRate = 115200,
    this.autoReconnect = false,
  });

  final List<UsbDevice> devices;
  final String? selectedPortName;
  final bool isConnected;
  final int baudRate;
  final bool autoReconnect;

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
