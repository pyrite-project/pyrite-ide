import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/board.dart';
import 'package:usb_serial/usb_serial.dart';
import 'android.dart' as android;
import 'desktop.dart' as desktop;

StateProvider<bool> connectState = StateProvider<bool>((ref) => false);
StateProvider<List<void Function(Uint8List data)>> serialDataCallbacks =
    StateProvider((ref) => []);

void sendCommand(WidgetRef ref, String command) {
  if (Platform.isAndroid) {
    android.sendCommand(ref, command);
  } else {
    desktop.sendCommand(ref, command);
  }
}

void connectPort(WidgetRef ref, dynamic device) {
  if (Platform.isAndroid && device is UsbDevice) {
    android.connectPort(ref, device);
  } else if (device is String) {
    desktop.connectPort(ref, device);
  }
}

String? getConnectedPortName(WidgetRef ref) {
  if (Platform.isAndroid && ref.read(connectState)) {
    return ref.read(android.selectedPortName);
  } else if (ref.read(connectState)) {
    return ref.watch(desktop.selectedPortName);
  }
  return null;
}

Future<bool> enterRawRepl(
  WidgetRef ref, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final completer = Completer<bool>();
  Timer? timeoutTimer;
  bool completed = false; // 添加完成标志

  // 创建并注册回调函数
  void callback(Uint8List data) {
    if (completed) return; // 如果已完成，直接返回

    if (utf8.decode(data).contains("raw REPL; CTRL-B to exit")) {
      completed = true; // 标记为已完成
      timeoutTimer?.cancel();

      // 确保只完成一次
      if (!completer.isCompleted) {
        completer.complete(true);
      }
    }
  }

  // 注册回调
  ref.read(serialDataCallbacks.notifier).state = [
    ...ref.read(serialDataCallbacks),
    callback,
  ];

  timeoutTimer = Timer(timeout, () {
    completed = true; // 标记为已完成

    // 移除回调
    ref.read(serialDataCallbacks.notifier).state = ref
        .read(serialDataCallbacks)
        .where((cb) => cb != callback)
        .toList();

    if (!completer.isCompleted) {
      completer.complete(false);
    }
  });

  sendCommand(ref, "\x01");

  try {
    return await completer.future;
  } finally {
    // 确保回调被移除
    completed = true;
    ref.read(serialDataCallbacks.notifier).state = ref
        .read(serialDataCallbacks)
        .where((cb) => cb != callback)
        .toList();
  }
}

Future<bool> exitRawRepl(
  WidgetRef ref, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final completer = Completer<bool>();
  Timer? timeoutTimer;
  bool completed = false; // 添加完成标志

  // 创建并注册回调函数
  void callback(Uint8List data) {
    if (completed) return; // 如果已完成，直接返回

    if (utf8.decode(data).contains("\r\n>>>")) {
      completed = true; // 标记为已完成
      timeoutTimer?.cancel();

      // 确保只完成一次
      if (!completer.isCompleted) {
        completer.complete(true);
      }
    }
  }

  // 注册回调
  ref.read(serialDataCallbacks.notifier).state = [
    ...ref.read(serialDataCallbacks),
    callback,
  ];

  timeoutTimer = Timer(timeout, () {
    completed = true; // 标记为已完成

    // 移除回调
    ref.read(serialDataCallbacks.notifier).state = ref
        .read(serialDataCallbacks)
        .where((cb) => cb != callback)
        .toList();

    if (!completer.isCompleted) {
      completer.complete(false);
    }
  });

  sendCommand(ref, "\x02");

  try {
    return await completer.future;
  } finally {
    // 确保回调被移除
    completed = true;
    ref.read(serialDataCallbacks.notifier).state = ref
        .read(serialDataCallbacks)
        .where((cb) => cb != callback)
        .toList();
  }
}

void update(WidgetRef ref) {
  if (Platform.isAndroid) {
    android.update(ref);
  } else {
    desktop.update(ref);
  }
}
