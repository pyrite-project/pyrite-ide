import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/board_manager/main.dart';
import 'package:pyrite_ide/core/services/editor/main.dart';

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

void connectPort(WidgetRef ref, String name) {
  ref.read(selectedPortName.notifier).state = name;
  ref.read(selectedPort.notifier).state = SerialPort(name);
  ref.read(selectedPort.notifier).state = SerialPort(name);
  final bool state = ref.read(selectedPort.notifier).state!.openReadWrite();
  SerialPortConfig config = SerialPortConfig();
  if (state) {
    config.baudRate = 115200;
    config.bits = 8;
    config.parity = SerialPortParity.none;
    config.stopBits = 1;
    final SerialPortReader reader = SerialPortReader(
      ref.read(selectedPort.notifier).state!,
    );
    ref.read(subscriptionProvider.notifier).state = reader.stream.listen((
      data,
    ) {
      repl.write(utf8.decode(data));
      // print(utf8.decode(data));
      for (void Function(Uint8List data) callback in container.read(
        serialDataCallbacks,
      )) {
        callback(data);
        print(callback);
      }
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

// 添加分块发送的参数
void sendCommand(dynamic ref, String command, {bool chunked = true}) {
  if (chunked && command.length > 64) {
    _sendChunkedCommand(ref, command);
  } else {
    _sendDirectCommand(ref, command);
  }
}

// 直接发送命令
void _sendDirectCommand(dynamic ref, String command) {
  ref.read(selectedPort.notifier).state?.write(utf8.encode(command));
}

// 分块发送命令
void _sendChunkedCommand(dynamic ref, String command) async {
  const chunkSize = 32; // 较小的块大小，避免缓冲区溢出
  for (int i = 0; i < command.length; i += chunkSize) {
    final end = (i + chunkSize < command.length)
        ? i + chunkSize
        : command.length;
    final chunk = command.substring(i, end);
    _sendDirectCommand(ref, chunk);
    await Future.delayed(Duration(milliseconds: 2)); // 块间延迟
  }
}
