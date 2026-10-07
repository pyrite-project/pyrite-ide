import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// On-disk store for the REPL's input history.
///
/// The history used to live only in a `List<String>` inside
/// `ReplInputController`, which meant it died with the process: closing the
/// IDE mid-debug-session threw away the command that took twenty minutes to
/// get right. This keeps it on disk instead.
///
/// History is bucketed per device rather than kept in one global list. The REPL
/// talks to a specific board, and the command that is obvious on one (a bare
/// `import webrepl`, say) is wrong on another; a shared list interleaved them
/// and Up-arrow offered commands that had never worked on the board currently
/// attached.
///
/// Deliberately not part of `PersistenceManager`: that path restores a
/// documented snapshot on launch, while history is an append-only convenience
/// that must survive a crash mid-write. A torn file costs the user their
/// scrollback; a bad snapshot costs them their workspace.
class ReplHistoryStore {
  ReplHistoryStore({this.directory});

  /// Directory holding the history files. Defaults to the app support
  /// directory, overridable in tests.
  final String? directory;

  /// Per-bucket cap, matching what the in-memory list used to enforce.
  static const int maxEntriesPerBucket = 500;

  /// How many buckets to keep. Beyond this the least recently used bucket is
  /// dropped, so a machine that has had dozens of boards attached does not
  /// accumulate history files forever.
  static const int maxBuckets = 32;

  String get _dir => directory ?? defaultHistoryDirectory();

  /// Where history lives for the current platform.
  ///
  /// Uses the same support directory as the rest of the app's user data rather
  /// than the current directory, which for a desktop app is wherever the user
  /// happened to launch it from and may not be writable.
  static String defaultHistoryDirectory() {
    final support = Platform.environment['APPDATA'];
    if (Platform.isWindows && support != null && support.isNotEmpty) {
      return path.join(support, 'PyriteIDE');
    }
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return path.join(home, '.pyrite_ide');
  }

  File _fileFor(String bucket) =>
      File(path.join(_dir, 'repl_history_${_sanitize(bucket)}.json'));

  /// Keeps a bucket name usable as a file name.
  ///
  /// Device labels come from a serial port list and a WebREPL host, so they can
  /// contain characters a path cannot (`COM3`, `192.168.1.5:8266`). Rather than
  /// reject them, everything outside `[A-Za-z0-9._-]` becomes `_`.
  ///
  /// The original label is kept in the file and checked on load, so two labels
  /// that sanitize to the same name cannot read each other's history.
  static String _sanitize(String bucket) =>
      bucket.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Loads the history for [bucket], oldest first.
  ///
  /// Never throws: a corrupt or unreadable file yields an empty history rather
  /// than taking the REPL down with it, since the history is a convenience and
  /// the console is the thing the user actually needs.
  Future<List<String>> load(String bucket) async {
    if (bucket.isEmpty) return const [];
    try {
      final file = _fileFor(bucket);
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const [];
      // The stored label is compared so a sanitised-name collision resolves to
      // an empty history rather than to another device's commands.
      if (decoded['bucket'] != bucket) return const [];
      final entries = decoded['entries'];
      if (entries is! List) return const [];
      return entries
          .whereType<String>()
          .take(maxEntriesPerBucket)
          .toList(growable: false);
    } catch (error) {
      debugPrint('[repl_history] ignoring unreadable history: $error');
      return const [];
    }
  }

  /// Replaces the history for [bucket] with [entries].
  ///
  /// Trims to [maxEntriesPerBucket] from the front, so the most recent commands
  /// are the ones that survive.
  Future<void> save(String bucket, List<String> entries) async {
    if (bucket.isEmpty) return;
    try {
      final trimmed = entries.length > maxEntriesPerBucket
          ? entries.sublist(entries.length - maxEntriesPerBucket)
          : entries;
      final file = _fileFor(bucket);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'bucket': bucket, 'entries': trimmed}),
        flush: true,
      );
      await _pruneOldBuckets(keep: bucket);
    } catch (error) {
      // Losing history is not worth surfacing an error for; the console keeps
      // working either way.
      debugPrint('[repl_history] could not save history: $error');
    }
  }

  /// Deletes the oldest history files until at most [maxBuckets] remain.
  ///
  /// [keep] is never pruned even if it is the oldest, so the device currently
  /// in use cannot have its history swept away by this call.
  Future<void> _pruneOldBuckets({required String keep}) async {
    final dir = Directory(_dir);
    if (!await dir.exists()) return;
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (!path.basename(entity.path).startsWith('repl_history_')) continue;
      if (!entity.path.endsWith('.json')) continue;
      if (entity.path == _fileFor(keep).path) continue;
      files.add(entity);
    }
    if (files.length < maxBuckets) return;
    final stat = <File, FileStat>{};
    for (final file in files) {
      final info = await file.stat();
      stat[file] = info;
    }
    final sorted = stat.keys.toList()
      ..sort((a, b) => stat[a]!.modified.compareTo(stat[b]!.modified));
    for (final file in sorted.take(files.length - maxBuckets + 1)) {
      try {
        await file.delete();
      } catch (_) {
        // A file we cannot delete is a reason to stop pruning, not to fail.
        break;
      }
    }
  }
}
