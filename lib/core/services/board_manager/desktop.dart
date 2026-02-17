import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:pyrite_ide/core/services/board_manager/main.dart';
import 'package:pyrite_ide/core/services/editor.dart';

StateProvider<List<String>> ports = StateProvider<List<String>>((ref) => []);
StateProvider<String?> selectedPortName = StateProvider<String?>((ref) => null);
StateProvider<SerialPort?> selectedPort = StateProvider<SerialPort?>(
  (ref) => null,
);
StateProvider<StreamSubscription<Uint8List>?> subscriptionProvider =
    StateProvider<StreamSubscription<Uint8List>?>((ref) => null);

void update(WidgetRef ref) {
  ref.read(ports.notifier).state = SerialPort.availablePorts.toSet().toList();
  ref.read(connectState.notifier).state = getConnectState(ref);
  // print(getConnectState(ref));
}

void connectPort(WidgetRef ref, String name) async {
  ref.read(selectedPortName.notifier).state = name;
  ref.read(selectedPort.notifier).state = SerialPort(name);
  ref.read(selectedPort.notifier).state = SerialPort(name);
  final bool connectState = ref
      .read(selectedPort.notifier)
      .state!
      .openReadWrite();
  SerialPortConfig config = SerialPortConfig();
  if (connectState) {
    config.baudRate = 115200;
    config.bits = 8;
    config.parity = SerialPortParity.none;
    config.stopBits = 1;
    final SerialPortReader reader = SerialPortReader(
      ref.read(selectedPort.notifier).state!,
      timeout: 3,
    );
    ref.read(subscriptionProvider.notifier).state = reader.stream.listen((
      data,
    ) {
      repl.write(utf8.decode(data));
    });
    update(ref);
  }
}

void dicconnectPort(WidgetRef ref) {
  ref.read(subscriptionProvider.notifier).state?.cancel();
  ref.read(subscriptionProvider.notifier).state = null;
  ref.read(selectedPort.notifier).state = null;
}

bool getConnectState(WidgetRef ref) {
  if (ref.read(selectedPortName) == null) return false;

  if (SerialPort(ref.read(selectedPortName)!).serialNumber == null) {
    dicconnectPort(ref);
    return false;
  }

  if (ref.read(subscriptionProvider.notifier).state != null) return true;

  return false;
}

void sendCommand(WidgetRef ref, String command) {
  if (ref.read(selectedPortName) != null) {
    ref.read(selectedPort.notifier).state!.write(utf8.encode("$command\r\n"));
  }
}
