import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:usb_serial/usb_serial.dart';

class DesktopUsbSerialState {
  const DesktopUsbSerialState({
    this.portNames = const [],
    this.selectedPortName,
    this.selectedPort,
    this.subscription,
    this.isConnected = false,
  });

  final List<String> portNames;
  final String? selectedPortName;
  final SerialPort? selectedPort;
  final StreamSubscription<Uint8List>? subscription;
  final bool isConnected;

  DesktopUsbSerialState copyWith({
    List<String>? portNames,
    String? selectedPortName,
    SerialPort? selectedPort,
    StreamSubscription<Uint8List>? subscription,
    bool? isConnected,
  }) {
    return DesktopUsbSerialState(
      portNames: portNames ?? this.portNames,
      selectedPortName: selectedPortName ?? this.selectedPortName,
      selectedPort: selectedPort ?? this.selectedPort,
      subscription: subscription ?? this.subscription,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

class AndroidUsbSerialState {
  const AndroidUsbSerialState({
    this.devices = const [],
    this.selectedPortName,
    this.selectedDevice,
    this.selectedPort,
    this.subscription,
    this.isConnected = false,
  });

  final List<UsbDevice> devices;
  final String? selectedPortName;
  final UsbDevice? selectedDevice;
  final UsbPort? selectedPort;
  final StreamSubscription<Uint8List>? subscription;
  final bool isConnected;

  AndroidUsbSerialState copyWith({
    List<UsbDevice>? devices,
    String? selectedPortName,
    UsbDevice? selectedDevice,
    UsbPort? selectedPort,
    StreamSubscription<Uint8List>? subscription,
    bool? isConnected,
  }) {
    return AndroidUsbSerialState(
      devices: devices ?? this.devices,
      selectedPortName: selectedPortName ?? this.selectedPortName,
      selectedDevice: selectedDevice ?? this.selectedDevice,
      selectedPort: selectedPort ?? this.selectedPort,
      subscription: subscription ?? this.subscription,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

typedef SerialDataCallback = void Function(Uint8List data);
