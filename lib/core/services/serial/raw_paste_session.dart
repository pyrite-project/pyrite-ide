import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';

/// Magic bytes for the raw-paste REPL protocol.
const int _rawPasteRespR = 0x52;
const int _rawPasteAccepted = 0x01;
const int _rawPasteRejected = 0x00;
const int _rawRespLowerR = 0x72;
const int _rawRespA = 0x61;

/// Result of a raw REPL Python execution.
class RawExecutionResult {
  final Uint8List stdout;
  final Uint8List stderr;

  const RawExecutionResult({required this.stdout, required this.stderr});
}

/// Manages a raw-paste REPL session with a MicroPython device.
class RawPasteSession {
  static final _rawReplBanner = utf8.encode('raw REPL; CTRL-B to exit');
  static final _prompt = Uint8List.fromList([0x3e]);
  static final _eot = Uint8List.fromList([0x04]);
  static final _rawPasteRequest = Uint8List.fromList([0x05, 0x41, 0x01]);

  final void Function(List<int>) _writeBytes;
  final SerialByteQueue _queue;

  RawPasteSession({
    required void Function(List<int>) writeBytes,
    SerialByteQueue? queue,
  }) : _writeBytes = writeBytes,
       _queue = queue ?? SerialByteQueue();

  SerialByteQueue get queue => _queue;

  Future<void> enterRawRepl({Duration timeout = const Duration(seconds: 5)}) async {
    _write(_eot);
    _write(_eot);
    await _queue.readUntil(_prompt, timeout);
    _write(Uint8List.fromList([0x01]));
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

  Future<void> exitRawRepl({Duration timeout = const Duration(seconds: 2)}) async {
    _queue.clear();
    _write(_eot);
    await _queue.readUntil(_prompt, timeout);
  }

  Future<String> execute(
    String code, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final bytes = utf8.encode(code);
    final response = await _tryEnterRawPaste(timeout);
    if (response == null) {
      throw RawPasteException('Device rejected raw-paste mode');
    }
    final result = await _executeRawPaste(bytes, response, timeout);
    return utf8.decode(result.stdout, allowMalformed: true);
  }

  Future<void> executeStreaming(
    String code, {
    Duration startupTimeout = const Duration(seconds: 20),
    required void Function() onStarted,
    required void Function(Uint8List data) onStdout,
    required void Function(Uint8List data) onStderr,
  }) async {
    final bytes = utf8.encode(code);
    final response = await _tryEnterRawPaste(startupTimeout);
    if (response == null) {
      throw RawPasteException('Device rejected raw-paste mode');
    }
    onStarted();
    await _writeRawPasteCode(bytes, response, startupTimeout);
    await _queue.readUntil(_eot, startupTimeout);
    await _queue.readUntilStreaming(_eot, onData: onStdout);
    await _queue.readUntilStreaming(_eot, onData: onStderr);
    await _queue.readUntil(_prompt, startupTimeout);
  }

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
    final response = await _tryEnterRawPaste(startupTimeout);
    if (response == null) {
      throw RawPasteException('Device rejected raw-paste mode');
    }

    final codeBytes = utf8.encode(code);
    await _writeRawPasteCode(codeBytes, response, startupTimeout);
    await _queue.readUntil(_eot, startupTimeout);

    await _queue.readUntil(readyMarker, completionTimeout);

    var sent = 0;
    var ackCount = 0;
    while (sent < data.length) {
      final end = math.min(sent + chunkSize, data.length);
      _write(data.sublist(sent, end));
      sent = end;
      ackCount++;
      if (ackEvery > 0 && ackCount % ackEvery == 0 && sent < data.length) {
        final ack = await _queue.readBytes(1, completionTimeout);
        if (ack[0] != 0x2B) {
          throw RawPasteException('Unexpected ACK: 0x${ack[0].toRadixString(16)}');
        }
      }
      onProgress?.call(sent, data.length);
    }

    await _queue.readUntil(doneMarker, completionTimeout);

    await _queue.readUntil(_eot, completionTimeout);
    await _readPayloadUntilEot(completionTimeout);
    await _queue.readUntil(_prompt, completionTimeout);
  }

  Future<int?> _tryEnterRawPaste(Duration timeout) async {
    _write(_rawPasteRequest);
    final response = await _queue.readBytes(2, timeout);
    if (response[0] == _rawPasteRespR && response[1] == _rawPasteAccepted) {
      final window = await _queue.readBytes(2, timeout);
      return window[0] | (window[1] << 8);
    }
    if (response[0] == _rawPasteRespR && response[1] == _rawPasteRejected) {
      return null;
    }
    if (response[0] == _rawRespLowerR && response[1] == _rawRespA) {
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
        final signal = (await _queue.readBytes(1, timeout))[0];
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
