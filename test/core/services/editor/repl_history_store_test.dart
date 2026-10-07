import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/repl_history_store.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pyrite_repl_history_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ReplHistoryStore store() => ReplHistoryStore(directory: dir.path);

  group('save and load', () {
    test('round-trips a history', () async {
      final history = store();
      await history.save('COM3', ['import webrepl', 'help()']);
      expect(await history.load('COM3'), ['import webrepl', 'help()']);
    });

    test('load returns empty for a bucket that was never saved', () async {
      expect(await store().load('COM7'), isEmpty);
    });

    test('an empty bucket name never touches the disk', () async {
      final history = store();
      await history.save('', ['nope']);
      expect(await history.load(''), isEmpty);
      expect(
        await dir.list().where((e) => e.path.contains('repl_history')).isEmpty,
        isTrue,
      );
    });

    test('replaces rather than appends', () async {
      final history = store();
      await history.save('COM3', ['a', 'b']);
      await history.save('COM3', ['c']);
      expect(await history.load('COM3'), ['c']);
    });
  });

  group('per-device bucketing', () {
    test('two devices keep separate histories', () async {
      final history = store();
      await history.save('COM3', ['board_a']);
      await history.save('COM7', ['board_b']);
      expect(await history.load('COM3'), ['board_a']);
      expect(await history.load('COM7'), ['board_b']);
    });

    test('a WebREPL host is bucketed apart from a serial port', () async {
      final history = store();
      await history.save('COM3', ['serial_cmd']);
      await history.save('WebREPL 192.168.1.5:8266', ['webrepl_cmd']);
      expect(await history.load('COM3'), ['serial_cmd']);
      expect(await history.load('WebREPL 192.168.1.5:8266'), ['webrepl_cmd']);
    });

    test('a sanitised-name collision yields an empty history', () async {
      final history = store();
      await history.save('COM/3', ['from_slash']);
      // Written under the same sanitised name by a different label.
      await File('${dir.path}/repl_history_COM_3.json').writeAsString(
        jsonEncode({
          'bucket': 'COM:3',
          'entries': ['from_colon'],
        }),
      );
      expect(await history.load('COM/3'), isEmpty);
    });
  });

  group('limits', () {
    test('trims to the newest entries on save', () async {
      final history = store();
      final many = [
        for (var i = 0; i < ReplHistoryStore.maxEntriesPerBucket + 20; i++)
          'cmd$i',
      ];
      await history.save('COM3', many);
      final loaded = await history.load('COM3');
      expect(loaded, hasLength(ReplHistoryStore.maxEntriesPerBucket));
      // The tail survives: a user who paged back far enough wants the old
      // command, not the one they typed five hundred entries ago.
      expect(loaded.last, 'cmd${many.length - 1}');
    });

    test('prunes old buckets past the cap but keeps the active one', () async {
      final history = store();
      // Write more buckets than the cap, with distinct modification times.
      for (var i = 0; i < ReplHistoryStore.maxBuckets + 6; i++) {
        await history.save('COM$i', ['cmd']);
        // Space the mtimes so pruning order is deterministic on filesystems
        // with coarse timestamps.
        final file = File('${dir.path}/repl_history_COM$i.json');
        file.setLastModifiedSync(DateTime.now().add(Duration(seconds: i)));
      }
      final store2 = store();
      // A save triggers pruning; the bucket it saves to is never pruned.
      await store2.save('current', ['keep_me']);

      final remaining = await dir
          .list()
          .where((e) => e.path.contains('repl_history'))
          .length;
      expect(remaining, lessThanOrEqualTo(ReplHistoryStore.maxBuckets));
      expect(await store2.load('current'), ['keep_me']);
      // The oldest bucket went first, not an arbitrary one.
      expect(await store2.load('COM0'), isEmpty);
    });
  });

  group('corrupt files', () {
    test('a non-JSON file yields an empty history', () async {
      await File('${dir.path}/repl_history_COM3.json').writeAsString('{oops');
      expect(await store().load('COM3'), isEmpty);
    });

    test('a JSON file of the wrong shape yields an empty history', () async {
      await File(
        '${dir.path}/repl_history_COM3.json',
      ).writeAsString('[1, 2, 3]');
      expect(await store().load('COM3'), isEmpty);
    });

    test('non-string entries are dropped', () async {
      await File('${dir.path}/repl_history_COM3.json').writeAsString(
        jsonEncode({
          'bucket': 'COM3',
          'entries': ['good', 42, null, 'also_good'],
        }),
      );
      expect(await store().load('COM3'), ['good', 'also_good']);
    });

    test('a file missing the bucket key is dropped', () async {
      await File('${dir.path}/repl_history_COM3.json').writeAsString(
        jsonEncode({
          'entries': ['legacy'],
        }),
      );
      // No `bucket` key means the collision guard cannot be satisfied; the
      // history is dropped rather than risk showing the wrong device's
      // commands.
      expect(await store().load('COM3'), isEmpty);
    });
  });
}
