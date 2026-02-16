import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:pyrite_ide/core/services/editor.dart';

StateProvider<List<String>> ports = StateProvider<List<String>>((ref) => []);
StateProvider<SerialPort?> selectedPort = StateProvider<SerialPort?>(
  (ref) => null,
);
StateProvider<StreamSubscription<Uint8List>?> subscriptionProvider =
    StateProvider<StreamSubscription<Uint8List>?>((ref) => null);

void updatePortList(WidgetRef ref) {
  ref.read(ports.notifier).state = SerialPort.availablePorts;
}

void connectPort(WidgetRef ref, String name) async {
  SerialPort? port = ref.read(selectedPort.notifier).state;
  port = SerialPort(name);
  final bool connectState = port.openReadWrite();
  SerialPortConfig config = SerialPortConfig();
  if (connectState) {
    config.baudRate = 115200;
    config.bits = 8;
    config.parity = SerialPortParity.none;
    config.stopBits = 1;
    final SerialPortReader reader = SerialPortReader(port, timeout: 3);
    StreamSubscription<Uint8List>? subscription = ref
        .read(subscriptionProvider.notifier)
        .state;
    subscription = reader.stream.listen((data) {
      repl.write(utf8.decode(data));
    });
  }
}

void dicconnectPort(WidgetRef ref) {
  StreamSubscription<Uint8List>? subscription = ref
      .read(subscriptionProvider.notifier)
      .state;
  subscription?.cancel();
  subscription = null;
}

bool getConnectState(WidgetRef ref) {
  final StreamSubscription<Uint8List>? subscription = ref
      .read(subscriptionProvider.notifier)
      .state;

  if (subscription != null) return true;

  return false;
}
