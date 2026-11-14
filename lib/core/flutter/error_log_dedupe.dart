import 'dart:async';

/// Folds repeated identical error reports into a single summary line.
///
/// Flutter can report the very same error on every frame; a failing assertion
/// in the semantics tree does exactly that, twice per frame. Logging each
/// occurrence with its full stack hides everything else in the output panel and
/// costs a file write per frame when the Git debug log is enabled. The first
/// occurrence of a run is still logged verbatim; the rest only bump a counter,
/// and the counter is reported as one line once the error has been quiet for
/// [quiet] (or when [flush] is called). A run that starts again after that line
/// has been written is summarized with a fresh count instead of reprinting the
/// stack, so a persistent per-frame error produces one full report followed by
/// occasional tallies.
///
/// Reports are matched by [ErrorLogDedupe.admit]'s `signature`, which should be
/// the exception text rather than the stack trace: stacks of repeated framework
/// errors are identical anyway, and the text is what a reader recognises.
class ErrorLogDedupe {
  ErrorLogDedupe({
    required this.emitSummary,
    this.quiet = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Receives one line per settled run, usually right after the flood stops.
  final void Function(String text) emitSummary;

  /// How long an error has to stay away before its run is tallied up.
  final Duration quiet;

  final DateTime Function() _clock;

  /// Beyond this many distinct messages the oldest idle one is dropped.
  /// Real sessions stay in the single digits; the cap only guards against a
  /// plugin that reports a unique message per frame.
  static const int maxRuns = 128;
  static const int _maxLabelLength = 200;

  final Map<String, _ErrorRun> _runs = {};
  Timer? _flushTimer;

  /// Returns `true` when this occurrence is the first of its run and deserves a
  /// full log entry, `false` when it is a repeat that has been folded into a
  /// pending tally.
  bool admit({required String signature}) {
    final now = _clock();
    final run = _runs[signature];
    if (run == null) {
      if (_runs.length >= maxRuns) _evictOne();
      _runs[signature] = _ErrorRun(label: _shorten(signature), lastSeen: now);
      return true;
    }
    run
      ..lastSeen = now
      ..repeats += 1;
    _scheduleFlush();
    return false;
  }

  /// Writes every pending tally immediately, without waiting for [quiet].
  void flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    for (final run in _runs.values) {
      final repeats = run.repeats;
      if (repeats == 0) continue;
      run.repeats = 0;
      try {
        emitSummary(
          '[dedupe] repeated $repeats time(s), stack omitted: ${run.label}',
        );
      } catch (_) {
        // A broken sink must not turn de-duplication into a second flood.
      }
    }
  }

  /// Forgets every run. Pending tallies are dropped.
  void reset() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _runs.clear();
  }

  void dispose() => reset();

  void _scheduleFlush() {
    // One timer is enough: it re-arms itself while reports keep arriving, so a
    // steady per-frame error never resets a timer on every frame.
    _flushTimer ??= Timer(quiet, _flushWhenSettled);
  }

  void _flushWhenSettled() {
    _flushTimer = null;
    final now = _clock();
    final stillRepeating = _runs.values.any(
      (run) => run.repeats > 0 && now.difference(run.lastSeen) < quiet,
    );
    if (stillRepeating) {
      _flushTimer = Timer(quiet, _flushWhenSettled);
      return;
    }
    flush();
  }

  void _evictOne() {
    final entries = _runs.entries.toList()
      ..sort((a, b) => a.value.lastSeen.compareTo(b.value.lastSeen));
    final victim = entries.firstWhere(
      (entry) => entry.value.repeats == 0,
      orElse: () => entries.first,
    );
    _runs.remove(victim.key);
  }

  String _shorten(String signature) {
    final single = signature.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (single.length <= _maxLabelLength) return single;
    return '${single.substring(0, _maxLabelLength - 3)}...';
  }
}

class _ErrorRun {
  _ErrorRun({required this.label, required this.lastSeen});

  final String label;
  DateTime lastSeen;
  int repeats = 0;
}
