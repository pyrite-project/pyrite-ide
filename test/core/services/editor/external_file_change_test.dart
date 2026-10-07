import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/external_file_change.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1);
  final stampA = FileDiskStamp(modified: t0, size: 10);
  final stampB = FileDiskStamp(
    modified: t0.add(const Duration(seconds: 5)),
    size: 10,
  );
  final stampC = FileDiskStamp(
    modified: t0.add(const Duration(seconds: 5)),
    size: 12,
  );

  group('FileDiskStamp', () {
    test('sameAs needs both mtime and size to match', () {
      expect(stampA.sameAs(FileDiskStamp(modified: t0, size: 10)), isTrue);
      expect(stampA.sameAs(stampB), isFalse);
      expect(stampB.sameAs(stampC), isFalse);
    });

    test('equality and hashCode agree with sameAs', () {
      expect(stampA, FileDiskStamp(modified: t0, size: 10));
      expect(stampA.hashCode, FileDiskStamp(modified: t0, size: 10).hashCode);
    });
  });

  group('planExternalChange', () {
    ExternalChangeAction plan({
      bool exists = true,
      FileDiskStamp? previous,
      FileDiskStamp? current,
      String? diskText = 'disk',
      String? baseline = 'disk',
      bool tabIsDirty = false,
    }) => planExternalChange(
      exists: exists,
      previousStamp: previous,
      currentStamp: current,
      diskText: diskText,
      baseline: baseline,
      tabIsDirty: tabIsDirty,
    );

    test('an unmoved file is none', () {
      expect(
        plan(previous: stampA, current: stampA),
        ExternalChangeAction.none,
      );
    });

    test('a missing file is deleted even when there was never a baseline', () {
      expect(
        plan(
          exists: false,
          previous: stampA,
          current: null,
          diskText: null,
          baseline: null,
        ),
        ExternalChangeAction.deleted,
      );
    });

    test('a changed stamp over identical text is a touch, not a reload', () {
      expect(
        plan(previous: stampA, current: stampC),
        ExternalChangeAction.touchOnly,
      );
    });

    test('identical stamp and text is none, so a resave stays quiet', () {
      expect(
        plan(previous: stampA, current: stampA),
        ExternalChangeAction.none,
      );
    });

    test('an undecodable file never triggers a reload', () {
      expect(
        plan(
          previous: stampA,
          current: stampC,
          diskText: null,
          baseline: 'disk',
        ),
        ExternalChangeAction.touchOnly,
      );
    });

    test('changed text on a clean tab reloads outright', () {
      expect(
        plan(
          previous: stampA,
          current: stampC,
          diskText: 'new',
          tabIsDirty: false,
        ),
        ExternalChangeAction.reload,
      );
    });

    test('changed text under unsaved edits prompts', () {
      expect(
        plan(
          previous: stampA,
          current: stampC,
          diskText: 'new',
          tabIsDirty: true,
        ),
        ExternalChangeAction.prompt,
      );
    });

    test(
      'a brand new tab with no baseline reloads when the file has content',
      () {
        expect(
          plan(previous: null, current: stampC, baseline: null),
          ExternalChangeAction.reload,
        );
      },
    );

    test('a brand new empty file is not treated as changed', () {
      expect(
        plan(previous: null, current: null, diskText: '', baseline: null),
        ExternalChangeAction.none,
      );
    });
  });

  group('against the real filesystem', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('pyrite_ext_change_');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('statFileStamp is null for a path that does not exist', () async {
      expect(await statFileStamp(File('${dir.path}/nope.py')), isNull);
    });

    test('statFileStamp tracks content changes', () async {
      final file = File('${dir.path}/a.py')..writeAsStringSync('x = 1\n');
      final before = await statFileStamp(file);
      expect(before, isNotNull);
      expect(before!.size, 6);
      // Rewrite with different content and a clearly newer stamp, since some
      // filesystems only tick mtime at second granularity.
      await file.writeAsString('x = 1\ny = 2\n', flush: true);
      final after = await statFileStamp(file);
      expect(after!.size, 12);
      expect(after.sameAs(before), isFalse);
    });

    test('readDiskText returns null for a binary file', () async {
      final file = File('${dir.path}/b.bin')
        ..writeAsBytesSync([0x00, 0x01, 0x02, 0xff, 0xfe, 0xfd]);
      expect(await readDiskText(file), isNull);
    });

    test('readDiskText round-trips text content', () async {
      final file = File('${dir.path}/c.py')..writeAsStringSync('x = 1\n');
      expect(await readDiskText(file), 'x = 1\n');
    });

    test('readDiskText is null once the file is gone', () async {
      final file = File('${dir.path}/d.py')..writeAsStringSync('x = 1\n');
      await file.delete();
      expect(await readDiskText(file), isNull);
    });
  });
}
