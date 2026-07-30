import 'dart:async';
import 'dart:typed_data';

/// Thrown when a serial queue operation is cancelled due to device disconnect.
class SerialCancelledException implements Exception {
  final String message;
  const SerialCancelledException([this.message = 'Serial connection lost']);
  @override
  String toString() => 'SerialCancelledException: $message';
}

/// Buffer for receiving serial bytes and reading them by pattern or count.
class SerialByteQueue {
  final List<int> _buffer = [];
  int _readOffset = 0;
  Completer<void>? _dataCompleter;
  bool _cancelled = false;

  int get availableLength => _buffer.length - _readOffset;

  bool get hasData => availableLength > 0;

  /// Whether this queue has been cancelled (by disconnect or user interrupt).
  bool get isCancelled => _cancelled;

  /// Returns the index of [pattern] in the buffer, or -1 if not found.
  /// Does not consume any data.
  int indexOf(List<int> pattern) => _indexOf(pattern);

  void add(Uint8List data) {
    if (_cancelled || data.isEmpty) return;
    _compactIfNeeded();
    _buffer.addAll(data);
    _dataCompleter?.complete();
    _dataCompleter = null;
  }

  /// Cancels all pending and future reads. Completes any waiting future
  /// immediately so that blocked operations unblock and release the mutex.
  void cancel() {
    _cancelled = true;
    _buffer.clear();
    _readOffset = 0;
    _dataCompleter?.complete();
    _dataCompleter = null;
  }

  void clear() {
    _buffer.clear();
    _readOffset = 0;
  }

  Future<Uint8List> readBytes(int count, Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    while (availableLength < count) {
      await _waitForData(_remaining(timeout, stopwatch));
    }
    return _take(count);
  }

  Future<void> readBytesStreaming(
    int count,
    Duration timeout, {
    required void Function(Uint8List data) onData,
  }) async {
    final stopwatch = Stopwatch()..start();
    var remaining = count;
    while (remaining > 0) {
      if (!hasData) {
        await _waitForData(_remaining(timeout, stopwatch));
      }
      final length = availableLength < remaining ? availableLength : remaining;
      final data = _take(length);
      remaining -= data.length;
      onData(data);
    }
  }

  Future<Uint8List> readUntil(List<int> pattern, Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      final index = _indexOf(pattern);
      if (index >= 0) {
        final end = index + pattern.length;
        return _take(end);
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
          onData(_take(index));
        }
        _advance(pattern.length);
        return;
      }
      final safeLength = availableLength - pattern.length + 1;
      if (safeLength > 0) {
        onData(_take(safeLength));
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
    if (pattern.isEmpty || availableLength < pattern.length) return -1;
    final lastStart = _buffer.length - pattern.length;
    for (int i = _readOffset; i <= lastStart; i++) {
      var matched = true;
      for (int j = 0; j < pattern.length; j++) {
        if (_buffer[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i - _readOffset;
    }
    return -1;
  }

  Uint8List _take(int count) {
    final result = Uint8List.fromList(
      _buffer.sublist(_readOffset, _readOffset + count),
    );
    _advance(count);
    return result;
  }

  void _advance(int count) {
    _readOffset += count;
    _compactIfNeeded();
  }

  void _compactIfNeeded() {
    if (_readOffset == 0) return;
    if (_readOffset == _buffer.length) {
      _buffer.clear();
      _readOffset = 0;
      return;
    }
    if (_readOffset >= 4096 && _readOffset * 2 >= _buffer.length) {
      _buffer.removeRange(0, _readOffset);
      _readOffset = 0;
    }
  }
}
