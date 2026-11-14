import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/logging/app_log.dart';
import 'package:pyrite_ide/core/services/serial/base_usb_serial.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/status_bar/running_operation_provider.dart';

// ---------------------------------------------------------------------------
// ReplMutex — prevents concurrent REPL transactions
// ---------------------------------------------------------------------------

class ReplMutex {
  bool _locked = false;
  final List<Completer<void>> _waitQueue = [];

  bool get isLocked => _locked;

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

  Future<T?> tryRunExclusive<T>(Future<T> Function() action) async {
    if (_locked || _waitQueue.isNotEmpty) return null;
    _locked = true;
    try {
      return await action();
    } finally {
      _locked = false;
      if (_waitQueue.isNotEmpty) {
        _waitQueue.removeAt(0).complete();
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
    this.waitForPasteEcho = false,
  }) : _writeBytes = writeBytes;

  final SerialByteQueue queue;
  final void Function(List<int>) _writeBytes;
  final bool waitForPasteEcho;
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

  /// Maximum Base64 characters sent as one stdin line during raw-input
  /// uploads. 256 chars (+ newline) decode to at most 192 payload bytes —
  /// small enough for the device to buffer while the VM is briefly stalled.
  static const int _stdinLineChars = 256;

  /// Pause between the stdin lines of one chunk so the device can drain each
  /// line before the next one arrives.
  static const Duration _stdinLineGap = Duration(milliseconds: 1);

  // Paste-mode markers (wraps user code to extract clean output).
  static const _startMarker = '__PYRITE_NORMAL_REPL_START__';
  static const _endMarker = '__PYRITE_NORMAL_REPL_END__';

  // -- Public: enter / exit ------------------------------------------------

  /// Enters the selected REPL mode after CTRL-C has been sent.
  Future<void> enterRepl(ReplMode mode, {Duration? timeout}) async {
    final t = timeout ?? const Duration(seconds: 5);
    AppLog.d('repl', 'enter mode=$mode timeout=${t.inSeconds}s');

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
    AppLog.d(
      'repl',
      'exit mode=$mode timeout=${t.inSeconds}s cancelled=${queue.isCancelled}',
    );
    switch (mode) {
      case ReplMode.paste:
        _write([0x03]); // CTRL-C
        queue.clear();
        try {
          await queue.readUntil(_prompt3, t);
        } catch (error) {
          AppLog.d('repl', 'waiting for the paste prompt failed: $error');
        }
        break;
      case ReplMode.rawRepl:
        queue.clear();
        _write([0x03]); // CTRL-C
        await Future<void>.delayed(const Duration(milliseconds: 50));
        queue.clear();
        break;
    }
  }

  /// Performs a MicroPython soft reset from the friendly prompt: CTRL-D on an
  /// empty input line reboots the VM, dropping `sys.modules` and any task
  /// state left by earlier runs so the next run imports freshly uploaded
  /// files instead of modules cached by a previous import. The device
  /// answers with the "MPY: soft reboot" banner and a fresh friendly prompt.
  Future<void> softReset({Duration? timeout}) async {
    final t = timeout ?? const Duration(seconds: 5);
    AppLog.d('repl', 'soft reset');
    queue.clear();
    _write([0x02]); // CTRL-B: make sure we are at the friendly prompt.
    _write([0x04]); // CTRL-D on an empty line: soft reset.
    try {
      await queue.readUntil(utf8.encode('MPY: soft reboot'), t);
    } on TimeoutException {
      // Some builds reset quietly; the prompt below still confirms the reset.
      AppLog.d('repl', 'soft reboot banner missing; waiting for prompt only');
    }
    await queue.readUntil(_prompt3, t);
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
    // Nothing to run: an empty line sent to the raw REPL makes the device
    // print OK and leave the session (PYEXEC_FORCED_EXIT) instead of framing
    // output with EOT. Skipping the round trip returns the same empty result
    // without depending on that device behaviour.
    if (code.trim().isEmpty) return '';
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
  ///
  /// Each chunk travels as several short Base64 lines instead of one long
  /// line. A 2KB chunk encoded as a single ~2.7KB line overruns the device's
  /// USB CDC receive buffer whenever the VM stalls mid-line (GC, flash I/O);
  /// the driver silently drops the excess and the device fails decoding with
  /// "incorrect padding". Short lines with a small gap between them keep the
  /// receive buffer out of the red zone; the device still ACKs once per chunk.
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
    // One start line, ten progress lines and one summary replace what used to
    // be a line (or two) per chunk: on a slow port with a sparse ACK that was
    // hundreds of lines per megabyte, each of them pushed into the output
    // panel, for no information a summary does not carry.
    final cycle = Stopwatch()..start();
    AppLog.d(
      'transfer',
      'upload start code=${code.length}B data=${AppLog.humanBytes(data.length)} '
          'chunk=$chunkSize ackEvery=$ackEvery '
          'timeout=${completionTimeout.inSeconds}s',
    );

    // Phase 1: Send code + CTRL-D to execute the device script.
    final codeBytes = utf8.encode(code);
    _write(codeBytes);
    _write(_eot); // CTRL-D: execute the code

    // Phase 2: Wait for device to signal READY.
    final readyData = await queue.readUntil(readyMarker, startupTimeout);
    _logDevText(utf8.decode(readyData, allowMalformed: true));
    AppLog.d('transfer', 'device ready, streaming payload');

    // Phase 3: Send data with sparse ACK flow control.
    var sent = 0;
    var ackCount = 0;
    while (sent < data.length) {
      if (queue.isCancelled) {
        AppLog.w(
          'transfer',
          'upload cancelled at $sent/${data.length} after '
              '${cycle.elapsedMilliseconds}ms',
        );
        throw const SerialCancelledException();
      }
      final end = math.min(sent + chunkSize, data.length);
      final encoded = base64Encode(data.sublist(sent, end));
      for (var off = 0; off < encoded.length; off += _stdinLineChars) {
        final stop = math.min(off + _stdinLineChars, encoded.length);
        _write(utf8.encode('${encoded.substring(off, stop)}\n'));
        if (stop < encoded.length) {
          await Future<void>.delayed(_stdinLineGap);
        }
      }
      sent = end;
      ackCount++;
      if (ackEvery > 0 && ackCount % ackEvery == 0) {
        final ack = await _readUntilPattern(
          0x2B,
          completionTimeout,
          // The device reports write failures as a DEV-LOG + PYRITE_WRITE_ERR
          // line instead of a '+'. Surfacing the line immediately reports the
          // real cause (and lets the caller retry) instead of burning the
          // whole completion timeout on a missing ACK.
          onError: (line) {
            final index = line.indexOf('PYRITE_WRITE_ERR:');
            if (index >= 0) {
              throw DeviceSessionException(line.substring(index).trim());
            }
          },
        );
        if (!ack) {
          throw DeviceSessionException(
            'Device ACK timeout during data transfer',
          );
        }
      }
      onProgress?.call(sent, data.length);
      AppLog.progress('transfer', 'upload', sent, data.length);
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
    AppLog.i(
      'transfer',
      'upload done ${AppLog.humanBytes(data.length)} in '
          '${cycle.elapsedMilliseconds}ms '
          '(${AppLog.throughput(data.length, cycle.elapsedMilliseconds)}), '
          'acks=$ackCount',
    );
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

  /// Logs any `[DEV-LOG]` lines found in [text].
  ///
  /// Called with only the newly received bytes, never with the whole buffer:
  /// re-scanning an accumulated multi-megabyte download once per chunk was
  /// quadratic work whose only product was a handful of device lines.
  static void _logDevText(String text) {
    for (final line in text.split('\n')) {
      final trimmed = line.trimRight();
      if (trimmed.startsWith('[DEV-LOG]')) {
        AppLog.d('device', trimmed);
      }
    }
  }

  /// Reads single bytes until [pattern] arrives.
  ///
  /// Returns `true` if found, `false` on timeout. Cancellation is propagated
  /// as [SerialCancelledException] so callers never retry an interrupted job.
  /// Bytes that are not the target are collected into lines: each completed
  /// line is handed to [onError] (throwing from it aborts the wait) so a
  /// device-side write failure surfaces immediately instead of burning the
  /// whole timeout on a missing ACK. DEV-LOG lines are logged as they arrive.
  ///
  /// A `String` pattern is deliberately not supported: matching it required
  /// converting and re-scanning the whole accumulated buffer on every byte,
  /// which is quadratic in the transfer size. The only caller waits for the
  /// ACK byte.
  Future<bool> _readUntilPattern(
    int pattern,
    Duration timeout, {
    void Function(String line)? onError,
  }) async {
    final sw = Stopwatch()..start();
    final buf = StringBuffer();
    while (sw.elapsed < timeout) {
      if (queue.isCancelled) throw const SerialCancelledException();
      if (queue.hasData) {
        final byte = await queue.readBytes(1, const Duration(milliseconds: 50));
        if (byte[0] == pattern) return true;
        final ch = String.fromCharCodes(byte);
        if (ch == '\n') {
          final line = buf.toString();
          buf.clear();
          _logDevText(line);
          onError?.call(line);
        } else if (ch != '\r') {
          buf.write(ch);
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
    return false;
  }

  // -- Paste mode -----------------------------------------------------------

  Future<void> _enterPasteMode(Duration timeout) async {
    // Wait for the device to finish processing CTRL-C. Some WebREPL
    // implementations deliver the normal prompt and the paste banner in
    // separate packets, so preserve a paste marker if it is already present.
    try {
      await _waitForNormalPromptOrPasteReady(timeout);
    } on SerialCancelledException {
      rethrow;
    } catch (error) {
      AppLog.d('repl', 'waiting for the normal prompt failed: $error');
    }
    if (queue.indexOf(_pastePrompt) < 0) {
      queue.clear();
      _write([0x05]); // Ctrl-E
      await _waitForPasteReady(timeout);
    } else {
      await _consumePastePrompt();
    }
  }

  static final _pastePrompt = Uint8List.fromList([0x3D, 0x3D, 0x3D]);

  Future<void> _waitForNormalPromptOrPasteReady(Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      if (queue.isCancelled) throw const SerialCancelledException();
      if (queue.indexOf(_pastePrompt) >= 0) return;
      if (queue.indexOf(_prompt3) >= 0) {
        await queue.readUntil(_prompt3, Duration.zero);
        return;
      }
      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Timed out waiting for REPL prompt', timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> _waitForPasteReady(Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      if (queue.isCancelled) throw const SerialCancelledException();
      if (queue.indexOf(_pastePrompt) >= 0) {
        await _consumePastePrompt();
        return;
      }
      if (queue.indexOf(_dotsPrompt) >= 0) {
        await queue.readUntil(_dotsPrompt, Duration.zero);
        return;
      }
      if (queue.indexOf(_prompt3) >= 0) {
        // A prompt can arrive before the paste banner over WebREPL. Consume
        // it and keep waiting instead of reporting a false unsupported-mode
        // error.
        await queue.readUntil(_prompt3, Duration.zero);
        continue;
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
    await _writePasteScript(
      Uint8List.fromList(utf8.encode(script)),
      timeout: timeout,
    );
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
    await _writePasteScript(
      Uint8List.fromList(utf8.encode(script)),
      timeout: timeout,
    );
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
    // An empty line followed by EOT is the raw REPL exit sequence: the device
    // acknowledges with OK and reboots out of the session, so the stdout and
    // stderr EOT frames this method waits for are never sent. There is
    // nothing to execute, so report the start and finish immediately.
    if (code.trim().isEmpty) {
      onStarted();
      return;
    }

    final bytes = utf8.encode(code);
    _write(bytes);
    _write(_eot);
    onStarted();

    final ack = await queue.readBytes(2, timeout);
    if (ack.length != 2 || ack[0] != 0x4f || ack[1] != 0x4b) {
      throw const DeviceSessionException('Raw REPL did not acknowledge code.');
    }
    // The startup timeout also bounds each streamed frame: a device that
    // stops emitting output must surface as an error instead of holding the
    // REPL transaction (and its mutex) forever.
    await queue.readUntilStreaming(_eot, timeout: timeout, onData: onStdout);
    await queue.readUntilStreaming(_eot, timeout: timeout, onData: onStderr);
    await queue.readUntil(_prompt, timeout);
  }

  // -- Helpers --------------------------------------------------------------

  /// Sends paste-mode input in conservative blocks. WebREPL implementations
  /// on ESP-class boards may accept the Paste Mode banner but fail to process
  /// a large text frame followed immediately by Ctrl-D. Keeping blocks below
  /// the common 128-byte boundary and yielding between them mirrors Thonny's
  /// WebREPL behavior without requiring echo parsing on the shared queue.
  Future<void> _writePasteScript(
    Uint8List bytes, {
    required Duration timeout,
  }) async {
    if (waitForPasteEcho) {
      bytes = _normalizePasteNewlines(bytes);
    }
    const blockSize = 127;
    var offset = 0;
    while (offset < bytes.length) {
      var end = math.min(offset + blockSize, bytes.length);
      // Do not split a multi-byte UTF-8 sequence between WebSocket frames.
      while (end > offset &&
          end < bytes.length &&
          (bytes[end] & 0xC0) == 0x80) {
        end--;
      }
      if (end > offset && end < bytes.length && bytes[end - 1] == 0x0D) {
        end--;
      }
      if (end == offset) end = math.min(offset + blockSize, bytes.length);
      final block = bytes.sublist(offset, end);
      _write(block);
      if (waitForPasteEcho) {
        await _waitForPasteEcho(block, timeout);
      }
      offset = end;
      if (offset < bytes.length) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }
  }

  Uint8List _normalizePasteNewlines(Uint8List bytes) {
    final normalized = <int>[];
    for (var index = 0; index < bytes.length; index++) {
      final byte = bytes[index];
      if (byte == 0x0A && (index == 0 || bytes[index - 1] != 0x0D)) {
        normalized.add(0x0D);
      }
      normalized.add(byte);
    }
    return Uint8List.fromList(normalized);
  }

  Future<void> _waitForPasteEcho(List<int> block, Duration timeout) async {
    final expected = block.where((byte) => byte != 0x0D).toList();
    final stopwatch = Stopwatch()..start();
    var matched = 0;
    var mayHaveLinePrefix = false;
    final prefixCandidate = <int>[];
    const linePrefix = [0x3D, 0x3D, 0x3D, 0x20];

    Future<int> nextByte() async {
      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException(
          'Timed out waiting for paste echo at $matched/${expected.length} bytes',
          timeout,
        );
      }
      try {
        return (await queue.readBytes(1, remaining)).single;
      } on TimeoutException {
        throw TimeoutException(
          'Timed out waiting for paste echo at $matched/${expected.length} bytes',
          timeout,
        );
      }
    }

    void matchByte(int byte) {
      if (byte == 0x0D) return;
      // A few WebREPL builds duplicate LF while echoing CRLF input. Treat an
      // LF where source expects a regular character as transport noise; real
      // source newlines are still matched normally.
      if (byte == 0x0A &&
          matched < expected.length &&
          expected[matched] != 0x0A) {
        return;
      }
      if (matched >= expected.length || byte != expected[matched]) {
        final expectedByte = matched < expected.length
            ? '0x${expected[matched].toRadixString(16).padLeft(2, '0')}'
            : 'end of echo';
        throw DeviceSessionException(
          'Unexpected paste echo at byte $matched: expected $expectedByte, '
          'got 0x${byte.toRadixString(16).padLeft(2, '0')}.',
        );
      }
      matched++;
      mayHaveLinePrefix = byte == 0x0A;
    }

    while (matched < expected.length || mayHaveLinePrefix) {
      final byte = await nextByte();
      if (byte == 0x0D) continue;

      if (mayHaveLinePrefix) {
        // Some WebREPL builds emit an additional line ending before the
        // continuation prefix. It is transport echo, not source content.
        if (byte == 0x0A && prefixCandidate.isEmpty) {
          continue;
        }
        prefixCandidate.add(byte);
        var prefixStillMatches = prefixCandidate.length <= linePrefix.length;
        for (
          var index = 0;
          prefixStillMatches && index < prefixCandidate.length;
          index++
        ) {
          prefixStillMatches = prefixCandidate[index] == linePrefix[index];
        }
        if (prefixStillMatches && prefixCandidate.length < linePrefix.length) {
          continue;
        }
        if (prefixStillMatches) {
          prefixCandidate.clear();
          mayHaveLinePrefix = false;
          continue;
        }

        final replay = List<int>.from(prefixCandidate);
        prefixCandidate.clear();
        mayHaveLinePrefix = false;
        for (final replayByte in replay) {
          matchByte(replayByte);
        }
        continue;
      }

      matchByte(byte);
    }
  }

  Future<void> _consumePastePrompt() async {
    await queue.readUntil(_pastePrompt, Duration.zero);
    if (queue.firstByte == 0x20) {
      await queue.readBytes(1, Duration.zero);
    }
  }

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
  bool softReset = false,
}) async {
  final session = DeviceSession(queue: queue, writeBytes: writeBytes);
  for (var i = 0; i < interruptCount; i++) {
    writeBytes([0x03]);
    await Future<void>.delayed(Duration(milliseconds: interruptIntervalMs));
  }
  await Future<void>.delayed(settleDelay);
  if (softReset) {
    await session.softReset();
  }
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
      AppLog.i('txn', 'device recovery confirmed on attempt ${attempt + 1}');
      return true;
    } on SerialCancelledException {
      return false;
    } on TimeoutException {
      // Retry with another interrupt burst.
    }
  }
  AppLog.w('txn', 'device recovery could not confirm friendly REPL');
  return false;
}

/// Best-effort call site of the transaction that is about to start.
///
/// A transaction owns the serial line for about a second even when its action
/// is trivial — the 12-interrupt handshake and the exit sequence dominate — so
/// a transaction that repeats every second is indistinguishable in the log from
/// any other: `[txn] START` says nothing about who asked for it. Naming the
/// first frame outside this file answers that without changing behaviour. In a
/// debug build it resolves to `file.dart:line`; a release build keeps only the
/// enclosing function name, which still identifies the caller.
String _describeTransactionCaller() {
  const skipped = [
    'device_executor.dart',
    'package:flutter/',
    'dart:async',
    'dart:core',
    'dart:collection',
  ];
  for (final frame in StackTrace.current.toString().split('\n')) {
    final line = frame.trim();
    if (line.isEmpty || !line.startsWith('#')) continue;
    if (skipped.any(line.contains)) continue;
    return line.replaceFirst(RegExp(r'^#\d+\s+'), '');
  }
  return 'unknown';
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
  bool softReset = false,
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
        AppLog.d('txn', 'duplicate hardware reset ignored');
        return;
      }
      termination = TransactionTermination.hardwareReset;
      AppLog.i('txn', 'hardware reset requested; cancelling queue');
      queue.cancel();
    }

    read(hardwareResetControllerProvider).register(requestHardwareReset);

    // Register running operation so the status bar can show an indicator
    // with interrupt and force-reset buttons.
    read(runningOperationsProvider.notifier).start(
      RunningOperation(
        id: runningOperationId,
        labelKey: I18nKey.statusRunning,
        icon: Icons.play_arrow,
        canInterrupt: true,
        canForceReset:
            read(hardwareResetStrategyProvider) !=
            HardwareResetStrategy.disabled,
        onInterrupt: () {
          if (termination != TransactionTermination.none) {
            AppLog.d('txn', 'duplicate interrupt ignored during recovery');
            return;
          }
          termination = TransactionTermination.interrupt;
          AppLog.i('txn', 'interrupt requested: CTRL-C burst + queue cancel');
          // 1. Send multiple CTRL-C to the device to stop execution.
          writeBytes([0x03, 0x03, 0x03, 0x03, 0x03]);
          // 2. Cancel the IDE-side queue so pending reads unblock and the
          //    finally block runs, releasing the mutex and all state.
          queue.cancel();
        },
        onForceReset: requestHardwareReset,
      ),
    );

    final mode = forceMode ?? read(replModeProvider) ?? ReplMode.rawRepl;
    DeviceSession? session;
    // Timed so a repeating transaction can be told apart from a slow one: the
    // elapsed value is the whole cycle (handshake + action + exit), which is
    // what a user sees as the cadence in the log.
    final cycle = Stopwatch()..start();
    // One START/END pair per transaction replaces the seven stage lines this
    // path used to print (entering REPL, entered, running, exiting, done...).
    // The stages are visible in the elapsed value; only the outcome and the
    // caller are what a reader needs.
    var outcome = 'ok';
    try {
      AppLog.d(
        'txn',
        'START mode=$mode op=$runningOperationId '
            'from=${_describeTransactionCaller()}',
      );
      try {
        session = await _initSessionAndEnterRepl(
          queue,
          writeBytes,
          mode,
          interruptCount: interruptCount,
          interruptIntervalMs: interruptIntervalMs,
          settleDelay: settleDelay,
          softReset: softReset,
        );
      } catch (e) {
        AppLog.w('txn', 'enterRepl failed: $e');
        if ((interruptCount < 12 ||
                settleDelay < const Duration(milliseconds: 150)) &&
            !queue.isCancelled) {
          AppLog.w('txn', 'retrying REPL with conservative handshake');
          queue.clear();
          session = await _initSessionAndEnterRepl(
            queue,
            writeBytes,
            mode,
            softReset: softReset,
          );
        } else {
          rethrow;
        }
      }
      return await action(session, mode);
    } catch (e) {
      outcome = switch (e) {
        SerialCancelledException() => 'cancelled',
        _ => 'error',
      };
      rethrow;
    } finally {
      AppLog.d(
        'txn',
        'END mode=$mode op=$runningOperationId result=$outcome '
            'elapsed=${cycle.elapsedMilliseconds}ms '
            'cancelled=${queue.isCancelled}',
      );
      read(hardwareResetControllerProvider).unregister(requestHardwareReset);
      cleanup?.call();
      try {
        if (termination == TransactionTermination.none && session != null) {
          await session.exitRepl(mode);
        } else if (termination != TransactionTermination.none) {
          AppLog.d('txn', 'interrupted; skipping normal REPL exit');
        }
      } catch (e) {
        AppLog.w('txn', 'exitRepl error: $e');
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
              AppLog.w(
                'txn',
                'soft recovery failed; reopening the serial connection',
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
              AppLog.w(
                'txn',
                'device remains unresponsive; disconnecting the port',
              );
              await read(serialProvider.notifier).disconnectPort();
            }
            AppLog.i('txn', 'interrupt recovery result=$recovered');
          } finally {
            recoveryQueue.cancel();
            read(serialDataCallbacksProvider.notifier).remove(recoveryCallback);
          }
        } else if (termination == TransactionTermination.hardwareReset) {
          final strategy = read(hardwareResetStrategyProvider);
          final reset = await read(
            serialProvider.notifier,
          ).hardwareReset(strategy);
          AppLog.i('txn', 'hardware reset result=$reset');
        } else {
          // Leave successful transactions at the friendly prompt.
          writeBytes([0x03, 0x03]);
          writeBytes([0x02]);
          await Future<void>.delayed(exitSettleDelay);
        }
      } finally {
        read(runningOperationsProvider.notifier).stop(runningOperationId);
        read(serialReplIoPausedProvider.notifier).state = false;
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

const replCompletionOperationId = 'repl-completion';
const _replCompletionMarker = '__PYRITE_COMPLETION__';

/// Queries names while the device is already showing a friendly prompt.
///
/// This path deliberately avoids the regular transaction handshake because
/// completion must never interrupt a program or clear the user's local input.
Future<List<String>?> queryReplNamesAtPrompt(
  WidgetRef ref, {
  String? owner,
  Duration timeout = const Duration(milliseconds: 900),
}) async {
  if (owner != null && !RegExp(r'^[A-Za-z_]\w*$').hasMatch(owner)) {
    return null;
  }
  if (!ref.read(serialProvider).isConnected ||
      ref.read(runningOperationsProvider).isNotEmpty) {
    return null;
  }

  final mutex = ref.read(replMutexProvider);
  return mutex.tryRunExclusive<List<String>?>(() async {
    if (!ref.read(serialProvider).isConnected ||
        ref.read(runningOperationsProvider).isNotEmpty) {
      return null;
    }

    final queue = SerialByteQueue();
    void callback(Uint8List data) => queue.add(data);
    final disconnect = ref.listenManual<SerialProviderState>(serialProvider, (
      _,
      next,
    ) {
      if (!next.isConnected) queue.cancel();
    });
    ref.read(serialReplIoPausedProvider.notifier).state = true;
    ref.read(serialDataCallbacksProvider.notifier).add(callback);
    ref
        .read(runningOperationsProvider.notifier)
        .start(
          const RunningOperation(
            id: replCompletionOperationId,
            label: 'REPL completion',
            icon: Icons.manage_search,
          ),
        );

    try {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      queue.clear();
      final command = buildReplCompletionProbe(owner);
      ref.read(serialProvider.notifier).sendCommand(command, chunked: false);
      final response = await queue.readUntil(utf8.encode('>>> '), timeout);
      return parseReplCompletionProbeResponse(
        utf8.decode(response, allowMalformed: true),
      );
    } on TimeoutException {
      return null;
    } on SerialCancelledException {
      return null;
    } finally {
      queue.cancel();
      disconnect.close();
      ref.read(serialDataCallbacksProvider.notifier).remove(callback);
      ref
          .read(runningOperationsProvider.notifier)
          .stop(replCompletionOperationId);
      ref.read(serialReplIoPausedProvider.notifier).state = false;
    }
  });
}

@visibleForTesting
String buildReplCompletionProbe(String? owner) {
  if (owner != null && !RegExp(r'^[A-Za-z_]\w*$').hasMatch(owner)) {
    throw ArgumentError.value(owner, 'owner', 'Only a direct name is allowed');
  }
  final expression = owner == null
      ? 'dir()'
      : "dir($owner) if '$owner' in globals() else []";
  return "print('$_replCompletionMarker'+__import__('ujson').dumps($expression))\r\n";
}

@visibleForTesting
List<String>? parseReplCompletionProbeResponse(String response) {
  final normalized = response.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (final line in normalized.split('\n').reversed) {
    final trimmed = line.trim();
    if (!trimmed.startsWith(_replCompletionMarker)) continue;
    try {
      final decoded = jsonDecode(
        trimmed.substring(_replCompletionMarker.length),
      );
      if (decoded is! List) return null;
      return decoded
          .whereType<String>()
          .where((name) => !name.startsWith('__'))
          .toSet()
          .toList()
        ..sort();
    } on FormatException {
      return null;
    }
  }
  return null;
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
      return sub.close;
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
      return sub.close;
    },
  );
}

/// Runs a Python script while forwarding stdout and stderr as the device
/// emits them.
///
/// When [workingDirectory] is set, the device's working directory is switched
/// there first — within the same transaction, so a preceding soft reset (which
/// restores the firmware default directory) cannot undo it.
Future<void> runPythonOnDeviceStreaming(
  WidgetRef ref,
  String python, {
  Duration startupTimeout = _defaultTimeout,
  ReplMode? forceMode,
  String runningOperationId = 'code-exec',
  bool softReset = false,
  String? workingDirectory,
  required void Function() onStarted,
  required void Function(Uint8List data) onStdout,
  required void Function(Uint8List data) onStderr,
}) {
  // Empty source is never sent to the raw REPL: an empty line plus EOT makes
  // the device print OK and leave the session without the stdout/stderr EOT
  // frames, so the streaming wait would never finish. There is nothing to
  // execute, so complete the run without opening a transaction.
  if (python.trim().isEmpty) {
    onStarted();
    return Future<void>.value();
  }
  return _runTransaction(
    ref.read,
    (session, mode) async {
      if (workingDirectory != null) {
        await setDeviceWorkingDirectory(session, workingDirectory, mode: mode);
      }
      await session.executeStreaming(
        python,
        timeout: startupTimeout,
        mode: mode,
        onStarted: onStarted,
        onStdout: onStdout,
        onStderr: onStderr,
      );
    },
    onSetup: (queue) {
      final sub = ref.listenManual(serialProvider, (_, next) {
        if ((next as UsbSerialState?)?.isConnected == false) queue.cancel();
      });
      return sub.close;
    },
    forceMode: forceMode,
    softReset: softReset,
    runningOperationId: runningOperationId,
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
      return sub.close;
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

      final cycle = Stopwatch()..start();
      AppLog.d(
        'transfer',
        'download start path=$remotePath size=${AppLog.humanBytes(expectedSize)}',
      );

      final raw = await session.readRawFile(
        script,
        expectedSize,
        timeout: timeout,
        onProgress: onProgress,
      );
      AppLog.i(
        'transfer',
        'download done ${AppLog.humanBytes(raw.length)} in '
            '${cycle.elapsedMilliseconds}ms '
            '(${AppLog.throughput(raw.length, cycle.elapsedMilliseconds)})',
      );
      return raw;
    },
    forceMode: ReplMode.rawRepl,
    onSetup: (queue) {
      final sub = ref.listen(serialProvider, (_, next) {
        if ((next as UsbSerialState?)?.isConnected == false) queue.cancel();
      });
      return sub.close;
    },
  );
}

String _boardFileExpr(String path) {
  return "'${path.replaceAll("'", "\\'")}'";
}

/// Marker printed after a successful working-directory switch, so a silent
/// success is distinguishable from the traceback a failed one prints.
const String kDeviceChdirOkMarker = '__PYRITE_CHDIR_OK__';

/// Switches the device's working directory to [directory] inside the current
/// transaction.
///
/// The switch must happen this way — as its own command before the script —
/// rather than as a preamble on the script itself: prepending lines would
/// shift every traceback line number, and the marker keeps a failed switch
/// (missing directory, firmware without `os.chdir`) aborting the run with the
/// real error instead of quietly running from the wrong directory.
Future<void> setDeviceWorkingDirectory(
  DeviceSession session,
  String directory, {
  required ReplMode mode,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final output = await session.executeCommand(
    'import os\n'
    'os.chdir(${_boardFileExpr(directory)})\n'
    "print('$kDeviceChdirOkMarker')\n",
    timeout: timeout,
    mode: mode,
  );
  if (!output.contains(kDeviceChdirOkMarker)) {
    throw DeviceSessionException(
      output.trim().isEmpty
          ? "Switching the device working directory to '$directory' failed."
          : output.trim(),
    );
  }
}
