import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';

abstract class SdkSerialCommands {
  static const String listPorts = 'sdk.serial.list_ports';
  static const String getStatus = 'sdk.serial.get_status';
  static const String read = 'sdk.serial.read';
  static const String connect = 'sdk.serial.connect';
  static const String disconnect = 'sdk.serial.disconnect';
  static const String send = 'sdk.serial.send';
  static const String sendCommand = 'sdk.serial.send_command';
  static const String runPython = 'sdk.serial.run_python';
  static const String hardwareReset = 'sdk.serial.hardware_reset';
  static const String setBaudRate = 'sdk.serial.set_baud_rate';
  static const String setAutoReconnect = 'sdk.serial.set_auto_reconnect';
}

class SdkSerial {
  final Ref ref;
  SdkSerial(this.ref);

  void bind(PluginRunManager runManager) {
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
      SdkSerialCommands.hardwareReset,
      _handleHardwareReset,
    );
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

  bool get _isConnected => ref.read(serialProvider).isConnected == true;

  Future<void> _handleListPorts(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    await ref.read(serialProvider.notifier).refresh();
    final state = ref.read(serialProvider);
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
    final state = ref.read(serialProvider);
    final hardwareResetStrategy = ref.read(hardwareResetStrategyProvider);
    _respondOk(
      envelope,
      respond,
      data: {
        'is_connected': state.isConnected,
        'selected_port': state.selectedPortName,
        'baud_rate': state.baudRate,
        'auto_reconnect': state.autoReconnect,
        'hardware_reset_strategy': hardwareResetStrategy.name,
        'hardware_reset_enabled':
            hardwareResetStrategy != HardwareResetStrategy.disabled,
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
      await ref.read(serialProvider.notifier).connectPort(port);
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
      await ref.read(serialProvider.notifier).disconnectPort();
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
    ref.read(serialProvider.notifier).sendBytes(Uint8List.fromList(bytes));
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
        .read(serialProvider.notifier)
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
      if (maxBytes != null &&
          buffer.length >= maxBytes &&
          !completer.isCompleted) {
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
      data: {'data': data, 'text': utf8.decode(data, allowMalformed: true)},
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

  Future<void> _handleHardwareReset(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (!_isConnected) {
      _respondError(envelope, respond, '设备未连接');
      return;
    }
    try {
      final accepted = await hardwareResetDevice(ref.read);
      if (!accepted) {
        _respondError(envelope, respond, 'Hardware reset is disabled');
        return;
      }
      _respondOk(envelope, respond, data: true);
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
    ref.read(serialProvider.notifier).setBaudRate(value);
    _respondOk(envelope, respond);
  }

  void _handleSetAutoReconnect(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final value = _payload(envelope)['value'];
    ref.read(serialProvider.notifier).setAutoReconnect(value == true);
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

final Provider<SdkSerial> sdkSerialProvider = Provider(SdkSerial.new);
