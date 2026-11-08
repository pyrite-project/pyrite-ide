import 'package:flutter/foundation.dart';
import 'package:flserial/serial_scanner.dart';
import 'package:pyrite_ide/core/models/serial_port_descriptor.dart';
import 'package:pyrite_ide/core/services/serial/base_usb_serial.dart';

class SerialProviderState extends UsbSerialState {
  const SerialProviderState({
    this.ports = const [],
    super.selectedPortName,
    super.isConnected,
    super.baudRate,
    super.autoReconnect,
  });

  /// Every port the scan found, including ones the device list hides, so a
  /// session open on a hidden port is not mistaken for an unplugged device.
  final List<SerialPortDescriptor> ports;

  List<String> get portNames => ports.map((p) => p.path).toList();

  /// flserial-shaped view of [ports] for the plugin SDK.
  List<SerialPortInfo> get portInfos => ports.map((p) => p.toBasic()).toList();

  @override
  SerialProviderState copyWith({
    List<SerialPortDescriptor>? ports,
    String? selectedPortName,
    bool? isConnected,
    int? baudRate,
    bool? autoReconnect,
    bool clearSelectedPort = false,
  }) {
    return SerialProviderState(
      ports: ports ?? this.ports,
      selectedPortName: clearSelectedPort
          ? null
          : selectedPortName ?? this.selectedPortName,
      isConnected: isConnected ?? this.isConnected,
      baudRate: baudRate ?? this.baudRate,
      autoReconnect: autoReconnect ?? this.autoReconnect,
    );
  }
}

typedef SerialDataCallback = void Function(Uint8List data);
