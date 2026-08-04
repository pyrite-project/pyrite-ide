import 'dart:async';

/// Coalesces `requestRange` / `requestChildren` calls for lazily-loaded data.
///
/// Scrolling must never issue a Python round-trip per frame, so requests are
/// debounced and de-duplicated: a range already requested (or already loaded) is
/// never asked for again, and a burst of scroll frames collapses into one call.
class VisibleRangeTracker {
  VisibleRangeTracker({
    required this.onRequest,
    this.debounce = const Duration(milliseconds: 120),
    this.chunkSize = 100,
  });

  /// Called with a de-duplicated, chunk-aligned range that needs loading.
  final void Function(int start, int count) onRequest;
  final Duration debounce;
  final int chunkSize;

  final Set<int> _requestedChunks = {};
  Timer? _timer;
  int? _pendingStart;
  int? _pendingEnd;

  /// Notes that rows in `[start, end)` are missing and should be fetched.
  ///
  /// Safe to call from a scroll callback: nothing is sent until the debounce
  /// window closes, and chunks already in flight are skipped.
  void noteMissing(int start, int end) {
    if (end <= start) return;
    final firstChunk = start ~/ chunkSize;
    final lastChunk = (end - 1) ~/ chunkSize;

    var rangeStart = -1;
    var rangeEnd = -1;
    for (var chunk = firstChunk; chunk <= lastChunk; chunk++) {
      if (_requestedChunks.contains(chunk)) continue;
      _requestedChunks.add(chunk);
      final chunkStart = chunk * chunkSize;
      if (rangeStart < 0) rangeStart = chunkStart;
      rangeEnd = chunkStart + chunkSize;
    }
    if (rangeStart < 0) return;

    _pendingStart = _pendingStart == null
        ? rangeStart
        : (rangeStart < _pendingStart! ? rangeStart : _pendingStart!);
    _pendingEnd = _pendingEnd == null
        ? rangeEnd
        : (rangeEnd > _pendingEnd! ? rangeEnd : _pendingEnd!);

    _timer?.cancel();
    _timer = Timer(debounce, _flush);
  }

  void _flush() {
    _timer = null;
    final start = _pendingStart;
    final end = _pendingEnd;
    _pendingStart = null;
    _pendingEnd = null;
    if (start == null || end == null) return;
    onRequest(start, end - start);
  }

  /// Forgets in-flight bookkeeping so a resync can re-request everything.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _pendingStart = null;
    _pendingEnd = null;
    _requestedChunks.clear();
  }

  /// Whether the chunk covering [index] has already been requested.
  bool isChunkRequested(int index) =>
      _requestedChunks.contains(index ~/ chunkSize);

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
