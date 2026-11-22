import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/api/sdk_response.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';

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

  // Multi-device sessions. The commands above keep addressing the active
  // device; these expose the other open ports so a plugin can drive two boards
  // at once instead of being limited to whichever one the user is looking at.
  static const String listSessions = 'sdk.serial.list_sessions';
  static const String activateSession = 'sdk.serial.activate_session';
  static const String closeSession = 'sdk.serial.close_session';
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
    runManager.registerHandler(
      SdkSerialCommands.listSessions,
      _handleListSessions,
    );
    runManager.registerHandler(
      SdkSerialCommands.activateSession,
      _handleActivateSession,
    );
    runManager.registerHandler(
      SdkSerialCommands.closeSession,
      _handleCloseSession,
    );
  }

  void _handleListSessions(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final sessions = ref.read(serialProvider.notifier).sessions.sessions;
    respondOk(
      envelope,
      respond,
      data: [
        for (final session in sessions)
          {
            'id': session.id,
            'port': session.portPath,
            'baud_rate': session.baudRate,
            'is_active': session.isActive,
          },
      ],
    );
  }

  void _handleActivateSession(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = _payload(envelope);
    final id = payload['id']?.toString() ?? payload['session_id']?.toString();
    if (id == null || id.isEmpty) {
      respondError(envelope, respond, 'Missing session id');
      return;
    }
    final notifier = ref.read(serialProvider.notifier);
    if (!notifier.sessions.sessions.any((session) => session.id == id)) {
      respondError(envelope, respond, 'No such serial session: $id');
      return;
    }
    notifier.activateSession(id);
    _handleGetStatus(envelope, respond);
  }

  Future<void> _handleCloseSession(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = _payload(envelope);
    final id = payload['id']?.toString() ?? payload['session_id']?.toString();
    if (id == null || id.isEmpty) {
      respondError(envelope, respond, 'Missing session id');
      return;
    }
    final notifier = ref.read(serialProvider.notifier);
    final session = notifier.sessions.sessions
        .where((item) => item.id == id)
        .firstOrNull;
    if (session == null) {
      respondError(envelope, respond, 'No such serial session: $id');
      return;
    }
    await notifier.closeSessionFor(session.portPath);
    _handleGetStatus(envelope, respond);
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
    respondOk(
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
    respondOk(
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
      respondError(envelope, respond, 'Missing serial port');
      return;
    }

    try {
      await ref.read(serialProvider.notifier).connectPort(port);
      _handleGetStatus(envelope, respond);
    } catch (e) {
      respondError(envelope, respond, e.toString());
    }
  }

  Future<void> _handleDisconnect(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    try {
      await ref.read(serialProvider.notifier).disconnectPort();
      respondOk(envelope, respond);
    } catch (e) {
      respondError(envelope, respond, e.toString());
    }
  }

  void _handleSend(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    if (!_isConnected) {
      respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = _payload(envelope);
    final data = payload['data'];
    final bytes = _bytesFrom(data);
    if (bytes == null) {
      respondError(envelope, respond, 'Invalid serial data');
      return;
    }
    ref.read(serialProvider.notifier).sendBytes(Uint8List.fromList(bytes));
    respondOk(envelope, respond, data: bytes.length);
  }

  void _handleSendCommand(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    if (!_isConnected) {
      respondError(envelope, respond, '设备未连接');
      return;
    }
    final payload = _payload(envelope);
    final command = payload['command']?.toString();
    if (command == null) {
      respondError(envelope, respond, 'Missing command');
      return;
    }
    ref
        .read(serialProvider.notifier)
        .sendCommand(command, chunked: payload['chunked'] != false);
    respondOk(envelope, respond);
  }

  Future<void> _handleRead(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = _payload(envelope);
    final timeoutMs = (payload['timeout_ms'] as num?)?.toInt() ?? 1000;
    final maxBytes = (payload['max_bytes'] as num?)?.toInt();
    // Zero is meaningful (read nothing); a negative count has no meaning and
    // would surface as a RangeError from `sublist` only after the read timed
    // out, leaving the caller without an answer.
    if (maxBytes != null && maxBytes < 0) {
      respondError(envelope, respond, 'max_bytes must not be negative');
      return;
    }
    if (!_isConnected) {
      respondError(envelope, respond, '设备未连接');
      return;
    }
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
    respondOk(
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
      respondError(envelope, respond, 'Missing Python code');
      return;
    }
    final timeoutMs = (payload['timeout_ms'] as num?)?.toInt() ?? 20000;
    try {
      final output = await runPythonOnDevice(
        ref,
        code,
        timeout: Duration(milliseconds: timeoutMs),
      );
      respondOk(envelope, respond, data: output);
    } catch (e) {
      respondError(envelope, respond, e.toString());
    }
  }

  Future<void> _handleHardwareReset(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    if (!_isConnected) {
      respondError(envelope, respond, '设备未连接');
      return;
    }
    try {
      final accepted = await hardwareResetDevice(ref.read);
      if (!accepted) {
        respondError(envelope, respond, 'Hardware reset is disabled');
        return;
      }
      respondOk(envelope, respond, data: true);
    } catch (e) {
      respondError(envelope, respond, e.toString());
    }
  }

  void _handleSetBaudRate(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final value = (_payload(envelope)['value'] as num?)?.toInt();
    if (value == null) {
      respondError(envelope, respond, 'Missing baud rate');
      return;
    }
    ref.read(serialProvider.notifier).setBaudRate(value);
    respondOk(envelope, respond);
  }

  void _handleSetAutoReconnect(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final value = _payload(envelope)['value'];
    ref.read(serialProvider.notifier).setAutoReconnect(value == true);
    respondOk(envelope, respond);
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
