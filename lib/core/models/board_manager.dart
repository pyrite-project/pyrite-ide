import 'package:flutter/foundation.dart';
import 'package:flserial/serial_scanner.dart';
import 'package:pyrite_ide/core/services/serial/base_usb_serial.dart';

class SerialProviderState extends UsbSerialState {
  const SerialProviderState({
    this.portInfos = const [],
    super.selectedPortName,
    super.isConnected,
    super.baudRate,
    super.autoReconnect,
  });

  List<String> get portNames => portInfos.map((p) => p.path).toList();

  final List<SerialPortInfo> portInfos;

  @override
  SerialProviderState copyWith({
    List<SerialPortInfo>? portInfos,
    String? selectedPortName,
    bool? isConnected,
    int? baudRate,
    bool? autoReconnect,
    bool clearSelectedPort = false,
  }) {
    return SerialProviderState(
      portInfos: portInfos ?? this.portInfos,
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
