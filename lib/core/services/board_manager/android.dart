import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/board_manager/main.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:pyrite_ide/core/services/editor/main.dart';

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
          for (void Function(Uint8List data) callback in container.read(
            serialDataCallbacks,
          )) {
            callback(data);
          }
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

// 添加分块发送的参数
void sendCommand(WidgetRef ref, String command, {bool chunked = true}) {
  if (chunked && command.length > 64) {
    _sendChunkedCommand(ref, command);
  } else {
    _sendDirectCommand(ref, command);
  }
}

// 直接发送命令
void _sendDirectCommand(WidgetRef ref, String command) {
  ref
      .read(selectedPort.notifier)
      .state
      ?.write(Uint8List.fromList(command.codeUnits));
}

// 分块发送命令
void _sendChunkedCommand(WidgetRef ref, String command) async {
  const chunkSize = 16; // 较小的块大小，避免缓冲区溢出
  for (int i = 0; i < command.length; i += chunkSize) {
    final end = (i + chunkSize < command.length)
        ? i + chunkSize
        : command.length;
    final chunk = command.substring(i, end);
    _sendDirectCommand(ref, chunk);
    await Future.delayed(Duration(milliseconds: 1)); // 块间延迟
  }
}
