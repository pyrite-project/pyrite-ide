import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/device/board_sync_plan.dart';
import 'package:pyrite_ide/core/services/device/board_sync_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pyrite_sync_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> writeFile(String relative, String content) async {
    final file = File(path.join(tempDir.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  group('scanLocalWorkspace', () {
    test('collects files with size and mtime', () async {
      await writeFile('main.py', 'print(1)');
      await writeFile('lib/util.py', 'x = 1');

      final snapshot = await scanLocalWorkspace(tempDir.path);

      expect(snapshot.files.keys, containsAll(['main.py', 'lib/util.py']));
      expect(snapshot.files['main.py']!.size, 'print(1)'.length);
      expect(snapshot.files['main.py']!.modified, isNotNull);
      expect(snapshot.directories, contains('lib'));
    });

    test('skips VCS and build noise', () async {
      await writeFile('main.py', 'x');
      await writeFile('.git/config', 'nope');
      await writeFile('build/out.bin', 'nope');
      await writeFile('__pycache__/m.pyc', 'nope');

      final snapshot = await scanLocalWorkspace(tempDir.path);

      expect(snapshot.files.keys, ['main.py']);
    });

    test(
      'missing root returns an empty snapshot instead of throwing',
      () async {
        final snapshot = await scanLocalWorkspace(
          path.join(tempDir.path, 'does-not-exist'),
        );

        expect(snapshot.isEmpty, isTrue);
      },
    );

    test('honours a custom ignore set', () async {
      await writeFile('main.py', 'x');
      await writeFile('secrets/key.txt', 'nope');

      final snapshot = await scanLocalWorkspace(
        tempDir.path,
        ignoredDirectories: const {'secrets'},
      );

      expect(snapshot.files.keys, ['main.py']);
    });
  });

  group('scanLocalWorkspace + buildSyncPlan end to end', () {
    test('local-only files become uploads against an empty board', () async {
      await writeFile('main.py', 'print(1)');
      await writeFile('lib/a.py', 'a');

      final local = await scanLocalWorkspace(tempDir.path);
      final plan = buildSyncPlan(
        local: local,
        board: const SyncTreeSnapshot(
          files: <String, SyncFileInfo>{},
          directories: <String>{},
          root: '/',
        ),
      );

      expect(plan.uploadCount, 2);
      expect(plan.downloadCount, 0);
      expect(plan.requiredBoardDirectories, contains('lib'));
    });

    test('identical board snapshot yields no work', () async {
      await writeFile('main.py', 'print(1)');
      final local = await scanLocalWorkspace(tempDir.path);

      final boardFiles = {
        for (final entry in local.files.entries)
          entry.key: SyncFileInfo(
            relativePath: entry.key,
            size: entry.value.size,
            modified: entry.value.modified,
          ),
      };
      final plan = buildSyncPlan(
        local: local,
        board: SyncTreeSnapshot(
          files: boardFiles,
          directories: const {},
          root: '/',
        ),
      );

      expect(plan.hasWork, isFalse);
      expect(plan.unchangedCount, 1);
    });
  });
}
