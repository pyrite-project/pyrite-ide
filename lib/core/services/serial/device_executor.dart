import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/serial/base_usb_serial.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';
import 'package:pyrite_ide/core/services/status_bar/running_operation_provider.dart';

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

enum TransactionTermination { none, interrupt, hardwareReset }

class HardwareResetController {
  VoidCallback? _request;

  bool get isAvailable => _request != null;

  void register(VoidCallback request) => _request = request;

  void unregister(VoidCallback request) {
    if (_request == request) _request = null;
  }

  void request() => _request?.call();
}

final hardwareResetControllerProvider = Provider<HardwareResetController>(
  (ref) => HardwareResetController(),
);

/// Requests a reset for an active transaction, or resets the idle device
/// while holding the REPL mutex. Hardware reset is never invoked implicitly.
Future<bool> hardwareResetDevice(ProviderReader read) async {
  final strategy = read(hardwareResetStrategyProvider);
  if (strategy == HardwareResetStrategy.disabled) return false;
  final controller = read(hardwareResetControllerProvider);
  if (controller.isAvailable) {
    controller.request();
    return true;
  }
  return read(replMutexProvider).runExclusive(() async {
    read(serialReplIoPausedProvider.notifier).state = true;
    try {
      return await read(serialProvider.notifier).hardwareReset(strategy);
    } finally {
      read(serialReplIoPausedProvider.notifier).state = false;
    }
  });
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
    StateNotifierProvider<
      SerialDataCallbacksNotifier,
      List<SerialDataCallback>
    >((ref) => SerialDataCallbacksNotifier());

// ---------------------------------------------------------------------------
// I/O pause flag — blocks user REPL while a transaction owns the serial line
// ---------------------------------------------------------------------------

final serialReplIoPausedProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// DeviceSession — unified REPL session supporting raw-repl and paste modes
// ---------------------------------------------------------------------------

class DeviceSession {
  DeviceSession({
    required this.queue,
    required void Function(List<int>) writeBytes,
  }) : _writeBytes = writeBytes;

  final SerialByteQueue queue;
  final void Function(List<int>) _writeBytes;
  bool _pasteReady = false;

  // -- Shared protocol tokens -----------------------------------------------

  static final _prompt = Uint8List.fromList([0x3E]); // ">"
  static final _prompt3 = Uint8List.fromList([
    0x3E,
    0x3E,
    0x3E,
    0x20,
  ]); // ">>> "
  static final _dotsPrompt = Uint8List.fromList([
    0x2E,
    0x2E,
    0x2E,
    0x20,
  ]); // "... "
  static final _eot = Uint8List.fromList([0x04]); // CTRL-D
  static final _rawReplBanner = utf8.encode('raw REPL; CTRL-B to exit');

  // Paste-mode markers (wraps user code to extract clean output).
  static const _startMarker = '__PYRITE_NORMAL_REPL_START__';
  static const _endMarker = '__PYRITE_NORMAL_REPL_END__';

  // -- Public: enter / exit ------------------------------------------------

  /// Enters the selected REPL mode after CTRL-C has been sent.
  Future<void> enterRepl(ReplMode mode, {Duration? timeout}) async {
    final t = timeout ?? const Duration(seconds: 5);
    debugPrint('[repl] enterRepl mode=$mode timeout=${t.inSeconds}s');

    if (mode == ReplMode.paste) {
      await _enterPasteMode(t);
      _pasteReady = true;
      return;
    }

    if (mode == ReplMode.rawRepl) {
      await _enterRawRepl(t);
      return;
    }
  }

  /// Exits the current REPL mode and resets to normal state.
  Future<void> exitRepl(ReplMode mode, {Duration? timeout}) async {
    final t = timeout ?? const Duration(seconds: 2);
    debugPrint(
      '[repl] exitRepl mode=$mode timeout=${t.inSeconds}s queueCancelled=${queue.isCancelled}',
    );
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
    }
    debugPrint('[repl] exitRepl done');
  }

  // -- Public: execute ------------------------------------------------------

  /// Executes a Python script and returns stdout as a string.
  Future<String> execute(
    String code, {
    Duration timeout = const Duration(seconds: 20),
    required ReplMode mode,
  }) async {
    return executeCommand(code, timeout: timeout, mode: mode);
  }

  /// Executes one command while keeping ownership of the current REPL
  /// transaction. Paste mode re-enters paste input between commands without
  /// repeating the transaction-level interrupt handshake.
  Future<String> executeCommand(
    String code, {
    Duration timeout = const Duration(seconds: 20),
    required ReplMode mode,
  }) async {
    switch (mode) {
      case ReplMode.paste:
        if (!_pasteReady) {
          queue.clear();
          _write([0x05]); // CTRL-E
          await _waitForPasteReady(timeout);
          _pasteReady = true;
        }
        return _executePaste(code, timeout);
      case ReplMode.rawRepl:
        return executeRawCommand(code, timeout: timeout);
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
        if (!_pasteReady) {
          queue.clear();
          _write([0x05]); // CTRL-E
          await _waitForPasteReady(timeout);
          _pasteReady = true;
        }
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
    }
  }

  /// Executes a Python script that reads Base64-framed data from stdin.
  ///
  /// Protocol (matches CLI's _send_flash_payload):
  ///   1. Send code + CTRL-D to execute
  ///   2. Wait for [readyMarker] (device signals it's ready for data)
  ///   3. Send Base64 lines for [chunkSize] byte chunks, waiting for '+' ACK every
  ///      [ackEvery] chunks (sparse ACK flow control)
  ///   4. Wait for [doneMarker] and consume the raw REPL trailer
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
    debugPrint(
      '[raw-input] START raw-repl upload, code=${code.length}B data=${data.length}B '
      'chunk=$chunkSize ackEvery=$ackEvery timeout=${completionTimeout.inSeconds}s',
    );

    // Phase 1: Send code + CTRL-D to execute the device script.
    final codeBytes = utf8.encode(code);
    _write(codeBytes);
    _write(_eot); // CTRL-D: execute the code
    debugPrint('[raw-input] code sent, waiting for readyMarker...');

    // Phase 2: Wait for device to signal READY.
    final readyData = await queue.readUntil(readyMarker, startupTimeout);
    _logDevText(utf8.decode(readyData, allowMalformed: true));
    debugPrint('[raw-input] readyMarker received');
    debugPrint('[raw-input] sending data...');

    // Phase 3: Send data with sparse ACK flow control.
    var sent = 0;
    var ackCount = 0;
    while (sent < data.length) {
      if (queue.isCancelled) {
        debugPrint(
          '[raw-input] CANCELLED during data send at $sent/${data.length}',
        );
        throw const SerialCancelledException();
      }
      final end = math.min(sent + chunkSize, data.length);
      _write(utf8.encode('${base64Encode(data.sublist(sent, end))}\n'));
      sent = end;
      ackCount++;
      if (ackEvery > 0 && ackCount % ackEvery == 0) {
        debugPrint(
          '[raw-input] waiting ACK #$ackCount at $sent/${data.length}',
        );
        final ack = await _readUntilPattern(0x2B, completionTimeout);
        if (!ack) {
          throw DeviceSessionException(
            'Device ACK timeout during data transfer',
          );
        }
        debugPrint('[raw-input] ACK received');
      }
      onProgress?.call(sent, data.length);
    }
    final doneData = await queue.readUntil(doneMarker, completionTimeout);
    final doneText = utf8.decode(doneData, allowMalformed: true);
    if (doneText.contains('PYRITE_WRITE_ERR:')) {
      throw DeviceSessionException(doneText.trim());
    }
    await queue.readUntil(_eot, completionTimeout);
    final stderr = await _readUntilEot(completionTimeout);
    await queue.readUntil(_prompt, completionTimeout);
    if (stderr.isNotEmpty) {
      throw DeviceSessionException(utf8.decode(stderr, allowMalformed: true));
    }
  }

  /// Executes [code] in the current raw REPL session and reads exactly
  /// [expectedSize] stdout bytes before consuming stderr and the prompt.
  Future<Uint8List> readRawFile(
    String code,
    int expectedSize, {
    Duration timeout = const Duration(seconds: 30),
    void Function(int received, int total)? onProgress,
  }) async {
    _write(utf8.encode(code));
    _write(_eot);
    await queue.readUntil(const [0x4F, 0x4B], timeout); // OK

    final output = BytesBuilder(copy: false);
    var received = 0;
    await queue.readBytesStreaming(
      expectedSize,
      timeout,
      onData: (data) {
        output.add(data);
        received += data.length;
        onProgress?.call(received, expectedSize);
      },
    );
    await queue.readUntil(_eot, timeout);
    final stderr = await _readUntilEot(timeout);
    await queue.readUntil(_prompt, timeout);
    if (stderr.isNotEmpty) {
      throw DeviceSessionException(utf8.decode(stderr, allowMalformed: true));
    }
    return output.takeBytes();
  }

  /// Logs any `[DEV-LOG]` lines found in [text] via `debugPrint`.
  static void _logDevText(String text) {
    for (final line in text.split('\n')) {
      final trimmed = line.trimRight();
      if (trimmed.startsWith('[DEV-LOG]')) {
        debugPrint('[device] $trimmed');
      }
    }
  }

  /// Reads from the queue until [pattern] is found.
  ///
  /// If [pattern] is an `int`, matches a single byte.
  /// If [pattern] is a `String`, accumulates text and matches via `contains`.
  ///
  /// Returns `true` if found, `false` on timeout. Cancellation is propagated
  /// as [SerialCancelledException] so callers never retry an interrupted job.
  /// [onError] is called periodically with accumulated text (for error
  /// detection before the target is found). DEV-LOG lines are logged
  /// automatically.
  Future<bool> _readUntilPattern(
    Object pattern,
    Duration timeout, {
    void Function(String text)? onError,
  }) async {
    final sw = Stopwatch()..start();
    final buf = StringBuffer();
    var lastErrorCheck = 0;
    while (sw.elapsed < timeout) {
      if (queue.isCancelled) throw const SerialCancelledException();
      if (queue.hasData) {
        final byte = await queue.readBytes(1, const Duration(milliseconds: 50));
        if (pattern is int) {
          if (byte[0] == pattern) return true;
          // Log DEV-LOG lines from non-target bytes.
          final ch = String.fromCharCodes(byte);
          if (ch == '\n') {
            _logDevText(buf.toString());
            buf.clear();
          } else if (ch != '\r') {
            buf.write(ch);
          }
        } else {
          buf.write(String.fromCharCodes(byte));
          final text = buf.toString();
          if (text.contains(pattern as String)) return true;
          // Periodically check for errors and DEV-LOG lines.
          if (text.length - lastErrorCheck >= 8) {
            lastErrorCheck = text.length;
            if (onError != null) onError(text);
            _logDevText(text);
          }
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
    return false;
  }

  // -- Paste mode -----------------------------------------------------------

  Future<void> _enterPasteMode(Duration timeout) async {
    // Wait for the device to finish processing CTRL-C and show ">>>",
    // then clear any leftover output before entering paste mode.
    try {
      await queue.readUntil(_prompt3, timeout);
    } on SerialCancelledException {
      rethrow;
    } catch (_) {}
    queue.clear();
    _write([0x05]); // Ctrl-E
    await _waitForPasteReady(timeout);
  }

  Future<void> _waitForPasteReady(Duration timeout) async {
    final eqPrompt = Uint8List.fromList([0x3D, 0x3D, 0x3D]); // "==="
    final stopwatch = Stopwatch()..start();
    while (true) {
      if (queue.isCancelled) throw const SerialCancelledException();
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
    // _enterPasteMode already entered paste mode (Ctrl-E + waited for ===).
    final script =
        '${_markerPrint(_startMarker)}\n$code\n${_markerPrint(_endMarker)}\n';
    _write(utf8.encode(script));
    _write([0x04]); // Ctrl-D

    try {
      final allData = await _waitForPromptAndReadAll(timeout);
      return _extractBetweenMarkers(allData);
    } finally {
      _pasteReady = false;
    }
  }

  Future<void> _executeStreamingPaste(
    String code, {
    required Duration timeout,
    required void Function() onStarted,
    required void Function(Uint8List data) onStdout,
    required void Function(Uint8List data) onStderr,
  }) async {
    // _enterPasteMode already entered paste mode (Ctrl-E + waited for ===).
    final script =
        '${_markerPrint(_startMarker)}\n$code\n${_markerPrint(_endMarker)}\n';
    _write(utf8.encode(script));
    _write([0x04]); // Ctrl-D
    onStarted();

    try {
      final parser = _PasteOutputParser(
        startMarker: _startMarker,
        endMarker: _endMarker,
        onOutput: onStdout,
      );
      await _waitForPromptAndStream(timeout, parser);
      parser.close();
    } finally {
      _pasteReady = false;
    }
  }

  String _markerPrint(String marker) {
    final split = marker.length ~/ 2;
    return "print('${marker.substring(0, split)}' + '${marker.substring(split)}')";
  }

  Future<String> _waitForPromptAndReadAll(Duration timeout) async {
    final withoutSpace = Uint8List.fromList([0x3E, 0x3E, 0x3E]); // ">>>"

    final stopwatch = Stopwatch()..start();
    while (true) {
      if (queue.isCancelled) throw const SerialCancelledException();
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

  Future<void> _waitForPromptAndStream(
    Duration timeout,
    _PasteOutputParser parser,
  ) async {
    final withoutSpace = Uint8List.fromList([0x3E, 0x3E, 0x3E]);
    final stopwatch = Stopwatch()..start();
    while (true) {
      if (queue.isCancelled) throw const SerialCancelledException();
      if (queue.indexOf(_prompt3) >= 0) {
        await queue.readUntilStreaming(_prompt3, onData: parser.addBytes);
        return;
      }
      if (queue.indexOf(withoutSpace) >= 0) {
        await queue.readUntilStreaming(withoutSpace, onData: parser.addBytes);
        return;
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

  /// Executes one command in the already-entered raw REPL session.
  Future<String> executeRawCommand(
    String code, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final bytes = Uint8List.fromList([...utf8.encode(code), ..._eot]);
    var offset = 0;
    while (offset < bytes.length) {
      final end = math.min(offset + 255, bytes.length);
      _write(bytes.sublist(offset, end));
      offset = end;
      if (offset < bytes.length) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

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
    _write(bytes);
    _write(_eot);
    onStarted();

    await queue.readUntilStreaming(_eot, onData: onStdout);
    await queue.readUntilStreaming(_eot, onData: onStderr);
    await queue.readUntil(_prompt, timeout);
  }

  // -- Helpers --------------------------------------------------------------

  Future<Uint8List> _readUntilEot(Duration timeout) async {
    final data = await queue.readUntil(_eot, timeout);
    return Uint8List.fromList(data.sublist(0, data.length - 1));
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

class _PasteOutputParser {
  _PasteOutputParser({
    required this.startMarker,
    required this.endMarker,
    required this.onOutput,
  }) {
    _decoder = const Utf8Decoder(allowMalformed: true).startChunkedConversion(
      StringConversionSink.fromStringSink(_CallbackStringSink(_addText)),
    );
  }

  final String startMarker;
  final String endMarker;
  final void Function(Uint8List data) onOutput;
  late ByteConversionSink _decoder;
  String _pending = '';
  bool _started = false;
  bool _finished = false;

  void addBytes(Uint8List data) => _decoder.add(data);

  void close() {
    _decoder.close();
    if (!_finished) {
      throw const DeviceSessionException(
        'Paste execution ended without the output marker.',
      );
    }
  }

  void _addText(String text) {
    if (_finished || text.isEmpty) return;
    _pending += text;

    if (!_started) {
      final markerIndex = _pending.indexOf(startMarker);
      if (markerIndex < 0) {
        _keepPossibleMarkerPrefix(startMarker);
        return;
      }
      _pending = _pending.substring(markerIndex + startMarker.length);
      _started = true;
    }

    final endIndex = _pending.indexOf(endMarker);
    if (endIndex >= 0) {
      _emit(_pending.substring(0, endIndex));
      _pending = '';
      _finished = true;
      return;
    }

    final keep = _matchingSuffixLength(_pending, endMarker);
    final emitLength = _pending.length - keep;
    if (emitLength > 0) {
      _emit(_pending.substring(0, emitLength));
      _pending = _pending.substring(emitLength);
    }
  }

  void _keepPossibleMarkerPrefix(String marker) {
    final keep = _matchingSuffixLength(_pending, marker);
    _pending = keep == 0 ? '' : _pending.substring(_pending.length - keep);
  }

  int _matchingSuffixLength(String text, String marker) {
    final maxLength = math.min(text.length, marker.length - 1);
    for (var length = maxLength; length > 0; length--) {
      if (text.endsWith(marker.substring(0, length))) return length;
    }
    return 0;
  }

  void _emit(String text) {
    if (text.isEmpty) return;
    onOutput(Uint8List.fromList(utf8.encode(text)));
  }
}

class _CallbackStringSink implements StringSink {
  const _CallbackStringSink(this._write);

  final void Function(String) _write;

  @override
  void write(Object? object) => _write(object?.toString() ?? '');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) => _write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => _write('${object ?? ''}\n');
}

// ---------------------------------------------------------------------------
// Transaction runner — the single gateway for all REPL operations
// ---------------------------------------------------------------------------

const _defaultTimeout = Duration(seconds: 20);

typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Exception thrown when the device cannot be reached for a REPL operation.
class DeviceNotReadyException implements Exception {
  final String message;
  const DeviceNotReadyException(this.message);
  @override
  String toString() => 'DeviceNotReadyException: $message';
}

/// Sends a CTRL-C burst and enters REPL on a fresh [DeviceSession].
Future<DeviceSession> _initSessionAndEnterRepl(
  SerialByteQueue queue,
  void Function(List<int>) writeBytes,
  ReplMode mode, {
  int interruptCount = 12,
  int interruptIntervalMs = 30,
  Duration settleDelay = const Duration(milliseconds: 150),
}) async {
  final session = DeviceSession(queue: queue, writeBytes: writeBytes);
  for (var i = 0; i < interruptCount; i++) {
    writeBytes([0x03]);
    await Future<void>.delayed(Duration(milliseconds: interruptIntervalMs));
  }
  await Future<void>.delayed(settleDelay);
  await session.enterRepl(mode);
  return session;
}

/// Interrupts the active script and confirms a friendly REPL prompt.
Future<bool> _recoverInterruptedDevice(
  SerialByteQueue queue,
  void Function(List<int>) writeBytes, {
  int maxAttempts = 2,
}) async {
  const recoveryMarker = '__PYRITE_RECOVERED__';
  final encodedMarker = base64Encode(utf8.encode(recoveryMarker));
  final recoveryCommand = utf8.encode(
    "import ubinascii;print(ubinascii.a2b_base64('$encodedMarker').decode())\r\n",
  );
  final marker = utf8.encode(recoveryMarker);
  final friendlyPrompt = utf8.encode('>>> ');
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    queue.clear();
    writeBytes([0x03, 0x03, 0x03, 0x03, 0x03]);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    writeBytes([0x02]); // CTRL-B: leave raw REPL if necessary.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    queue.clear();
    writeBytes(recoveryCommand);
    try {
      await queue.readUntil(marker, const Duration(seconds: 2));
      await queue.readUntil(friendlyPrompt, const Duration(seconds: 2));
      debugPrint('[txn] device recovery confirmed on attempt ${attempt + 1}');
      return true;
    } on SerialCancelledException {
      return false;
    } on TimeoutException {
      // Retry with another interrupt burst.
    }
  }
  debugPrint('[txn] device recovery could not confirm friendly REPL');
  return false;
}

/// Runs a REPL transaction with mutex, I/O pausing, and cleanup.
///
Future<T> _runTransaction<T>(
  ProviderReader read,
  Future<T> Function(DeviceSession session, ReplMode mode) action, {
  void Function()? Function(SerialByteQueue queue)? onSetup,
  ReplMode? forceMode,
  int interruptCount = 12,
  int interruptIntervalMs = 30,
  Duration settleDelay = const Duration(milliseconds: 150),
  Duration exitSettleDelay = const Duration(milliseconds: 300),
  String runningOperationId = 'code-exec',
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
      read(serialProvider.notifier).sendBytes(Uint8List.fromList(bytes));
    }

    var termination = TransactionTermination.none;

    void requestHardwareReset() {
      if (termination != TransactionTermination.none) {
        debugPrint('[txn] duplicate hardware reset ignored');
        return;
      }
      termination = TransactionTermination.hardwareReset;
      debugPrint('[txn] hardware reset requested; cancelling queue');
      queue.cancel();
    }

    read(hardwareResetControllerProvider).register(requestHardwareReset);

    // Register running operation so the status bar can show an indicator
    // with interrupt and force-reset buttons.
    read(runningOperationsProvider.notifier).start(
      RunningOperation(
        id: runningOperationId,
        label: '运行中',
        icon: Icons.play_arrow,
        canInterrupt: true,
        canForceReset:
            read(hardwareResetStrategyProvider) !=
            HardwareResetStrategy.disabled,
        onInterrupt: () {
          if (termination != TransactionTermination.none) {
            debugPrint('[txn] duplicate interrupt ignored during recovery');
            return;
          }
          termination = TransactionTermination.interrupt;
          debugPrint(
            '[txn] onInterrupt fired, sending 5x CTRL-C + cancelling queue',
          );
          // 1. Send multiple CTRL-C to the device to stop execution.
          writeBytes([0x03, 0x03, 0x03, 0x03, 0x03]);
          // 2. Cancel the IDE-side queue so pending reads unblock and the
          //    finally block runs, releasing the mutex and all state.
          queue.cancel();
          debugPrint('[txn] queue cancelled, isCancelled=${queue.isCancelled}');
        },
        onForceReset: () {
          requestHardwareReset();
        },
      ),
    );

    final mode = forceMode ?? read(replModeProvider) ?? ReplMode.rawRepl;
    DeviceSession? session;
    try {
      debugPrint('[txn] START mode=$mode');
      try {
        debugPrint('[txn] entering REPL...');
        session = await _initSessionAndEnterRepl(
          queue,
          writeBytes,
          mode,
          interruptCount: interruptCount,
          interruptIntervalMs: interruptIntervalMs,
          settleDelay: settleDelay,
        );
        debugPrint('[txn] REPL entered OK');
      } catch (e) {
        debugPrint('[txn] enterRepl failed: $e');
        if ((interruptCount < 12 ||
                settleDelay < const Duration(milliseconds: 150)) &&
            !queue.isCancelled) {
          debugPrint('[txn] retrying REPL with conservative handshake');
          queue.clear();
          session = await _initSessionAndEnterRepl(queue, writeBytes, mode);
          debugPrint('[txn] REPL entered after conservative retry');
        } else {
          rethrow;
        }
      }
      debugPrint('[txn] running action...');
      return await action(session, mode);
    } finally {
      debugPrint('[txn] FINALLY: queue.isCancelled=${queue.isCancelled}');
      read(hardwareResetControllerProvider).unregister(requestHardwareReset);
      cleanup?.call();
      try {
        if (termination == TransactionTermination.none && session != null) {
          debugPrint('[txn] exitRepl...');
          await session.exitRepl(mode);
          debugPrint('[txn] exitRepl done');
        } else if (termination != TransactionTermination.none) {
          debugPrint('[txn] interrupted; skipping normal REPL exit');
        }
      } catch (e) {
        debugPrint('[txn] exitRepl error: $e');
      }
      queue.cancel();
      queue.clear();
      read(serialDataCallbacksProvider.notifier).remove(callback);
      try {
        if (termination == TransactionTermination.interrupt) {
          final recoveryQueue = SerialByteQueue();
          void recoveryCallback(Uint8List data) => recoveryQueue.add(data);
          read(serialDataCallbacksProvider.notifier).add(recoveryCallback);
          try {
            var recovered = await _recoverInterruptedDevice(
              recoveryQueue,
              writeBytes,
            );
            if (!recovered && read(serialProvider).isConnected) {
              debugPrint(
                '[txn] soft recovery failed; reopening the serial connection',
              );
              final serial = read(serialProvider.notifier);
              final baudRate = read(serialProvider).baudRate;
              recovered = await serial.reconnectAtBaud(
                baudRate,
                initializeDevice: false,
              );
              if (recovered) {
                await Future<void>.delayed(const Duration(milliseconds: 500));
                recovered = await _recoverInterruptedDevice(
                  recoveryQueue,
                  writeBytes,
                  maxAttempts: 1,
                );
              }
            }
            if (!recovered && read(serialProvider).isConnected) {
              debugPrint(
                '[txn] device remains unresponsive; disconnecting the port',
              );
              await read(serialProvider.notifier).disconnectPort();
            }
            debugPrint('[txn] interrupt recovery result=$recovered');
          } finally {
            recoveryQueue.cancel();
            read(serialDataCallbacksProvider.notifier).remove(recoveryCallback);
          }
        } else if (termination == TransactionTermination.hardwareReset) {
          final strategy = read(hardwareResetStrategyProvider);
          final reset = await read(
            serialProvider.notifier,
          ).hardwareReset(strategy);
          debugPrint('[txn] hardware reset result=$reset');
        } else {
          // Leave successful transactions at the friendly prompt.
          writeBytes([0x03, 0x03]);
          writeBytes([0x02]);
          await Future<void>.delayed(exitSettleDelay);
        }
      } finally {
        read(runningOperationsProvider.notifier).stop(runningOperationId);
        read(serialReplIoPausedProvider.notifier).state = false;
        debugPrint('[txn] FINALLY done');
      }
    }
  });
}

void _ensureConnected(ProviderReader read) {
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
  String runningOperationId = 'code-exec',
}) {
  return _runTransaction(
    ref.read,
    (session, mode) => session.execute(python, timeout: timeout, mode: mode),
    runningOperationId: runningOperationId,
    onSetup: (queue) {
      final sub = ref.listen(serialProvider, (_, next) {
        if ((next as UsbSerialState?)?.isConnected == false) queue.cancel();
      });
      return () => sub.close();
    },
  );
}

/// Runs multiple commands inside one transaction. Raw REPL stays open between
/// commands; Paste mode only re-enters paste input and keeps Python globals.
Future<T> runPythonInReplSession<T>(
  Ref ref,
  Future<T> Function(DeviceSession session, ReplMode mode) action,
) {
  return _runTransaction(
    ref.read,
    action,
    interruptCount: 3,
    interruptIntervalMs: 30,
    settleDelay: const Duration(milliseconds: 50),
    exitSettleDelay: const Duration(milliseconds: 80),
    onSetup: (queue) {
      final sub = ref.listen(serialProvider, (_, next) {
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
      final sub = ref.listenManual(serialProvider, (_, next) {
        if ((next as UsbSerialState?)?.isConnected == false) queue.cancel();
      });
      return () => sub.close();
    },
  );
}

/// Runs a Python script while streaming Base64-framed data into stdin.
/// Uses regular raw REPL mode (CTRL-A + code + CTRL-D) because
/// sys.stdin.buffer.readinto() does not work during code execution in
/// raw-paste mode on many boards (including K230D).
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
    forceMode: ReplMode.rawRepl,
    onSetup: (queue) {
      final sub = ref.listen(serialProvider, (_, next) {
        if ((next as UsbSerialState?)?.isConnected == false) queue.cancel();
      });
      return () => sub.close();
    },
  );
}

/// Reads a file as raw bytes. Size lookup and transfer share one raw REPL
/// transaction, avoiding an extra interrupt/entry/exit handshake.
Future<Uint8List> runPythonReadDeviceFile(
  Ref ref,
  String remotePath, {
  void Function(int received, int total)? onProgress,
}) {
  return _runTransaction(
    ref.read,
    (session, mode) async {
      final path = _boardFileExpr(remotePath);
      final sizeOutput = await session.executeRawCommand(
        "import os\nprint(os.stat($path)[6])",
        timeout: const Duration(seconds: 5),
      );
      final expectedSize = int.tryParse(sizeOutput.trim());
      if (expectedSize == null || expectedSize < 0) {
        throw DeviceSessionException(
          'Invalid file size response: ${sizeOutput.trim()}',
        );
      }
      onProgress?.call(0, expectedSize);
      if (expectedSize == 0) return Uint8List(0);

      final baudRate = ref.read(serialProvider).baudRate;
      final wireSeconds = (expectedSize * 10 / math.max(baudRate, 1)).ceil();
      final timeout = Duration(seconds: math.max(30, wireSeconds + 15));
      final script =
          "import os,sys\n"
          "_out=sys.stdout.buffer\n"
          "p=$path\n"
          "with open(p,'rb') as f:\n"
          " while True:\n"
          "  c=f.read(512)\n"
          "  if not c:break\n"
          "  _out.write(c)\n";

      debugPrint(
        '[raw-input] readDeviceFile path=$remotePath size=$expectedSize',
      );

      final raw = await session.readRawFile(
        script,
        expectedSize,
        timeout: timeout,
        onProgress: onProgress,
      );
      debugPrint('[raw-input] readDeviceFile done: ${raw.length} bytes');
      return raw;
    },
    forceMode: ReplMode.rawRepl,
    onSetup: (queue) {
      final sub = ref.listen(serialProvider, (_, next) {
        if ((next as UsbSerialState?)?.isConnected == false) queue.cancel();
      });
      return () => sub.close();
    },
  );
}

String _boardFileExpr(String path) {
  return "'${path.replaceAll("'", "\\'")}'";
}
