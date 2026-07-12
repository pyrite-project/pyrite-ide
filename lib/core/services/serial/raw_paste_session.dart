import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Buffer for receiving serial bytes and reading them by pattern or count.
class SerialByteQueue {
  final List<int> _buffer = [];
  Completer<void>? _dataCompleter;

  bool get hasData => _buffer.isNotEmpty;

  void add(Uint8List data) {
    if (data.isEmpty) return;
    _buffer.addAll(data);
    _dataCompleter?.complete();
    _dataCompleter = null;
  }

  void clear() {
    _buffer.clear();
  }

  Future<Uint8List> readBytes(int count, Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    while (_buffer.length < count) {
      await _waitForData(_remaining(timeout, stopwatch));
    }
    final result = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return Uint8List.fromList(result);
  }

  Future<Uint8List> readUntil(List<int> pattern, Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      final index = _indexOf(pattern);
      if (index >= 0) {
        final end = index + pattern.length;
        final result = _buffer.sublist(0, end);
        _buffer.removeRange(0, end);
        return Uint8List.fromList(result);
      }
      await _waitForData(_remaining(timeout, stopwatch));
    }
  }

  Future<void> readUntilStreaming(
    List<int> pattern, {
    Duration? timeout,
    required void Function(Uint8List data) onData,
  }) async {
    if (pattern.isEmpty) {
      throw ArgumentError.value(pattern, 'pattern', 'Must not be empty');
    }

    final stopwatch = timeout == null ? null : (Stopwatch()..start());
    while (true) {
      final index = _indexOf(pattern);
      if (index >= 0) {
        if (index > 0) {
          onData(Uint8List.fromList(_buffer.sublist(0, index)));
        }
        _buffer.removeRange(0, index + pattern.length);
        return;
      }

      final safeLength = _buffer.length - pattern.length + 1;
      if (safeLength > 0) {
        onData(Uint8List.fromList(_buffer.sublist(0, safeLength)));
        _buffer.removeRange(0, safeLength);
      }

      await _waitForData(
        timeout == null ? null : _remaining(timeout, stopwatch!),
      );
    }
  }

  Future<void> _waitForData(Duration? timeout) async {
    _dataCompleter ??= Completer<void>();
    if (timeout == null) {
      await _dataCompleter!.future;
    } else {
      await _dataCompleter!.future.timeout(timeout);
    }
  }

  Duration _remaining(Duration timeout, Stopwatch stopwatch) {
    final remainingMs = timeout.inMilliseconds - stopwatch.elapsedMilliseconds;
    if (remainingMs <= 0) {
      throw TimeoutException('Timed out waiting for serial data', timeout);
    }
    return Duration(milliseconds: remainingMs);
  }

  int _indexOf(List<int> pattern) {
    if (pattern.isEmpty || _buffer.length < pattern.length) return -1;
    for (int i = 0; i <= _buffer.length - pattern.length; i++) {
      var matched = true;
      for (int j = 0; j < pattern.length; j++) {
        if (_buffer[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }
    return -1;
  }
}

/// Result of a raw REPL Python execution.
class RawExecutionResult {
  final Uint8List stdout;
  final Uint8List stderr;

  const RawExecutionResult({required this.stdout, required this.stderr});
}

/// Manages a raw-paste REPL session with a MicroPython device.
///
/// Usage:
/// ```dart
/// final session = RawPasteSession(writeBytes: (bytes) => serial.write(bytes));
/// try {
///   await session.enterRawRepl(timeout: timeout);
///   final output = await session.execute(pythonCode, timeout: timeout);
/// } finally {
///   await session.exitRawRepl();
/// }
/// ```
class RawPasteSession {
  static final _rawReplBanner = utf8.encode('raw REPL; CTRL-B to exit');
  static final _prompt = Uint8List.fromList([0x3e]);
  static final _eot = Uint8List.fromList([0x04]);
  static final _rawPasteRequest = Uint8List.fromList([0x05, 0x41, 0x01]);
  static final _ok = utf8.encode('OK');

  final void Function(List<int>) _writeBytes;
  final SerialByteQueue _queue;

  RawPasteSession({
    required void Function(List<int>) writeBytes,
    SerialByteQueue? queue,
  }) : _writeBytes = writeBytes,
       _queue = queue ?? SerialByteQueue();

  SerialByteQueue get queue => _queue;

  Future<void> enterRawRepl({required Duration timeout}) async {
    _write(const [0x03, 0x03]);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _queue.clear();

    _write(const [0x01]);
    await _queue.readUntil(_rawReplBanner, timeout);
    await _queue.readUntil(_prompt, timeout);
  }

  /// Sends SOH and waits for the raw-repl banner + prompt.
  /// Does NOT send CTRL-C — the caller handles interruption.
  Future<void> tryHandshake(Duration timeout) async {
    _write(const [0x01]);
    await _queue.readUntil(_rawReplBanner, timeout);
    await _queue.readUntil(_prompt, timeout);
  }

  Future<void> exitRawRepl() async {
    try {
      _write(const [0x02]);
      await _queue.readUntil(utf8.encode('>>>'), const Duration(seconds: 2));
    } catch (_) {
      // A failed exit prompt read should not mask the actual operation result.
      // The next transaction will re-enter raw REPL from a known state.
    }
  }

  Future<String> execute(String python, {required Duration timeout}) async {
    final code = Uint8List.fromList(utf8.encode(python));
    final windowIncrement = await _tryEnterRawPaste(timeout);
    final result = windowIncrement == null
        ? await _executeStandardRaw(code, timeout)
        : await _executeRawPaste(code, windowIncrement, timeout);

    if (result.stderr.isNotEmpty) {
      throw RawPasteException(
        utf8.decode(result.stderr, allowMalformed: true).trim(),
      );
    }
    return utf8.decode(result.stdout, allowMalformed: true);
  }

  Future<void> executeStreaming(
    String python, {
    required Duration startupTimeout,
    required void Function() onStarted,
    required void Function(Uint8List data) onStdout,
    required void Function(Uint8List data) onStderr,
  }) async {
    final code = Uint8List.fromList(utf8.encode(python));
    final windowIncrement = await _tryEnterRawPaste(startupTimeout);

    if (windowIncrement == null) {
      await _writeChunksWithoutFlowControl(code);
      _write(_eot);
      await _queue.readUntil(_ok, startupTimeout);
    } else {
      await _writeRawPasteCode(code, windowIncrement, startupTimeout);
      await _queue.readUntil(_eot, startupTimeout);
    }

    onStarted();
    await _queue.readUntilStreaming(_eot, onData: onStdout);

    final stderr = BytesBuilder(copy: false);
    await _queue.readUntilStreaming(
      _eot,
      onData: (data) {
        stderr.add(data);
        onStderr(data);
      },
    );
    await _queue.readUntil(_prompt, startupTimeout);

    if (stderr.length > 0) {
      throw RawPasteException(
        utf8.decode(stderr.takeBytes(), allowMalformed: true).trim(),
      );
    }
  }

  Future<int?> _tryEnterRawPaste(Duration timeout) async {
    _write(_rawPasteRequest);
    final response = await _queue.readBytes(2, timeout);
    if (response[0] == 0x52 && response[1] == 0x01) {
      final window = await _queue.readBytes(2, timeout);
      return window[0] | (window[1] << 8);
    }
    if (response[0] == 0x52 && response[1] == 0x00) {
      return null;
    }
    if (response[0] == 0x72 && response[1] == 0x61) {
      await _queue.readUntil(_prompt, timeout);
      return null;
    }
    throw RawPasteException(
      'Unexpected raw-paste handshake: ${response.toList()}',
    );
  }

  Future<RawExecutionResult> _executeRawPaste(
    Uint8List code,
    int windowIncrement,
    Duration timeout,
  ) async {
    await _writeRawPasteCode(code, windowIncrement, timeout);
    await _queue.readUntil(_eot, timeout);
    final stdout = await _readPayloadUntilEot(timeout);
    final stderr = await _readPayloadUntilEot(timeout);
    await _queue.readUntil(_prompt, timeout);
    return RawExecutionResult(stdout: stdout, stderr: stderr);
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
      while (_queue.hasData) {
        final signal = (await _queue.readBytes(1, timeout))[0];
        if (signal == 0x01) {
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
        final signal = (await _queue.readBytes(1, timeout))[0];
        if (signal == 0x01) {
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

  Future<RawExecutionResult> _executeStandardRaw(
    Uint8List code,
    Duration timeout,
  ) async {
    await _writeChunksWithoutFlowControl(code);
    _write(_eot);
    await _queue.readUntil(_ok, timeout);
    final stdout = await _readPayloadUntilEot(timeout);
    final stderr = await _readPayloadUntilEot(timeout);
    await _queue.readUntil(_prompt, timeout);
    return RawExecutionResult(stdout: stdout, stderr: stderr);
  }

  Future<void> _writeChunksWithoutFlowControl(Uint8List code) async {
    const chunkSize = 64;
    for (int i = 0; i < code.length; i += chunkSize) {
      final end = math.min(i + chunkSize, code.length);
      _write(code.sublist(i, end));
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<Uint8List> _readPayloadUntilEot(Duration timeout) async {
    final data = await _queue.readUntil(_eot, timeout);
    return Uint8List.fromList(data.sublist(0, data.length - 1));
  }

  void _write(List<int> bytes) {
    _writeBytes(bytes);
  }
}

/// Exception thrown when a raw-paste REPL operation fails.
class RawPasteException implements Exception {
  final String message;
  const RawPasteException(this.message);
  @override
  String toString() => 'RawPasteException: $message';
}
