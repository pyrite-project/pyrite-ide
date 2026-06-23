import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/board_manager/repl_io.dart';
import 'package:pyrite_ide/core/services/board_manager/serial_data_callbacks_provider.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/periodic_task/provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:usb_serial/usb_serial.dart';

class AndroidUsbSerialNotifier extends StateNotifier<AndroidUsbSerialState> {
  final Ref ref;

  AndroidUsbSerialNotifier(this.ref) : super(const AndroidUsbSerialState());

  void _update() async {
    state = state.copyWith(devices: await UsbSerial.listDevices());
    state = state.copyWith(isConnected: _getConnectState());
  }

  void refresh() {
    _update();
  }

  void connectPort(UsbDevice device) async {
    bindReplOnOutputCallback();
    state = state.copyWith(
      selectedDevice: device,
      selectedPort: await device.create(),
      selectedPortName: device.deviceName,
    );
    if (state.selectedPort == null) return;
    final bool openState = await state.selectedPort!.open();

    if (openState) {
      await state.selectedPort!.setPortParameters(
        115200,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );
      state = state.copyWith(
        subscription: state.selectedPort!.inputStream!.listen((data) {
          repl.write(utf8.decode(data));
          for (void Function(Uint8List data) callback in ref.read(
            serialDataCallbacksProvider,
          )) {
            callback(data);
          }
        }),
      );
      _update();
    }
  }

  void dicconnectPort() {
    state.subscription?.cancel();
    state = state.copyWith(
      selectedDevice: null,
      selectedPort: null,
      selectedPortName: null,
    );
  }

  bool _getConnectState() {
    if (state.selectedPortName == null) return false;

    List<String> portNames = [];
    for (var device in state.devices) {
      portNames.add(device.deviceName);
    }

    // usb_serial 库保证了设备列表随硬件接入/弹出事件而及时变动，故这里采用判断 selectedPortName 是否位于列表中来判断连接状态
    if (!portNames.contains(state.selectedPortName)) return false;

    if (state.subscription != null) return true;

    return false;
  }

  void setBaudRate(int value) {
    state = state.copyWith(baudRate: value);
  }

  void setAutoReconnect(bool value) {
    state = state.copyWith(autoReconnect: value);
  }

  void sendBytes(Uint8List bytes) {
    state.selectedPort!.write(bytes);
  }

  void sendCommand(String command, {bool chunked = true}) {
    if (chunked && command.length > 64) {
      _sendChunkedCommand(command);
    } else {
      _sendDirectCommand(command);
    }
  }

  // 直接发送命令
  void _sendDirectCommand(String command) {
    state.selectedPort!.write(utf8.encode(command));
  }

  // 分块发送命令
  void _sendChunkedCommand(String command) async {
    const chunkSize = 32; // 较小的块大小，避免缓冲区溢出
    for (int i = 0; i < command.length; i += chunkSize) {
      final end = (i + chunkSize < command.length)
          ? i + chunkSize
          : command.length;
      final chunk = command.substring(i, end);
      _sendDirectCommand(chunk);
      await Future.delayed(Duration(milliseconds: 2)); // 块间延迟
    }
  }

  Future<bool> enterRawRepl() async {
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
    ref.read(serialDataCallbacksProvider.notifier).add(callback);

    timeoutTimer = Timer(Duration(seconds: 10), () {
      completed = true; // 标记为已完成

      // 移除回调
      ref.read(serialDataCallbacksProvider.notifier).remove(callback);

      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    sendCommand("\x01");

    try {
      return await completer.future;
    } finally {
      // 确保回调被移除
      completed = true;
      ref.read(serialDataCallbacksProvider.notifier).remove(callback);
    }
  }

  Future<bool> exitRawRepl() async {
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

    sendCommand("\x02");

    try {
      return await completer.future;
    } finally {
      // 确保回调被移除
      completed = true;
      ref.read(serialDataCallbacksProvider.notifier).remove(callback);
    }
  }

  void registerUpdateTask() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(periodicTaskManagerProvider)
          .registerTask(
            name: "port_message_update",
            interval: const Duration(seconds: 1),
            callback: () => _update(),
          );
    });
  }

  void bindReplOnOutputCallback() {
    repl.onOutput = (String data) {
      final encode = ref.read(chineseToUnicodeConversion);
      sendCommand(encode ? ReplInputEncoder.encode(data) : data);
    };
  }
}

final StateNotifierProvider<AndroidUsbSerialNotifier, AndroidUsbSerialState>
androidUsbSerialProvider = StateNotifierProvider(
  (ref) => AndroidUsbSerialNotifier(ref),
);
