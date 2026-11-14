import 'dart:async';

/// Coalesces `requestRange` / `requestChildren` calls for lazily-loaded data.
///
/// Scrolling must never issue a Python round-trip per frame, so requests are
/// debounced and de-duplicated: a range requested within [retryAfter] is not
/// asked for again, and a burst of scroll frames collapses into one call.
/// Unanswered requests are retried, and [reset] forgets a replaced window.
class VisibleRangeTracker {
  VisibleRangeTracker({
    required this.onRequest,
    this.debounce = const Duration(milliseconds: 120),
    this.chunkSize = 100,
    this.retryAfter = const Duration(seconds: 2),
  });

  /// Called with a de-duplicated, chunk-aligned range that needs loading.
  final void Function(int start, int count) onRequest;
  final Duration debounce;
  final int chunkSize;

  /// How long a request may stay unanswered before its chunks count as failed.
  ///
  /// `requestRange` is fire-and-forget, so a stopped transport or a plugin-side
  /// error reports nothing back. Expiring the mark lets a later rebuild ask
  /// again instead of leaving those rows as placeholders forever.
  final Duration retryAfter;

  final Map<int, DateTime> _requestedChunks = {};
  Timer? _timer;
  int? _pendingStart;
  int? _pendingEnd;

  /// Notes that rows in `[start, end)` are missing and should be fetched.
  ///
  /// Safe to call from a scroll callback: nothing is sent until the debounce
  /// window closes, and chunks requested less than [retryAfter] ago are
  /// skipped.
  void noteMissing(int start, int end) {
    if (end <= start) return;
    final now = DateTime.now();
    final firstChunk = start ~/ chunkSize;
    final lastChunk = (end - 1) ~/ chunkSize;

    var rangeStart = -1;
    var rangeEnd = -1;
    for (var chunk = firstChunk; chunk <= lastChunk; chunk++) {
      final requestedAt = _requestedChunks[chunk];
      if (requestedAt != null && now.difference(requestedAt) < retryAfter) {
        continue;
      }
      // A stale mark means the earlier request was never answered, so the
      // chunk is treated as new and requested again.
      _requestedChunks[chunk] = now;
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

  /// Forgets which chunks the previous data window requested.
  ///
  /// Call when a new plugin snapshot may have replaced the window: requests
  /// made against the old window are not guaranteed to arrive, so rows still
  /// missing after the replacement must be asked for again. A request that is
  /// already debounced is kept, otherwise a steady stream of snapshots could
  /// starve it before it ever fires.
  void reset() {
    _requestedChunks.clear();
  }

  /// Whether the chunk covering [index] has already been requested.
  bool isChunkRequested(int index) =>
      _requestedChunks.containsKey(index ~/ chunkSize);

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
