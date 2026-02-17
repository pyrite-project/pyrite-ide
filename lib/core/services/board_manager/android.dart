import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/board_manager/main.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:pyrite_ide/core/services/editor.dart';

StateProvider<List<UsbDevice>> devices = StateProvider<List<UsbDevice>>(
  (ref) => [],
);
StateProvider<UsbDevice?> selectedDevice = StateProvider<UsbDevice?>(
  (ref) => null,
);
StateProvider<String?> selectedPortName = StateProvider<String?>((ref) => null);
StateProvider<StreamSubscription<Uint8List>?> subscriptionProvider =
    StateProvider<StreamSubscription<Uint8List>?>((ref) => null);
StateProvider<UsbPort?> selectedPort = StateProvider<UsbPort?>((ref) => null);

void update(WidgetRef ref) async {
  ref.read(devices.notifier).state = await UsbSerial.listDevices();
  ref.read(connectState.notifier).state = getConnectState(ref);
}

void connectPort(WidgetRef ref, UsbDevice device) async {
  ref.read(selectedPort.notifier).state = await device.create();
  ref.read(selectedDevice.notifier).state = device;
  ref.read(selectedPortName.notifier).state = device.deviceName;
  if (ref.read(selectedPort.notifier).state == null) return;
  final bool state = await ref.read(selectedPort.notifier).state!.open();

  if (state) {
    await ref
        .read(selectedPort.notifier)
        .state!
        .setPortParameters(
          115200,
          UsbPort.DATABITS_8,
          UsbPort.STOPBITS_1,
          UsbPort.PARITY_NONE,
        );
    ref.read(subscriptionProvider.notifier).state = ref
        .read(selectedPort.notifier)
        .state!
        .inputStream!
        .listen((data) {
          repl.write(utf8.decode(data));
        });
    update(ref);
    ref.read(connectState.notifier).state = state;
  }
}

void dicconnectPort(WidgetRef ref) {
  StreamSubscription<Uint8List>? subscription = ref
      .read(subscriptionProvider.notifier)
      .state;
  subscription?.cancel();
  subscription = null;
  ref.read(selectedPortName.notifier).state = null;
  ref.read(selectedPort.notifier).state = null;
  ref.read(connectState.notifier).state = false;
}

bool getConnectState(WidgetRef ref) {
  if (ref.read(selectedPortName) == null) return false;

  List<String> portNames = [];
  for (var device in ref.read(devices)) {
    portNames.add(device.deviceName);
  }

  // usb_serial 库保证了设备列表随硬件接入/弹出事件而及时变动，故这里采用判断 selectedPortName 是否位于列表中来判断连接状态
  if (!portNames.contains(ref.read(selectedPortName))) return false;

  if (ref.read(subscriptionProvider.notifier).state != null) return true;

  return false;
}

void sendCommand(WidgetRef ref, String command) {
  if (ref.read(selectedPortName) != null) {
    ref.read(selectedPort.notifier).state!.write(utf8.encode("$command\r\n"));
  }
}
