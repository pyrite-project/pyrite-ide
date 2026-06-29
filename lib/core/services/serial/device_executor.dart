import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/serial/raw_paste_session.dart';
import 'package:pyrite_ide/core/services/serial/repl_mutex_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_data_callbacks_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_repl_gate_provider.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';

const _defaultTimeout = Duration(seconds: 20);

/// Runs a Python script on the connected MicroPython device via the raw-paste
/// REPL protocol and returns the stdout output as a string.
///
/// This acquires the REPL mutex, pauses user-facing REPL I/O, enters raw-paste
/// mode, executes the code as a single block, then restores all state.
///
/// Throws [StateError] if no device is connected.
/// Throws [RawPasteException] if the device reports an execution error.
/// Throws [TimeoutException] if the device does not respond within [timeout].
Future<String> runPythonOnDevice(
  Ref ref,
  String python, {
  Duration timeout = _defaultTimeout,
}) async {
  final mutex = ref.read(replMutexProvider);
  return mutex.runExclusive(() async {
    _ensureConnected(ref);

    final queue = SerialByteQueue();
    void callback(Uint8List data) => queue.add(data);

    ref.read(serialReplIoPausedProvider.notifier).state = true;
    ref.read(serialDataCallbacksProvider.notifier).add(callback);

    final session = RawPasteSession(
      writeBytes: (bytes) {
        final serialProvider = getUsbSerialProvider();
        ref.read(serialProvider.notifier).sendBytes(Uint8List.fromList(bytes));
      },
      queue: queue,
    );
    try {
      await session.enterRawRepl(timeout: timeout);
      return await session.execute(python, timeout: timeout);
    } finally {
      try {
        await session.exitRawRepl();
      } finally {
        ref.read(serialDataCallbacksProvider.notifier).remove(callback);
        ref.read(serialReplIoPausedProvider.notifier).state = false;
      }
    }
  });
}

void _ensureConnected(Ref ref) {
  final serialProvider = getUsbSerialProvider();
  final serialState = ref.read(serialProvider);
  if (serialState.isConnected != true) {
    throw StateError('No serial device is connected');
  }
}
