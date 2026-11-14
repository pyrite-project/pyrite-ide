import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Severity of a log record written through [AppLog].
enum AppLogLevel { debug, info, warn, error }

/// Area-tagged IDE logging with the cost of a log line in mind.
///
/// A log line is not free: it is written to the console, mirrored into the
/// output panel (which copies its entry list and repaints a terminal) and it
/// competes with the work being logged. A transfer path that logs once per
/// chunk therefore spends more on diagnostics than on the transfer itself,
/// while telling the reader nothing they cannot get from one summary line.
///
/// This class encodes the distinction:
///  * [d] — per-transaction, per-chunk detail. Only emitted for debug and
///    profile builds, so a release build does not pay for it.
///  * [i] — an operation boundary a user or a bug report cares about
///    (connected a port, wrote a file, started a plugin).
///  * [w] / [e] — a failure that changed behaviour. Always emitted and also
///    appended to a rotating file, because these are the lines a user is
///    asked to send back when something goes wrong.
///  * [progress] and [atMostEvery] — collapse a hot loop into at most one line
///    per 10% step or per time window.
///
/// Output keeps the `[area] message` shape the rest of the codebase already
/// uses, so existing logs stay greppable.
///
/// A problem record is only worth writing if it can be understood without the
/// console, so every warning and error file record is self-contained:
///
///  * [session] opens each run with a banner (build mode, OS, boot counts), so
///    a file dropped on disk is attributable even when the run logged no error.
///  * Each record carries the last [_breadcrumbLimit] lines emitted before it,
///    which is what turns a lone exception into "connected COM4 → plugin
///    started → 1.4MB view.patch rejected → error".
///  * An error flushes immediately (rate limited), because the process may be
///    gone before the usual two-second debounce fires.
class AppLog {
  AppLog._();

  /// Verbose logging in release builds, for a field diagnosis build:
  /// `flutter build windows --dart-define=PYRITE_VERBOSE_LOG=true`.
  static const bool _verbose = bool.fromEnvironment('PYRITE_VERBOSE_LOG');

  /// Opt out of the log file, for a run that must not touch the disk.
  static const bool _noFile = bool.fromEnvironment('PYRITE_LOG_NO_FILE');

  static const String _fileName = 'app.log';
  static const int _maxFileBytes = 2 * 1024 * 1024;
  static const int _maxMessageChars = 8000;
  static const int _flushThreshold = 32;

  /// How much history a problem record carries. Long enough to cover a
  /// connect/handshake/transfer sequence, short enough that one error does
  /// not append a screenful of noise.
  static const int _breadcrumbLimit = 40;

  /// True when [d] records are worth producing at all.
  static bool get debugEnabled => _verbose || kDebugMode || kProfileMode;

  /// Dumps whole SDK envelopes instead of one-line summaries:
  /// `flutter run --dart-define=PYRITE_SDK_TRACE=true`.
  ///
  /// Off by default even in debug builds: a single `sdk.view.patch` may carry
  /// two megabytes of JSON, so printing frames verbatim buries the plugin's
  /// own output under escaped JSON.
  static const bool tracePayloads = bool.fromEnvironment('PYRITE_SDK_TRACE');

  /// A frame dump is useful but unbounded, so it is still clipped.
  static const int _maxTraceChars = 4096;

  /// Clips a wire frame for a dump, reporting how much was dropped so a
  /// truncated read is never mistaken for a complete one.
  static String clipTrace(String text) {
    if (text.length <= _maxTraceChars) return text;
    return '${text.substring(0, _maxTraceChars)}… '
        '(${text.length - _maxTraceChars} chars clipped)';
  }

  static final List<String> _pending = [];
  static final Map<String, int> _lastEmitMs = {};
  static final Map<String, int> _lastProgressStep = {};
  static final List<String> _breadcrumbs = [];
  static Timer? _flushTimer;
  static bool _rotated = false;
  static bool _sessionOpened = false;

  /// Per-operation detail; compiled out of release builds.
  static void d(String area, String message, {Object? error}) {
    if (!debugEnabled) return;
    _emit(AppLogLevel.debug, area, message, error: error);
  }

  /// Operation boundary: something started, finished, or was decided.
  static void i(String area, String message, {Object? error}) {
    _emit(AppLogLevel.info, area, message, error: error);
  }

  /// A recoverable problem: the operation continued, but not as asked.
  static void w(String area, String message, {Object? error}) {
    _emit(AppLogLevel.warn, area, message, error: error);
  }

  /// A failure that is being reported or that stopped an operation.
  ///
  /// When the throw site is unavailable (a caught error whose stack was not
  /// kept) the logging call site is recorded instead, which is still what
  /// tells a reader *which* operation gave up.
  static void e(
    String area,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    _emit(
      AppLogLevel.error,
      area,
      message,
      error: error,
      stack: stack ?? StackTrace.current,
    );
  }

  /// Logs [done] of [total] at most once per 10% step, so a chunk loop yields
  /// roughly ten lines instead of one per chunk. Returns true when a line was
  /// emitted.
  static bool progress(String area, String key, int done, int total) {
    if (total <= 0) return false;
    final clamped = done.clamp(0, total).toInt();
    final step = clamped >= total ? 10 : clamped * 10 ~/ total;
    final last = _lastProgressStep[key] ?? -1;
    if (step <= last) return false;
    _lastProgressStep[key] = step;
    if (clamped >= total) _lastProgressStep.remove(key);
    _emit(AppLogLevel.debug, area, '$key ${step * 10}% ($clamped/${total}B)');
    return true;
  }

  /// Returns true at most once per [window] for [key]; use it to keep a
  /// repeating event (a retry, a poll, a repeated warning) at a readable rate.
  static bool atMostEvery(String key, Duration window) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastEmitMs[key];
    if (last != null && now - last < window.inMilliseconds) return false;
    _lastEmitMs[key] = now;
    return true;
  }

  /// Drops the throttle state, so a test can assert on every line.
  @visibleForTesting
  static void resetThrottles() {
    _lastEmitMs.clear();
    _lastProgressStep.clear();
    _breadcrumbs.clear();
    _sessionOpened = false;
  }

  /// History a problem record would carry right now, oldest first.
  @visibleForTesting
  static List<String> get debugBreadcrumbs => List.unmodifiable(_breadcrumbs);

  /// Opens the log file for this run, before anything has gone wrong.
  ///
  /// Without it the file only appears at the first warning, which means a
  /// launch that never fails leaves no trace of what was even attempted.
  /// [fields] are rendered as `key=value` on one line; `null` values are
  /// skipped so a caller can pass "not known yet" without printing `null`.
  static void session(String area, Map<String, Object?> fields) {
    if (_noFile || _isTestEnvironment || _sessionOpened) return;
    _sessionOpened = true;
    final details = fields.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    final line = 'session start $details';
    // Still visible on the console: the banner doubles as the "how long did
    // this launch take" line a developer reads while the app is starting.
    debugPrint('[$area] $line');
    _remember(AppLogLevel.info, area, line);
    // A blank line keeps consecutive runs apart when the file is appended to.
    _pending
      ..add('')
      ..add(formatRecord(AppLogLevel.info, area, line));
    _flush();
  }

  /// Writes everything buffered to the file.
  ///
  /// Call before the process goes away: shutdown does not run the debounce
  /// timer, and the last problem before an exit is exactly the one a report
  /// needs.
  static void flushSync() => _flush();

  /// Formats a byte count for a transfer summary, e.g. `1.4MB`.
  static String humanBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  /// Throughput for a transfer summary, in bytes per second.
  static String throughput(int bytes, int elapsedMs) {
    if (elapsedMs <= 0) return 'n/a';
    return '${((bytes * 1000) / elapsedMs).toStringAsFixed(0)}B/s';
  }

  static void _emit(
    AppLogLevel level,
    String area,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    final text = _truncate(message);
    final suffix = error == null ? '' : ' error=$error';
    final line = '[$area] $text$suffix';

    debugPrint(line);
    if (level == AppLogLevel.warn || level == AppLogLevel.error) {
      _enqueue(level, area, text, error: error, stack: stack);
    }
    // Recorded after the write, so a problem record carries what led to it
    // rather than repeating itself as its own last breadcrumb.
    _remember(level, area, text);
  }

  static void _remember(AppLogLevel level, String area, String message) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    _breadcrumbs.add('$stamp ${_levelTag(level)} [$area] $message');
    if (_breadcrumbs.length > _breadcrumbLimit) {
      _breadcrumbs.removeRange(0, _breadcrumbs.length - _breadcrumbLimit);
    }
  }

  static String _levelTag(AppLogLevel level) => switch (level) {
    AppLogLevel.debug => 'D',
    AppLogLevel.info => 'I',
    AppLogLevel.warn => 'W',
    AppLogLevel.error => 'E',
  };

  static String _truncate(String message) {
    if (message.length <= _maxMessageChars) return message;
    return '${message.substring(0, _maxMessageChars)}'
        '… (${message.length - _maxMessageChars} chars truncated)';
  }

  // -- File sink ------------------------------------------------------------
  //
  // Only warnings and errors reach the file: they are rare, they are what a
  // bug report needs, and keeping them on disk is the only way a release
  // build remains diagnosable after the console is gone.

  static void _enqueue(
    AppLogLevel level,
    String area,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    if (_noFile || _isTestEnvironment) return;
    _pending.add(
      formatRecord(
        level,
        area,
        message,
        error: error,
        stack: stack,
        breadcrumbs: _breadcrumbs,
      ),
    );
    // An error is written straight away: the process may not survive long
    // enough for the debounce timer. Rate limited so a failing loop still
    // cannot turn into a disk write per frame.
    if (level == AppLogLevel.error &&
        atMostEvery('flush:error', const Duration(seconds: 1))) {
      _flush();
      return;
    }
    if (_pending.length >= _flushThreshold) {
      _flush();
      return;
    }
    _flushTimer ??= Timer(const Duration(seconds: 2), _flush);
  }

  /// Renders one file record.
  ///
  /// Kept separate from the sink so the shape a bug report depends on can be
  /// asserted in a unit test — the file itself is not written under
  /// `flutter test`, which would otherwise leave this unverifiable.
  @visibleForTesting
  static String formatRecord(
    AppLogLevel level,
    String area,
    String message, {
    Object? error,
    StackTrace? stack,
    List<String> breadcrumbs = const [],
  }) {
    final buffer = StringBuffer()
      ..write(DateTime.now().toIso8601String())
      ..write(' [')
      ..write(level.name.toUpperCase())
      ..write('] [')
      ..write(area)
      ..write('] ')
      ..write(message);
    if (breadcrumbs.isNotEmpty) {
      buffer.write('\n  --- last ${breadcrumbs.length} events ---');
      for (final line in breadcrumbs) {
        buffer.write('\n  $line');
      }
    }
    if (error != null) buffer.write('\n  error: $error');
    if (stack != null) {
      buffer.write('\n  stack:\n  ${stack.toString().trimRight()}');
    }
    return buffer.toString();
  }

  static bool get _isTestEnvironment =>
      Platform.environment.containsKey('FLUTTER_TEST');

  static void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final lines = _pending.join('\n');
    _pending.clear();
    try {
      _rotateIfNeeded();
      final file = File(_logPath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$lines\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Logging must never affect IDE behaviour.
    }
  }

  static String get _logPath => p.join(_logDirectoryPath(), _fileName);

  static String _logDirectoryPath() {
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return p.join(localAppData, 'PyriteIDE', 'logs');
      }
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, '.pyrite_ide', 'logs');
    }
    return p.join(Directory.systemTemp.path, 'pyrite_ide_logs');
  }

  static void _rotateIfNeeded() {
    if (_rotated) return;
    _rotated = true;
    try {
      final file = File(_logPath);
      if (!file.existsSync() || file.lengthSync() < _maxFileBytes) return;
      final old = File('$_logPath.old');
      if (old.existsSync()) old.deleteSync();
      file.renameSync(old.path);
    } catch (_) {
      // Best-effort rotation only.
    }
  }
}
