import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:pyrite_ide/core/services/editor.dart';

StateProvider<List<UsbDevice>> devices = StateProvider<List<UsbDevice>>(
  (ref) => [],
);
StateProvider<UsbPort?> selectedPort = StateProvider<UsbPort?>((ref) => null);
StateProvider<StreamSubscription<Uint8List>?> subscriptionProvider =
    StateProvider<StreamSubscription<Uint8List>?>((ref) => null);

void updateDeviceList(WidgetRef ref) async {
  var c = await UsbSerial.listDevices();
  ref.read(devices.notifier).state = await UsbSerial.listDevices();
}

void connectPort(WidgetRef ref, UsbDevice device) async {
  UsbPort? port = await device.create();
  ref.read(selectedPort.notifier).state = port;
  if (port == null) return;
  final bool connectState = await port.open();

  if (connectState) {
    await port.setPortParameters(
      115200,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );
    StreamSubscription<Uint8List>? subscription = ref
        .read(subscriptionProvider.notifier)
        .state;
    subscription = port.inputStream!.listen((data) {
      print(data);
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
