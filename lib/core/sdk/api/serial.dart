import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/serial/android_usb_serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/desktop_usb_serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/serial_data_callbacks_provider.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';

abstract class SdkSerialCommands {
  static const String listPorts = 'sdk.serial.list_ports';
  static const String getStatus = 'sdk.serial.get_status';
  static const String read = 'sdk.serial.read';
  static const String connect = 'sdk.serial.connect';
  static const String disconnect = 'sdk.serial.disconnect';
  static const String send = 'sdk.serial.send';
  static const String sendCommand = 'sdk.serial.send_command';
  static const String runPython = 'sdk.serial.run_python';
  static const String setBaudRate = 'sdk.serial.set_baud_rate';
  static const String setAutoReconnect = 'sdk.serial.set_auto_reconnect';
}

class SdkSerial extends StateNotifier<PluginRunManager?> {
  final Ref ref;
  SdkSerial(this.ref) : super(null);

  void bind(PluginRunManager runManager) {
    state = runManager;
    runManager.registerHandler(SdkSerialCommands.listPorts, _handleListPorts);
    runManager.registerHandler(SdkSerialCommands.getStatus, _handleGetStatus);
    runManager.registerHandler(SdkSerialCommands.read, _handleRead);
    runManager.registerHandler(SdkSerialCommands.connect, _handleConnect);
    runManager.registerHandler(SdkSerialCommands.disconnect, _handleDisconnect);
    runManager.registerHandler(SdkSerialCommands.send, _handleSend);
    runManager.registerHandler(
      SdkSerialCommands.sendCommand,
      _handleSendCommand,
    );
    runManager.registerHandler(SdkSerialCommands.runPython, _handleRunPython);
    runManager.registerHandler(
      SdkSerialCommands.setBaudRate,
      _handleSetBaudRate,
    );
    runManager.registerHandler(
      SdkSerialCommands.setAutoReconnect,
      _handleSetAutoReconnect,
    );
  }

  void _respondOk(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond, {
    dynamic data,
  }) {
    respond(
      makeEnvelope(
        type: SdkCommands.responseOk,
        payload: {'data': data},
        replyTo: envelope['id']?.toString(),
      ),
    );
  }

  void _respondError(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    String message,
  ) {
    respond(
      makeEnvelope(
        type: SdkCommands.responseError,
        payload: {'message': message},
        replyTo: envelope['id']?.toString(),
      ),
    );
  }

  Map<String, dynamic> _payload(Map<String, dynamic> envelope) {
    final payload = envelope['payload'];
    return payload is Map<String, dynamic> ? payload : <String, dynamic>{};
  }

  dynamic get _serialProvider => getUsbSerialProvider();

  bool get _isConnected => ref.read(_serialProvider).isConnected == true;

  Future<void> _handleListPorts(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (Platform.isAndroid) {
      await ref.read(androidUsbSerialProvider.notifier).refresh();
      final state = ref.read(androidUsbSerialProvider);
      _respondOk(
        envelope,
        respond,
        data: state.devices
            .map(
              (device) => {
                'name': device.deviceName,
                'path': device.deviceName,
                'manufacturer': device.manufacturerName,
                'product': device.productName,
              },
            )
            .toList(),
      );
      return;
    }

    await ref.read(desktopUsbSerialProvider.notifier).refresh();
    final state = ref.read(desktopUsbSerialProvider);
    _respondOk(
      envelope,
      respond,
      data: state.portInfos
          .map(
            (port) => {
              'name': port.path,
              'path': port.path,
              'description': port.description,
            },
          )
          .toList(),
    );
  }

  void _handleGetStatus(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final state = ref.read(_serialProvider);
    _respondOk(
      envelope,
      respond,
      data: {
        'platform': Platform.isAndroid ? 'android' : 'desktop',
        'is_connected': state.isConnected == true,
        'selected_port': state.selectedPortName,
        'baud_rate': state.baudRate,
        'auto_reconnect': state.autoReconnect,
      },
    );
  }

  Future<void> _handleConnect(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = _payload(envelope);
    final port = payload['port']?.toString() ?? payload['path']?.toString();
    if (port == null || port.isEmpty) {
      _respondError(envelope, respond, 'Missing serial port');
      return;
    }

    try {
      if (Platform.isAndroid) {
        await ref.read(androidUsbSerialProvider.notifier).refresh();
        final devices = ref.read(androidUsbSerialProvider).devices;
        final device = devices.where((d) => d.deviceName == port).firstOrNull;
        if (device == null) {
          _respondError(envelope, respond, 'Serial port not found: $port');
          return;
        }
        await ref.read(androidUsbSerialProvider.notifier).connectPort(device);
      } else {
        await ref.read(desktopUsbSerialProvider.notifier).connectPort(port);
      }
      _handleGetStatus(envelope, respond);
    } catch (e) {
      _respondError(envelope, respond, e.toString());
    }
  }

  Future<void> _handleDisconnect(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    try {
      await ref.read(_serialProvider.notifier).dicconnectPort();
      _respondOk(envelope, respond);
    } catch (e) {
      _respondError(envelope, respond, e.toString());
    }
  }

  void _handleSend(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    if (!_isConnected) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = _payload(envelope);
    final data = payload['data'];
    final bytes = _bytesFrom(data);
    if (bytes == null) {
      _respondError(envelope, respond, 'Invalid serial data');
      return;
    }
    ref.read(_serialProvider.notifier).sendBytes(Uint8List.fromList(bytes));
    _respondOk(envelope, respond, data: bytes.length);
  }

  void _handleSendCommand(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    if (!_isConnected) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = _payload(envelope);
    final command = payload['command']?.toString();
    if (command == null) {
      _respondError(envelope, respond, 'Missing command');
      return;
    }
    ref
        .read(_serialProvider.notifier)
        .sendCommand(command, chunked: payload['chunked'] != false);
    _respondOk(envelope, respond);
  }

  Future<void> _handleRead(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (!_isConnected) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = _payload(envelope);
    final timeoutMs = (payload['timeout_ms'] as num?)?.toInt() ?? 1000;
    final maxBytes = (payload['max_bytes'] as num?)?.toInt();
    final buffer = <int>[];
    final completer = Completer<void>();

    void callback(Uint8List data) {
      buffer.addAll(data);
      if (maxBytes != null && buffer.length >= maxBytes && !completer.isCompleted) {
        completer.complete();
      }
    }

    ref.read(serialDataCallbacksProvider.notifier).add(callback);
    try {
      await completer.future.timeout(Duration(milliseconds: timeoutMs));
    } on TimeoutException {
      // Returning the bytes received before timeout is intentional.
    } finally {
      ref.read(serialDataCallbacksProvider.notifier).remove(callback);
    }

    final data = maxBytes == null || buffer.length <= maxBytes
        ? buffer
        : buffer.sublist(0, maxBytes);
    _respondOk(
      envelope,
      respond,
      data: {
        'data': data,
        'text': utf8.decode(data, allowMalformed: true),
      },
    );
  }

  Future<void> _handleRunPython(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = _payload(envelope);
    final code = payload['code']?.toString();
    if (code == null) {
      _respondError(envelope, respond, 'Missing Python code');
      return;
    }
    final timeoutMs = (payload['timeout_ms'] as num?)?.toInt() ?? 20000;
    try {
      final output = await runPythonOnDevice(
        ref,
        code,
        timeout: Duration(milliseconds: timeoutMs),
      );
      _respondOk(envelope, respond, data: output);
    } catch (e) {
      _respondError(envelope, respond, e.toString());
    }
  }

  void _handleSetBaudRate(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final value = (_payload(envelope)['value'] as num?)?.toInt();
    if (value == null) {
      _respondError(envelope, respond, 'Missing baud rate');
      return;
    }
    ref.read(_serialProvider.notifier).setBaudRate(value);
    _respondOk(envelope, respond);
  }

  void _handleSetAutoReconnect(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final value = _payload(envelope)['value'];
    ref.read(_serialProvider.notifier).setAutoReconnect(value == true);
    _respondOk(envelope, respond);
  }

  List<int>? _bytesFrom(dynamic data) {
    if (data is String) return utf8.encode(data);
    if (data is List) {
      final result = <int>[];
      for (final item in data) {
        if (item is! num) return null;
        result.add(item.toInt() & 0xff);
      }
      return result;
    }
    return null;
  }
}

final sdkSerialProvider =
    StateNotifierProvider<SdkSerial, PluginRunManager?>((ref) {
  return SdkSerial(ref);
});
