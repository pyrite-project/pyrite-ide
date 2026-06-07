import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/board_manager/serial_data_callbacks_provider.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/periodic_task/provider.dart';

class DesktopUsbSerialNotifier extends StateNotifier<DesktopUsbSerialState> {
  final Ref ref;

  DesktopUsbSerialNotifier(this.ref) : super(const DesktopUsbSerialState());

  void _update() {
    state = state.copyWith(
      portNames: SerialPort.availablePorts.toSet().toList(),
      isConnected: _getConnectState(),
    );
    // print(getConnectState(ref));
  }

  void refresh() {
    _update();
  }

  void connectPort(String name) {
    bindReplOnOutputCallback();
    state = state.copyWith(
      selectedPortName: name,
      selectedPort: SerialPort(name),
    );
    final bool openState = state.selectedPort!.openReadWrite();
    SerialPortConfig config = SerialPortConfig();
    if (openState) {
      config.baudRate = 115200;
      config.bits = 8;
      config.parity = SerialPortParity.none;
      config.stopBits = 1;
      final SerialPortReader reader = SerialPortReader(state.selectedPort!);
      state = state.copyWith(
        subscription: reader.stream.listen((data) {
          repl.write(utf8.decode(data));
          // print(utf8.decode(data));
          for (void Function(Uint8List data) callback in ref.read(
            serialDataCallbacksProvider,
          )) {
            callback(data);
            // print(callback);
          }
        }),
      );
      _update();
    }
  }

  void dicconnectPort() {
    state.subscription?.cancel();
    state = state.copyWith(
      selectedPortName: null,
      selectedPort: null,
      subscription: null,
    );
  }

  bool _getConnectState() {
    if (state.selectedPortName == null) return false;

    if (SerialPort(state.selectedPortName!).serialNumber == null) {
      dicconnectPort();
      return false;
    }

    if (state.subscription != null) return true;

    return false;
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
      await Future.delayed(Duration(milliseconds: 1)); // 块间延迟
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
    repl.onOutput = (String data) => sendCommand(data);
  }
}

final StateNotifierProvider<DesktopUsbSerialNotifier, DesktopUsbSerialState>
desktopUsbSerialProvider = StateNotifierProvider(
  (ref) => DesktopUsbSerialNotifier(ref),
);
