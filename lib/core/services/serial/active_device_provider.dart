import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';

enum ActiveDeviceTransport { disconnected, serial, webRepl }

ActiveDeviceTransport resolveActiveDeviceTransport({
  required bool serialConnected,
  required WebReplState webReplState,
}) {
  if (webReplState == WebReplState.connected) {
    return ActiveDeviceTransport.webRepl;
  }
  if (serialConnected) return ActiveDeviceTransport.serial;
  return ActiveDeviceTransport.disconnected;
}

final activeDeviceTransportProvider = Provider<ActiveDeviceTransport>((ref) {
  return resolveActiveDeviceTransport(
    serialConnected: ref.watch(serialProvider).isConnected,
    webReplState: ref.watch(webReplProvider).state,
  );
});

final deviceConnectedProvider = Provider<bool>((ref) {
  return ref.watch(activeDeviceTransportProvider) !=
      ActiveDeviceTransport.disconnected;
});

/// Status-bar label for the WebREPL transport.
///
/// [buildWebReplUri] throws when the configured host is empty or unparseable,
/// and a connected session outlives an edit to that setting — clearing the host
/// field used to make the label provider throw while the status bar was
/// building. The label degrades to whatever the setting still says instead.
String webReplDeviceLabel(String host, int port) {
  try {
    final uri = buildWebReplUri(host, port);
    return 'WebREPL ${uri.host}:${uri.port}';
  } on FormatException {
    final trimmed = host.trim();
    return trimmed.isEmpty ? 'WebREPL' : 'WebREPL $trimmed';
  }
}

final activeDeviceLabelProvider = Provider<String?>((ref) {
  switch (ref.watch(activeDeviceTransportProvider)) {
    case ActiveDeviceTransport.webRepl:
      return webReplDeviceLabel(ref.watch(webReplHost), ref.watch(webReplPort));
    case ActiveDeviceTransport.serial:
      return ref.watch(serialProvider).selectedPortName;
    case ActiveDeviceTransport.disconnected:
      return null;
  }
});

void sendCommandToActiveDevice(ProviderReader read, String command) {
  switch (read(activeDeviceTransportProvider)) {
    case ActiveDeviceTransport.webRepl:
      read(webReplProvider.notifier).sendCommand(command);
      return;
    case ActiveDeviceTransport.serial:
      read(serialProvider.notifier).sendCommand(command);
      return;
    case ActiveDeviceTransport.disconnected:
      return;
  }
}

Future<String> runPythonOnActiveDevice(
  Ref ref,
  String python, {
  Duration timeout = const Duration(seconds: 20),
  String runningOperationId = 'code-exec',
}) async {
  switch (ref.read(activeDeviceTransportProvider)) {
    case ActiveDeviceTransport.webRepl:
      final stdout = BytesBuilder(copy: false);
      final stderr = BytesBuilder(copy: false);
      await ref
          .read(webReplProvider.notifier)
          .executeStreaming(
            python,
            timeout: timeout,
            onStarted: () {},
            onStdout: stdout.add,
            onStderr: stderr.add,
          );
      final error = utf8.decode(stderr.takeBytes(), allowMalformed: true);
      if (error.isNotEmpty) throw DeviceSessionException(error);
      return utf8.decode(stdout.takeBytes(), allowMalformed: true);
    case ActiveDeviceTransport.serial:
      return runPythonOnDevice(
        ref,
        python,
        timeout: timeout,
        runningOperationId: runningOperationId,
      );
    case ActiveDeviceTransport.disconnected:
      throw const DeviceNotReadyException('Device not connected.');
  }
}

Future<void> runPythonOnActiveDeviceStreaming(
  WidgetRef ref,
  String python, {
  Duration startupTimeout = const Duration(seconds: 20),
  String runningOperationId = 'code-exec',
  bool softReset = false,

  /// Device directory to switch into before the script runs, or null to keep
  /// the device's working directory as-is.
  String? workingDirectory,
  required void Function() onStarted,
  required void Function(Uint8List data) onStdout,
  required void Function(Uint8List data) onStderr,
}) {
  switch (ref.read(activeDeviceTransportProvider)) {
    case ActiveDeviceTransport.webRepl:
      return ref
          .read(webReplProvider.notifier)
          .executeStreaming(
            python,
            timeout: startupTimeout,
            softReset: softReset,
            workingDirectory: workingDirectory,
            onStarted: onStarted,
            onStdout: onStdout,
            onStderr: onStderr,
          );
    case ActiveDeviceTransport.serial:
      return runPythonOnDeviceStreaming(
        ref,
        python,
        startupTimeout: startupTimeout,
        runningOperationId: runningOperationId,
        softReset: softReset,
        workingDirectory: workingDirectory,
        onStarted: onStarted,
        onStdout: onStdout,
        onStderr: onStderr,
      );
    case ActiveDeviceTransport.disconnected:
      return Future<void>.error(
        const DeviceNotReadyException('Device not connected.'),
      );
  }
}
