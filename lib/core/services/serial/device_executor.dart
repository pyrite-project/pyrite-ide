import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/serial/base_usb_serial.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';

// ---------------------------------------------------------------------------
// ReplMutex — prevents concurrent REPL transactions
// ---------------------------------------------------------------------------

class ReplMutex {
  bool _locked = false;
  final List<Completer<void>> _waitQueue = [];

  Future<T> runExclusive<T>(Future<T> Function() action) async {
    while (_locked) {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
    }
    _locked = true;
    try {
      return await action();
    } finally {
      _locked = false;
      if (_waitQueue.isNotEmpty) {
        final next = _waitQueue.removeAt(0);
        next.complete();
      }
    }
  }
}

final replMutexProvider = Provider<ReplMutex>((ref) => ReplMutex());

// ---------------------------------------------------------------------------
// Serial data callbacks — multiplexes serial data to listeners
// ---------------------------------------------------------------------------

class SerialDataCallbacksNotifier
    extends StateNotifier<List<SerialDataCallback>> {
  SerialDataCallbacksNotifier() : super([]);

  void add(SerialDataCallback callback) {
    state = [...state, callback];
  }

  void remove(SerialDataCallback callback) {
    state = [
      for (final c in state)
        if (c != callback) c,
    ];
  }
}

final serialDataCallbacksProvider =
    StateNotifierProvider<SerialDataCallbacksNotifier, List<SerialDataCallback>>(
  (ref) => SerialDataCallbacksNotifier(),
);

// ---------------------------------------------------------------------------
// I/O pause flag — blocks user REPL while a transaction owns the serial line
// ---------------------------------------------------------------------------

final serialReplIoPausedProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// DeviceSession — unified REPL session supporting all three modes
// ---------------------------------------------------------------------------

/// Magic bytes for the raw-paste protocol.
const int _rawPasteRespR = 0x52;
const int _rawPasteAccepted = 0x01;
const int _rawPasteRejected = 0x00;
const int _rawRespLowerR = 0x72;
const int _rawRespA = 0x61;

class DeviceSession {
  DeviceSession({
    required this.queue,
    required void Function(List<int>) writeBytes,
  }) : _writeBytes = writeBytes;

  final SerialByteQueue queue;
  final void Function(List<int>) _writeBytes;

  // -- Shared protocol tokens -----------------------------------------------

  static final _prompt = Uint8List.fromList([0x3E]); // ">"
  static final _prompt3 = Uint8List.fromList([0x3E, 0x3E, 0x3E, 0x20]); // ">>> "
  static final _dotsPrompt = Uint8List.fromList([0x2E, 0x2E, 0x2E, 0x20]); // "... "
  static final _eot = Uint8List.fromList([0x04]); // CTRL-D
  static final _rawReplBanner = utf8.encode('raw REPL; CTRL-B to exit');
  static final _rawPasteRequest = Uint8List.fromList([0x05, 0x41, 0x01]);

  // Paste-mode markers (wraps user code to extract clean output).
  static const _startMarker = '__PYRITE_NORMAL_REPL_START__';
  static const _endMarker = '__PYRITE_NORMAL_REPL_END__';

  // -- Public: enter / exit ------------------------------------------------

  /// Enters the appropriate REPL mode after CTRL-C has been sent.
  Future<void> enterRepl(ReplMode mode, {Duration? timeout}) async {
    final t = timeout ?? const Duration(seconds: 5);
    switch (mode) {
      case ReplMode.paste:
        await _enterPasteMode(t);
        break;
      case ReplMode.rawRepl:
        await _enterRawRepl(t);
        break;
      case ReplMode.rawPaste:
        await _enterRawPasteWithRetry(t);
        break;
    }
  }

  /// Exits the current REPL mode and resets to normal state.
  Future<void> exitRepl(ReplMode mode, {Duration? timeout}) async {
    final t = timeout ?? const Duration(seconds: 2);
    switch (mode) {
      case ReplMode.paste:
        _write([0x03]); // CTRL-C
        queue.clear();
        try {
          await queue.readUntil(_prompt3, t);
        } catch (_) {}
        break;
      case ReplMode.rawRepl:
        queue.clear();
        _write([0x03]); // CTRL-C
        await Future<void>.delayed(const Duration(milliseconds: 50));
        queue.clear();
        break;
      case ReplMode.rawPaste:
        queue.clear();
        _write(_eot);
        try {
          await queue.readUntil(_prompt, t);
        } catch (_) {}
        break;
    }
  }

  // -- Public: execute ------------------------------------------------------

  /// Executes a Python script and returns stdout as a string.
  Future<String> execute(
    String code, {
    Duration timeout = const Duration(seconds: 20),
    required ReplMode mode,
  }) async {
    switch (mode) {
      case ReplMode.paste:
        return _executePaste(code, timeout);
      case ReplMode.rawRepl:
        return _executeRawRepl(code, timeout);
      case ReplMode.rawPaste:
        return _executeRawPaste(code, timeout);
    }
  }

  /// Executes a Python script with streaming output.
  Future<void> executeStreaming(
    String code, {
    Duration timeout = const Duration(seconds: 20),
    required ReplMode mode,
    required void Function() onStarted,
    required void Function(Uint8List data) onStdout,
    required void Function(Uint8List data) onStderr,
  }) async {
    switch (mode) {
      case ReplMode.paste:
        return _executeStreamingPaste(
          code,
          timeout: timeout,
          onStarted: onStarted,
          onStdout: onStdout,
          onStderr: onStderr,
        );
      case ReplMode.rawRepl:
        return _executeStreamingRawRepl(
          code,
          timeout: timeout,
          onStarted: onStarted,
          onStdout: onStdout,
          onStderr: onStderr,
        );
      case ReplMode.rawPaste:
        return _executeStreamingRawPaste(
          code,
          timeout: timeout,
          onStarted: onStarted,
          onStdout: onStdout,
          onStderr: onStderr,
        );
    }
  }

  /// Executes a Python script that reads raw binary data from stdin.
  /// Only works with raw-paste mode.
  Future<void> executeWithRawInput(
    String code,
    Uint8List data, {
    Duration startupTimeout = const Duration(seconds: 20),
    Duration completionTimeout = const Duration(seconds: 60),
    required List<int> readyMarker,
    required List<int> doneMarker,
    int chunkSize = 4096,
    int ackEvery = 8,
    void Function(int sent, int total)? onProgress,
  }) async {
    final response = await _tryRawPasteHandshake(startupTimeout);
    if (response == null) {
      throw const DeviceSessionException('Device rejected raw-paste mode');
    }

    final codeBytes = utf8.encode(code);
    await _writeRawPasteCode(codeBytes, response, startupTimeout);
    await queue.readUntil(_eot, startupTimeout);

    await queue.readUntil(readyMarker, completionTimeout);

    var sent = 0;
    var ackCount = 0;
    while (sent < data.length) {
      final end = math.min(sent + chunkSize, data.length);
      _write(data.sublist(sent, end));
      sent = end;
      ackCount++;
      if (ackEvery > 0 && ackCount % ackEvery == 0 && sent < data.length) {
        final ack = await queue.readBytes(1, completionTimeout);
        if (ack[0] != 0x2B) {
          throw DeviceSessionException(
            'Unexpected ACK: 0x${ack[0].toRadixString(16)}',
          );
        }
      }
      onProgress?.call(sent, data.length);
    }

    await queue.readUntil(doneMarker, completionTimeout);
    await queue.readUntil(_eot, completionTimeout);
    await _readPayloadUntilEot(completionTimeout);
    await queue.readUntil(_prompt, completionTimeout);
  }

  /// Sends SOH and waits for the raw-repl banner + prompt.
  Future<void> tryHandshake(Duration timeout) async {
    _write(const [0x01]); // CTRL-A
    await queue.readUntil(_rawReplBanner, timeout);
    await queue.readUntil(_prompt, timeout);
  }

  // -- Paste mode -----------------------------------------------------------

  Future<void> _enterPasteMode(Duration timeout) async {
    _write([0x05]); // Ctrl-E
    await _waitForPasteReady(timeout);
  }

  Future<void> _waitForPasteReady(Duration timeout) async {
    final eqPrompt = Uint8List.fromList([0x3D, 0x3D, 0x3D]); // "==="
    final stopwatch = Stopwatch()..start();
    while (true) {
      if (queue.indexOf(eqPrompt) >= 0) {
        await queue.readUntil(eqPrompt, Duration.zero);
        return;
      }
      if (queue.indexOf(_dotsPrompt) >= 0) {
        await queue.readUntil(_dotsPrompt, Duration.zero);
        return;
      }
      if (queue.indexOf(_prompt3) >= 0) {
        await queue.readUntil(_prompt3, Duration.zero);
        throw TimeoutException('Paste mode not available', timeout);
      }
      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Timed out waiting for paste mode', timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<String> _executePaste(String code, Duration timeout) async {
    queue.clear();
    _write([0x05]); // Ctrl-E
    await _waitForPasteReady(timeout ~/ 3);

    final script = "print('$_startMarker')\n$code\nprint('$_endMarker')\n";
    _write(utf8.encode(script));
    _write([0x04]); // Ctrl-D

    final allData = await _waitForPromptAndReadAll(timeout);
    return _extractBetweenMarkers(allData);
  }

  Future<void> _executeStreamingPaste(
    String code, {
    required Duration timeout,
    required void Function() onStarted,
    required void Function(Uint8List data) onStdout,
    required void Function(Uint8List data) onStderr,
  }) async {
    queue.clear();
    _write([0x05]); // Ctrl-E
    await _waitForPasteReady(timeout ~/ 3);

    final script = "print('$_startMarker')\n$code\nprint('$_endMarker')\n";
    _write(utf8.encode(script));
    _write([0x04]); // Ctrl-D
    onStarted();

    final allData = await _waitForPromptAndReadAll(timeout);
    final clean = _extractBetweenMarkers(allData);
    final bytes = Uint8List.fromList(utf8.encode(clean));
    if (bytes.isNotEmpty) onStdout(bytes);
  }

  Future<String> _waitForPromptAndReadAll(Duration timeout) async {
    final withoutSpace = Uint8List.fromList([0x3E, 0x3E, 0x3E]); // ">>>"

    final stopwatch = Stopwatch()..start();
    while (true) {
      if (queue.indexOf(_prompt3) >= 0) {
        final data = await queue.readUntil(_prompt3, Duration.zero);
        return utf8.decode(data, allowMalformed: true);
      }
      if (queue.indexOf(withoutSpace) >= 0) {
        final data = await queue.readUntil(withoutSpace, Duration.zero);
        return utf8.decode(data, allowMalformed: true);
      }
      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Timed out waiting for >>> prompt', timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  String _extractBetweenMarkers(String output) {
    final lastEndIdx = output.lastIndexOf(_endMarker);
    if (lastEndIdx < 0) {
      throw TimeoutException('End marker not found in output', null);
    }
    final beforeEnd = output.substring(0, lastEndIdx);
    final startIdx = beforeEnd.lastIndexOf(_startMarker);
    if (startIdx < 0) return beforeEnd;
    return beforeEnd.substring(startIdx + _startMarker.length);
  }

  // -- Raw REPL mode (CTRL-A) -----------------------------------------------

  Future<void> _enterRawRepl(Duration timeout) async {
    queue.clear();
    _write([0x01]); // CTRL-A
    await queue.readUntil(_rawReplBanner, timeout);
    await queue.readUntil(_prompt, timeout);
  }

  Future<String> _executeRawRepl(String code, Duration timeout) async {
    final bytes = utf8.encode(code);
    await _enterRawRepl(timeout ~/ 3);

    _write(bytes);
    _write(_eot);

    final stdout = await _readUntilEot(timeout);
    final stderr = await _readUntilEot(timeout);
    await queue.readUntil(_prompt, timeout);

    // Raw REPL outputs "OK\r\n" before stdout — strip it.
    var stdoutStr = utf8.decode(stdout, allowMalformed: true);
    if (stdoutStr.startsWith('OK')) {
      stdoutStr = stdoutStr.substring(2);
      if (stdoutStr.startsWith('\r\n')) {
        stdoutStr = stdoutStr.substring(2);
      } else if (stdoutStr.startsWith('\n')) {
        stdoutStr = stdoutStr.substring(1);
      }
    }
    if (stderr.isNotEmpty) {
      final errText = utf8.decode(stderr, allowMalformed: true);
      if (errText.isNotEmpty) {
        return '$stdoutStr\n$errText';
      }
    }
    return stdoutStr;
  }

  Future<void> _executeStreamingRawRepl(
    String code, {
    required Duration timeout,
    required void Function() onStarted,
    required void Function(Uint8List data) onStdout,
    required void Function(Uint8List data) onStderr,
  }) async {
    final bytes = utf8.encode(code);
    await _enterRawRepl(timeout ~/ 3);

    _write(bytes);
    _write(_eot);
    onStarted();

    await queue.readUntilStreaming(_eot, onData: onStdout);
    await queue.readUntilStreaming(_eot, onData: onStderr);
    await queue.readUntil(_prompt, timeout);
  }

  // -- Raw-paste mode (flow-controlled) -------------------------------------

  Future<int?> _tryRawPasteHandshake(Duration timeout) async {
    _write(_rawPasteRequest);
    final response = await queue.readBytes(2, timeout);
    if (response[0] == _rawPasteRespR && response[1] == _rawPasteAccepted) {
      final window = await queue.readBytes(2, timeout);
      return window[0] | (window[1] << 8);
    }
    if (response[0] == _rawPasteRespR && response[1] == _rawPasteRejected) {
      return null;
    }
    if (response[0] == _rawRespLowerR && response[1] == _rawRespA) {
      await queue.readUntil(_prompt, timeout);
      return null;
    }
    throw DeviceSessionException(
      'Unexpected raw-paste handshake: ${response.toList()}',
    );
  }

  Future<void> _enterRawPasteWithRetry(Duration timeout) async {
    // Tier 1: CTRL-C burst + CTRL-A handshake.
    var entered = await _tryHandshakeAfterInterrupt(timeout);

    // Tier 2: CTRL-D flush + retry.
    if (!entered) {
      _write([0x04]); // CTRL-D to flush half-parsed state
      await Future<void>.delayed(const Duration(milliseconds: 200));
      entered = await _tryHandshakeAfterInterrupt(const Duration(seconds: 3));
    }

    if (!entered) {
      _resetDevice();
      throw const DeviceSessionException(
        'Device not responding. Device may be running a program or not in REPL state.\n'
        'Press CTRL-C in the terminal to stop the program and try again.',
      );
    }
    queue.clear();
  }

  Future<bool> _tryHandshakeAfterInterrupt(Duration timeout) async {
    for (var i = 0; i < 2; i++) {
      _write([0x03]); // CTRL-C
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    queue.clear();

    try {
      await tryHandshake(timeout);
      return true;
    } on TimeoutException {
      return false;
    } on DeviceSessionException {
      rethrow;
    }
  }

  Future<String> _executeRawPaste(String code, Duration timeout) async {
    final bytes = utf8.encode(code);
    final response = await _tryRawPasteHandshake(timeout);
    if (response == null) {
      throw const DeviceSessionException('Device rejected raw-paste mode');
    }
    await _writeRawPasteCode(bytes, response, timeout);
    await queue.readUntil(_eot, timeout);
    final stdout = await _readPayloadUntilEot(timeout);
    await _readPayloadUntilEot(timeout); // consume stderr
    await queue.readUntil(_prompt, timeout);
    return utf8.decode(stdout, allowMalformed: true);
  }

  Future<void> _executeStreamingRawPaste(
    String code, {
    required Duration timeout,
    required void Function() onStarted,
    required void Function(Uint8List data) onStdout,
    required void Function(Uint8List data) onStderr,
  }) async {
    final bytes = utf8.encode(code);
    final response = await _tryRawPasteHandshake(timeout);
    if (response == null) {
      throw const DeviceSessionException('Device rejected raw-paste mode');
    }
    onStarted();
    await _writeRawPasteCode(bytes, response, timeout);
    await queue.readUntil(_eot, timeout);
    await queue.readUntilStreaming(_eot, onData: onStdout);
    await queue.readUntilStreaming(_eot, onData: onStderr);
    await queue.readUntil(_prompt, timeout);
  }

  Future<void> _writeRawPasteCode(
    Uint8List code,
    int windowIncrement,
    Duration timeout,
  ) async {
    var remainingWindow = windowIncrement;
    var offset = 0;
    var sentEndOfData = false;

    while (offset < code.length) {
      while (queue.hasData) {
        final signal = (await queue.readBytes(1, timeout))[0];
        if (signal == _rawPasteAccepted) {
          remainingWindow += windowIncrement;
        } else if (signal == 0x04) {
          _write(_eot);
          sentEndOfData = true;
          offset = code.length;
          break;
        }
      }
      if (offset >= code.length) break;

      if (remainingWindow <= 0) {
        final signal = (await queue.readBytes(1, timeout))[0];
        if (signal == _rawPasteAccepted) {
          remainingWindow += windowIncrement;
          continue;
        }
        if (signal == 0x04) {
          _write(_eot);
          sentEndOfData = true;
          break;
        }
        continue;
      }

      final count = math.min(remainingWindow, code.length - offset);
      _write(code.sublist(offset, offset + count));
      offset += count;
      remainingWindow -= count;
    }

    if (!sentEndOfData) {
      _write(_eot);
    }
  }

  // -- Helpers --------------------------------------------------------------

  Future<Uint8List> _readUntilEot(Duration timeout) async {
    final data = await queue.readUntil(_eot, timeout);
    return Uint8List.fromList(data.sublist(0, data.length - 1));
  }

  Future<Uint8List> _readPayloadUntilEot(Duration timeout) async {
    final data = await queue.readUntil(_eot, timeout);
    return Uint8List.fromList(data.sublist(0, data.length - 1));
  }

  void _resetDevice() {
    _write([0x03, 0x03]); // interrupt
    _write([0x02]); // CTRL-B: exit raw REPL
  }

  void _write(List<int> bytes) {
    _writeBytes(bytes);
  }
}

/// Exception thrown when a device session operation fails.
class DeviceSessionException implements Exception {
  final String message;
  const DeviceSessionException(this.message);
  @override
  String toString() => 'DeviceSessionException: $message';
}

// ---------------------------------------------------------------------------
// Transaction runner — the single gateway for all REPL operations
// ---------------------------------------------------------------------------

const _defaultTimeout = Duration(seconds: 20);
const Duration _postExitDelay = Duration(milliseconds: 10);

typedef _ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Exception thrown when the device cannot be reached for a REPL operation.
class DeviceNotReadyException implements Exception {
  final String message;
  const DeviceNotReadyException(this.message);
  @override
  String toString() => 'DeviceNotReadyException: $message';
}

/// Runs a REPL transaction with mutex, I/O pausing, and cleanup.
Future<T> _runTransaction<T>(
  _ProviderReader read,
  Future<T> Function(DeviceSession session, ReplMode mode) action, {
  /// Called with the queue before execution starts. Return an optional
  /// cleanup function that will be called in the `finally` block.
  void Function()? Function(SerialByteQueue queue)? onSetup,
}) async {
  final mutex = read(replMutexProvider);
  return mutex.runExclusive(() async {
    _ensureConnected(read);

    final queue = SerialByteQueue();
    void callback(Uint8List data) => queue.add(data);

    read(serialReplIoPausedProvider.notifier).state = true;
    read(serialDataCallbacksProvider.notifier).add(callback);

    // Set up disconnect listener — caller wires it and provides cleanup.
    final cleanup = onSetup?.call(queue);

    void writeBytes(List<int> bytes) {
      final serialProvider = getUsbSerialProvider();
      read(serialProvider.notifier).sendBytes(Uint8List.fromList(bytes));
    }

    final mode = read(replModeProvider);
    final session = DeviceSession(queue: queue, writeBytes: writeBytes);
    try {
      // CTRL-C to interrupt any running program.
      writeBytes([0x03]);
      await session.enterRepl(mode);
      return await action(session, mode);
    } finally {
      cleanup?.call();
      try {
        await session.exitRepl(mode);
      } catch (_) {}
      queue.cancel();
      queue.clear();
      // CTRL-C + CTRL-B to force back to normal REPL.
      writeBytes([0x03, 0x03]);
      writeBytes([0x02]);
      await Future<void>.delayed(_postExitDelay);
      read(serialDataCallbacksProvider.notifier).remove(callback);
      read(serialReplIoPausedProvider.notifier).state = false;
    }
  });
}

void _ensureConnected(_ProviderReader read) {
  final serialProvider = getUsbSerialProvider();
  final serialState = read(serialProvider);
  if (serialState.isConnected != true) {
    throw const DeviceNotReadyException('Device not connected.');
  }
}

// ---------------------------------------------------------------------------
// Public API — the only functions external code should call
// ---------------------------------------------------------------------------

/// Runs a Python script on the connected MicroPython device and returns
/// stdout as a string.
Future<String> runPythonOnDevice(
  Ref ref,
  String python, {
  Duration timeout = _defaultTimeout,
}) {
  return _runTransaction(
    ref.read,
    (session, mode) => session.execute(python, timeout: timeout, mode: mode),
    onSetup: (queue) {
      final sub = ref.listen(getUsbSerialProvider(), (_, next) {
        if ((next as UsbSerialState?)?.isConnected == false) queue.cancel();
      });
      return () => sub.close();
    },
  );
}

/// Runs a Python script while forwarding stdout and stderr as the device
/// emits them.
Future<void> runPythonOnDeviceStreaming(
  WidgetRef ref,
  String python, {
  Duration startupTimeout = _defaultTimeout,
  required void Function() onStarted,
  required void Function(Uint8List data) onStdout,
  required void Function(Uint8List data) onStderr,
}) {
  return _runTransaction(
    ref.read,
    (session, mode) => session.executeStreaming(
      python,
      timeout: startupTimeout,
      mode: mode,
      onStarted: onStarted,
      onStdout: onStdout,
      onStderr: onStderr,
    ),
    onSetup: (queue) {
      final sub = ref.listenManual(getUsbSerialProvider(), (_, next) {
        if ((next as UsbSerialState?)?.isConnected == false) queue.cancel();
      });
      return () => sub.close();
    },
  );
}

/// Runs a Python script while streaming raw binary data into stdin.
/// Only works with raw-paste mode.
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
}) {
  return _runTransaction(
    ref.read,
    (session, mode) {
      if (mode != ReplMode.rawPaste) {
        throw UnsupportedError(
          'Raw input execution requires raw-paste mode.',
        );
      }
      return session.executeWithRawInput(
        python,
        data,
        startupTimeout: startupTimeout,
        completionTimeout: completionTimeout,
        readyMarker: readyMarker,
        doneMarker: doneMarker,
        chunkSize: chunkSize,
        ackEvery: ackEvery,
        onProgress: onProgress,
      );
    },
    onSetup: (queue) {
      final sub = ref.listen(getUsbSerialProvider(), (_, next) {
        if ((next as UsbSerialState?)?.isConnected == false) queue.cancel();
      });
      return () => sub.close();
    },
  );
}
