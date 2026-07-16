import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/serial/raw_paste_session.dart';
import 'package:pyrite_ide/core/services/serial/repl_mutex_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_data_callbacks_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_repl_gate_provider.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';

const _defaultTimeout = Duration(seconds: 20);
const _handshakeTimeout = Duration(seconds: 2);
const _retryHandshakeTimeout = Duration(seconds: 3);

/// Exception thrown when the device cannot be reached for a REPL operation.
class DeviceNotReadyException implements Exception {
  final String message;
  const DeviceNotReadyException(this.message);
  @override
  String toString() => 'DeviceNotReadyException: $message';
}

/// Runs a Python script on the connected MicroPython device via the raw-paste
/// REPL protocol and returns the stdout output as a string.
///
/// Throws [DeviceNotReadyException] if the device is not connected or not in a
/// usable REPL state.
Future<String> runPythonOnDevice(
  Ref ref,
  String python, {
  Duration timeout = _defaultTimeout,
}) async {
  return _runPythonTransaction(
    ref,
    (session) => session.execute(python, timeout: timeout),
  );
}

Future<void> runPythonOnDeviceWithRawInput(
  Ref ref,
  String python,
  Uint8List data, {
  Duration startupTimeout = _defaultTimeout,
  Duration completionTimeout = const Duration(seconds: 60),
  required List<int> readyMarker,
  required List<int> doneMarker,
  int chunkSize = 4096,
  int ackEvery = 8,
  void Function(int sent, int total)? onProgress,
}) async {
  await _runPythonTransaction(
    ref,
    (session) => session.executeWithRawInput(
      python,
      data,
      startupTimeout: startupTimeout,
      completionTimeout: completionTimeout,
      readyMarker: readyMarker,
      doneMarker: doneMarker,
      chunkSize: chunkSize,
      ackEvery: ackEvery,
      onProgress: onProgress,
    ),
  );
}

Future<T> _runPythonTransaction<T>(
  Ref ref,
  Future<T> Function(RawPasteSession session) action,
) async {
  final mutex = ref.read(replMutexProvider);
  return mutex.runExclusive(() async {
    _ensureConnected(ref);

    final queue = SerialByteQueue();
    void callback(Uint8List data) => queue.add(data);

    ref.read(serialReplIoPausedProvider.notifier).state = true;
    ref.read(serialDataCallbacksProvider.notifier).add(callback);

    void writeBytes(List<int> bytes) {
      final serialProvider = getUsbSerialProvider();
      ref.read(serialProvider.notifier).sendBytes(Uint8List.fromList(bytes));
    }

    final session = RawPasteSession(writeBytes: writeBytes, queue: queue);
    try {
      // --- Tier 1: Ctrl+C burst + Ctrl+A handshake. ---
      var entered = false;
      entered = await _tryInterruptAndHandshake(
        session,
        writeBytes,
        queue,
        _handshakeTimeout,
      );

      // --- Tier 1 fallback: Ctrl+D flush + Ctrl+C burst + Ctrl+A. ---
      if (!entered) {
        writeBytes([0x04]); // Ctrl+D to flush half-parsed state
        await Future<void>.delayed(const Duration(milliseconds: 800));
        entered = await _tryInterruptAndHandshake(
          session,
          writeBytes,
          queue,
          _retryHandshakeTimeout,
        );
      }

      if (!entered) {
        _resetDevice(writeBytes);
        throw const DeviceNotReadyException(
          '设备未响应。设备可能正在运行程序或未处于 REPL 状态。\n'
          '请在终端中按 CTRL-C 停止程序后重试。',
        );
      }

      return await action(session);
    } finally {
      // --- Cleanup: always reset device to normal REPL state. ---
      try {
        await session.exitRawRepl();
      } catch (_) {}
      // Ensure device is back in normal REPL even if exitRawRepl failed.
      _resetDevice(writeBytes);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      ref.read(serialDataCallbacksProvider.notifier).remove(callback);
      ref.read(serialReplIoPausedProvider.notifier).state = false;
    }
  });
}

/// Sends CTRL-C one-by-one (12 times, 30ms apart) then Ctrl+A and waits for
/// the raw REPL banner. Returns true if handshake succeeded.
Future<bool> _tryInterruptAndHandshake(
  RawPasteSession session,
  void Function(List<int>) writeBytes,
  SerialByteQueue queue,
  Duration timeout,
) async {
  // Send CTRL-C one by one, 30ms apart — 12 times total (~360ms).
  for (var i = 0; i < 12; i++) {
    writeBytes([0x03]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  await Future<void>.delayed(const Duration(milliseconds: 150));
  queue.clear();

  try {
    await session.tryHandshake(timeout);
    return true;
  } on TimeoutException {
    return false;
  } on RawPasteException {
    rethrow;
  }
}

/// Sends CTRL-C×2 + CTRL-B to force the device back to normal REPL mode.
/// This is a fire-and-forget reset — we don't wait for a response.
void _resetDevice(void Function(List<int>) writeBytes) {
  writeBytes([0x03, 0x03]); // interrupt
  writeBytes([0x02]); // CTRL-B: exit raw REPL
}

void _ensureConnected(Ref ref) {
  final serialProvider = getUsbSerialProvider();
  final serialState = ref.read(serialProvider);
  if (serialState.isConnected != true) {
    throw const DeviceNotReadyException('设备未连接。请连接设备后重试。');
  }
}
