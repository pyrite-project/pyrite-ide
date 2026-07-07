import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

class GitDebugLog {
  static const enabled = bool.fromEnvironment('PYRITE_GIT_DEBUG_LOG');
  static const _fileName = 'git_debug.log';
  static const _maxLogBytes = 4 * 1024 * 1024;
  static bool _sessionStarted = false;

  static String get path => p.join(_logDirectoryPath(), _fileName);

  static void startSession() {
    if (!enabled) return;
    if (_sessionStarted) return;
    _sessionStarted = true;
    _rotateIfNeeded();
    log(
      'SESSION START pid=$pid os=${Platform.operatingSystem} '
      'cwd=${Directory.current.path} executable=${Platform.resolvedExecutable}',
    );
    log('logPath=$path');
  }

  static void log(String message, {Object? error, StackTrace? stackTrace}) {
    if (!enabled) return;
    final buffer = StringBuffer()
      ..write(DateTime.now().toIso8601String())
      ..write(' [git] ')
      ..write(message);
    if (error != null) {
      buffer
        ..write('\nERROR: ')
        ..write(error);
    }
    if (stackTrace != null) {
      buffer
        ..write('\nSTACK:\n')
        ..write(stackTrace);
    }

    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '${buffer.toString()}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Logging must never affect Git functionality.
    }
  }

  static Future<T> timeAsync<T>(
    String label,
    FutureOr<T> Function() action, {
    String Function(T value)? result,
  }) async {
    if (!enabled) return await action();
    final stopwatch = Stopwatch()..start();
    log('START $label');
    try {
      final value = await action();
      log(
        'END $label ${stopwatch.elapsedMilliseconds}ms${_result(value, result)}',
      );
      return value;
    } catch (error, stackTrace) {
      log(
        'ERROR $label ${stopwatch.elapsedMilliseconds}ms',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static T timeSync<T>(
    String label,
    T Function() action, {
    String Function(T value)? result,
  }) {
    if (!enabled) return action();
    final stopwatch = Stopwatch()..start();
    log('START $label');
    try {
      final value = action();
      log(
        'END $label ${stopwatch.elapsedMilliseconds}ms${_result(value, result)}',
      );
      return value;
    } catch (error, stackTrace) {
      log(
        'ERROR $label ${stopwatch.elapsedMilliseconds}ms',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static String _result<T>(T value, String Function(T value)? result) {
    if (result == null) return '';
    final text = result(value).trim();
    return text.isEmpty ? '' : ' $text';
  }

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
    try {
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() < _maxLogBytes) return;
      final oldFile = File('$path.old');
      if (oldFile.existsSync()) oldFile.deleteSync();
      file.renameSync(oldFile.path);
    } catch (_) {
      // Best-effort rotation only.
    }
  }
}
