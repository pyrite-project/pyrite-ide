import 'dart:async';
import 'dart:typed_data';

/// Thrown when a serial queue operation is cancelled due to device disconnect.
class SerialCancelledException implements Exception {
  final String message;
  const SerialCancelledException([
    this.message = 'Serial connection lost',
  ]);
  @override
  String toString() => 'SerialCancelledException: $message';
}

/// Buffer for receiving serial bytes and reading them by pattern or count.
class SerialByteQueue {
  final List<int> _buffer = [];
  Completer<void>? _dataCompleter;
  bool _cancelled = false;

  bool get hasData => _buffer.isNotEmpty;

  /// Returns the index of [pattern] in the buffer, or -1 if not found.
  /// Does not consume any data.
  int indexOf(List<int> pattern) => _indexOf(pattern);

  void add(Uint8List data) {
    if (_cancelled || data.isEmpty) return;
    _buffer.addAll(data);
    _dataCompleter?.complete();
    _dataCompleter = null;
  }

  /// Cancels all pending and future reads. Completes any waiting future
  /// immediately so that blocked operations unblock and release the mutex.
  void cancel() {
    _cancelled = true;
    _buffer.clear();
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
      if (_buffer.isNotEmpty) {
        onData(Uint8List.fromList(_buffer));
        _buffer.clear();
      }
      await _waitForData(_remainingNullable(timeout, stopwatch));
    }
  }

  Future<void> _waitForData(Duration? timeout) async {
    if (_cancelled) throw const SerialCancelledException();
    _dataCompleter ??= Completer<void>();
    if (timeout == null) {
      await _dataCompleter!.future;
    } else {
      await _dataCompleter!.future.timeout(timeout);
    }
    if (_cancelled) throw const SerialCancelledException();
  }

  Duration _remaining(Duration timeout, Stopwatch stopwatch) {
    final remainingMs = timeout.inMilliseconds - stopwatch.elapsedMilliseconds;
    if (remainingMs <= 0) {
      throw TimeoutException('Timed out waiting for serial data', timeout);
    }
    return Duration(milliseconds: remainingMs);
  }

  Duration? _remainingNullable(Duration? timeout, Stopwatch? stopwatch) {
    if (timeout == null || stopwatch == null) return null;
    return _remaining(timeout, stopwatch);
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
