import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/board_manager/serial_data_callbacks_provider.dart';
import 'android_usb_serial_provider.dart';
import 'desktop_usb_serial_provider.dart';

dynamic getUsbSerialProvider() {
  if (Platform.isAndroid) {
    return androidUsbSerialProvider;
  } else {
    return desktopUsbSerialProvider;
  }
}

final FutureProvider exitRawRepl = FutureProvider((ref) async {
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
  ref.read(serialDataCallbacksProvider.notifier).add(callback);

  timeoutTimer = Timer(Duration(seconds: 10), () {
    completed = true; // 标记为已完成

    // 移除回调
    ref.read(serialDataCallbacksProvider.notifier).remove(callback);

    if (!completer.isCompleted) {
      completer.complete(false);
    }
  });

  ref.read(getUsbSerialProvider().notifier).sendCommand("\x02");

  try {
    return await completer.future;
  } finally {
    // 确保回调被移除
    completed = true;
    ref.read(serialDataCallbacksProvider.notifier).remove(callback);
  }
});
