import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/device/board_sync_plan.dart';
import 'package:pyrite_ide/core/services/device/sync_ignore.dart';

SyncFileInfo _local(String path, int size, DateTime? modified) =>
    SyncFileInfo(relativePath: path, size: size, modified: modified);

SyncFileInfo _board(String path, int size, DateTime? modified) =>
    SyncFileInfo(relativePath: path, size: size, modified: modified);

SyncTreeSnapshot _snapshot(
  Map<String, SyncFileInfo> files, {
  Set<String> directories = const {},
  String root = '/root',
}) => SyncTreeSnapshot(files: files, directories: directories, root: root);

DateTime _at(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

void main() {
  group('buildSyncEntry: single side', () {
    test('local only is a new upload', () {
      final entry = buildSyncEntry(
        relativePath: 'main.py',
        local: _local('main.py', 42, _at(1000)),
        board: null,
      );

      expect(entry.action, BoardSyncAction.uploadNew);
      expect(entry.direction, BoardSyncDirection.localToBoard);
      expect(entry.transferBytes, 42);
    });

    test('board only is a new download', () {
      final entry = buildSyncEntry(
        relativePath: 'boot.py',
        local: null,
        board: _board('boot.py', 7, _at(1000)),
      );

      expect(entry.action, BoardSyncAction.downloadNew);
      expect(entry.direction, BoardSyncDirection.boardToLocal);
      expect(entry.transferBytes, 7);
    });

    test('neither side is unchanged and not selectable', () {
      final entry = buildSyncEntry(
        relativePath: 'gone.py',
        local: null,
        board: null,
      );

      expect(entry.action, BoardSyncAction.unchanged);
      expect(entry.selectable, isFalse);
    });
  });

  group('buildSyncEntry: both sides', () {
    test('same size and same mtime is unchanged', () {
      final entry = buildSyncEntry(
        relativePath: 'a.py',
        local: _local('a.py', 100, _at(2000)),
        board: _board('a.py', 100, _at(2000)),
      );

      expect(entry.action, BoardSyncAction.unchanged);
      expect(entry.selectable, isFalse);
    });

    test('mtime inside the tolerance is unchanged (FAT resolution)', () {
      final entry = buildSyncEntry(
        relativePath: 'a.py',
        local: _local('a.py', 100, _at(2000)),
        board: _board(
          'a.py',
          100,
          _at(2000).add(const Duration(milliseconds: 900)),
        ),
      );

      expect(entry.action, BoardSyncAction.unchanged);
    });

    test('larger and newer local file is an upload', () {
      final entry = buildSyncEntry(
        relativePath: 'a.py',
        local: _local('a.py', 200, _at(3000)),
        board: _board('a.py', 100, _at(2000)),
      );

      expect(entry.action, BoardSyncAction.uploadChanged);
      expect(entry.direction, BoardSyncDirection.localToBoard);
      expect(entry.note, contains('本地'));
    });

    test('larger and newer board file is a download', () {
      final entry = buildSyncEntry(
        relativePath: 'a.py',
        local: _local('a.py', 100, _at(2000)),
        board: _board('a.py', 300, _at(3000)),
      );

      expect(entry.action, BoardSyncAction.downloadChanged);
      expect(entry.direction, BoardSyncDirection.boardToLocal);
    });

    test('no mtime on the board falls back to upload with a note', () {
      final entry = buildSyncEntry(
        relativePath: 'a.py',
        local: _local('a.py', 200, _at(3000)),
        board: _board('a.py', 100, null),
      );

      expect(entry.action, BoardSyncAction.uploadChanged);
      expect(entry.note, contains('修改时间'));
    });

    test('zero mtime counts as "no timestamp"', () {
      final entry = buildSyncEntry(
        relativePath: 'a.py',
        local: _local('a.py', 200, _at(3000)),
        board: _board('a.py', 100, _at(0)),
      );

      expect(entry.action, BoardSyncAction.uploadChanged);
      expect(entry.note, contains('修改时间'));
    });

    test('sizeOnly policy ignores mtime', () {
      final entry = buildSyncEntry(
        relativePath: 'a.py',
        local: _local('a.py', 100, _at(9000)),
        board: _board('a.py', 100, _at(1000)),
        policy: SyncTimestampPolicy.sizeOnly,
      );

      expect(entry.action, BoardSyncAction.unchanged);
    });
  });

  group('buildSyncEntry: conflict detection', () {
    test('identical mtime with different size is a conflict', () {
      final entry = buildSyncEntry(
        relativePath: 'a.py',
        local: _local('a.py', 200, _at(2000)),
        board: _board('a.py', 100, _at(2000)),
      );

      expect(entry.action, BoardSyncAction.conflict);
      expect(entry.direction, BoardSyncDirection.none);
      expect(entry.note, contains('需要选择'));
    });

    test('baseline: only local changed -> upload', () {
      final entry = buildSyncEntry(
        relativePath: 'a.py',
        local: _local('a.py', 200, _at(3000)),
        board: _board('a.py', 100, _at(2000)),
        baseline: _at(2000),
      );

      expect(entry.action, BoardSyncAction.uploadChanged);
    });

    test('baseline: only board changed -> download', () {
      final entry = buildSyncEntry(
        relativePath: 'a.py',
        local: _local('a.py', 100, _at(2000)),
        board: _board('a.py', 300, _at(3000)),
        baseline: _at(2000),
      );

      expect(entry.action, BoardSyncAction.downloadChanged);
    });

    test('baseline: both changed -> conflict', () {
      final entry = buildSyncEntry(
        relativePath: 'a.py',
        local: _local('a.py', 200, _at(3000)),
        board: _board('a.py', 300, _at(4000)),
        baseline: _at(1000),
      );

      expect(entry.action, BoardSyncAction.conflict);
      expect(entry.note, contains('都修改过'));
    });
  });

  group('buildSyncPlan', () {
    test('unions both sides in sorted order', () {
      final plan = buildSyncPlan(
        local: _snapshot({
          'b.py': _local('b.py', 10, _at(2000)),
          'a.py': _local('a.py', 10, _at(2000)),
        }),
        board: _snapshot({
          'c.py': _board('c.py', 10, _at(2000)),
          'a.py': _board('a.py', 10, _at(2000)),
        }, root: '/'),
      );

      expect(plan.entries.map((entry) => entry.relativePath).toList(), [
        'a.py',
        'b.py',
        'c.py',
      ]);
      expect(plan.uploadCount, 1);
      expect(plan.downloadCount, 1);
      expect(plan.unchangedCount, 1);
      expect(plan.boardRoot, '/');
    });

    test('actionable excludes unchanged and conflicts', () {
      final plan = buildSyncPlan(
        local: _snapshot({
          'same.py': _local('same.py', 10, _at(2000)),
          'new.py': _local('new.py', 10, _at(2000)),
          'clash.py': _local('clash.py', 20, _at(2000)),
        }),
        board: _snapshot({
          'same.py': _board('same.py', 10, _at(2000)),
          'clash.py': _board('clash.py', 10, _at(2000)),
        }),
      );

      expect(plan.entries.length, 3);
      expect(plan.actionable.length, 1);
      expect(plan.actionable.single.relativePath, 'new.py');
      expect(plan.conflicts.single.relativePath, 'clash.py');
      expect(plan.hasWork, isTrue);
    });

    test('totalTransferBytes only counts actionable rows', () {
      final plan = buildSyncPlan(
        local: _snapshot({
          'a.py': _local('a.py', 100, _at(2000)),
          'b.py': _local('b.py', 40, _at(2000)),
        }),
        board: _snapshot({
          'b.py': _board('b.py', 10, _at(1000)),
          'c.py': _board('c.py', 7, _at(2000)),
        }),
      );

      expect(plan.totalTransferBytes, 100 + 40 + 7);
    });

    test('includeUnchanged=false drops identical rows', () {
      final plan = buildSyncPlan(
        local: _snapshot({'same.py': _local('same.py', 10, _at(2000))}),
        board: _snapshot({'same.py': _board('same.py', 10, _at(2000))}),
        includeUnchanged: false,
      );

      expect(plan.entries, isEmpty);
      expect(plan.hasWork, isFalse);
    });

    test('localToBoard direction drops download-only rows', () {
      final plan = buildSyncPlan(
        local: _snapshot({'new.py': _local('new.py', 10, _at(2000))}),
        board: _snapshot({'board.py': _board('board.py', 10, _at(2000))}),
        direction: BoardSyncDirection.localToBoard,
      );

      expect(plan.entries.map((entry) => entry.relativePath), ['new.py']);
    });

    test('boardToLocal direction drops upload-only rows', () {
      final plan = buildSyncPlan(
        local: _snapshot({'new.py': _local('new.py', 10, _at(2000))}),
        board: _snapshot({'board.py': _board('board.py', 10, _at(2000))}),
        direction: BoardSyncDirection.boardToLocal,
      );

      expect(plan.entries.map((entry) => entry.relativePath), ['board.py']);
    });

    test('required directories come from every upload parent', () {
      final plan = buildSyncPlan(
        local: _snapshot({
          'lib/a.py': _local('lib/a.py', 1, _at(2000)),
          'lib/deep/b.py': _local('lib/deep/b.py', 1, _at(2000)),
        }),
        board: _snapshot(const {}),
      );

      expect(plan.requiredBoardDirectories, {'lib', 'lib/deep'});
      expect(plan.requiredLocalDirectories, isEmpty);
    });

    test('required local directories come from every download parent', () {
      final plan = buildSyncPlan(
        local: _snapshot(const {}),
        board: _snapshot({'pkg/a.py': _board('pkg/a.py', 1, _at(2000))}),
      );

      expect(plan.requiredLocalDirectories, {'pkg'});
      expect(plan.requiredBoardDirectories, isEmpty);
    });

    test('empty snapshots produce an empty plan', () {
      final plan = buildSyncPlan(
        local: _snapshot(const {}),
        board: _snapshot(const {}),
      );

      expect(plan.isEmpty, isTrue);
      expect(plan.hasWork, isFalse);
    });
  });

  group('buildSyncPlan: .pyrsyncignore', () {
    test('flags the ignore file and every matched path', () {
      final plan = buildSyncPlan(
        local: _snapshot({
          '.pyrsyncignore': _local('.pyrsyncignore', 24, _at(2000)),
          'main.py': _local('main.py', 10, _at(2000)),
          'build/out.bin': _local('build/out.bin', 5, _at(2000)),
        }),
        board: _snapshot(const {}),
        ignore: SyncIgnoreRules.parse('# keep the board small\nbuild\n'),
      );

      expect(
        plan.entries
            .where((entry) => entry.ignoredByDefault)
            .map((entry) => entry.relativePath),
        ['.pyrsyncignore', 'build/out.bin'],
      );
      // Ignored rows stay in the diff, they are only pre-unticked.
      expect(plan.actionable.length, 3);
      expect(plan.defaultSelection.map((entry) => entry.relativePath), [
        'main.py',
      ]);
      expect(plan.ignoredCount, 2);
    });

    test('the same rules match board-only rows', () {
      final plan = buildSyncPlan(
        local: _snapshot(const {}),
        board: _snapshot({
          'vendor/lib.py': _board('vendor/lib.py', 10, _at(2000)),
          'main.py': _board('main.py', 10, _at(2000)),
        }),
        ignore: SyncIgnoreRules.parse('vendor\n'),
      );

      expect(plan.defaultSelection.map((entry) => entry.relativePath), [
        'main.py',
      ]);
      expect(plan.ignoredEntries.single.relativePath, 'vendor/lib.py');
    });

    test('no rules leave the default selection untouched', () {
      final plan = buildSyncPlan(
        local: _snapshot({'main.py': _local('main.py', 10, _at(2000))}),
        board: _snapshot(const {}),
      );

      expect(plan.ignoredEntries, isEmpty);
      expect(plan.defaultSelection.single.relativePath, 'main.py');
    });
  });

  group('buildSyncPlan: truncated local scan', () {
    test('never defaults board-only rows to a download', () {
      final plan = buildSyncPlan(
        local: const SyncTreeSnapshot(
          files: <String, SyncFileInfo>{},
          directories: <String>{},
          root: '/root',
          truncated: true,
        ),
        board: _snapshot({'boot.py': _board('boot.py', 7, _at(2000))}),
      );

      expect(plan.truncated, isTrue);
      final row = plan.entries.single;
      expect(row.action, BoardSyncAction.downloadNew);
      expect(row.selectable, isFalse);
      expect(row.note, isNotNull);
      expect(plan.actionable, isEmpty);
      expect(plan.defaultSelection, isEmpty);
      // The plan still reports work so the preview opens and explains the
      // truncation instead of the page claiming both sides already match.
      expect(plan.hasWork, isTrue);
    });

    test('keeps rows whose local copy was scanned uploadable', () {
      final plan = buildSyncPlan(
        local: SyncTreeSnapshot(
          files: {'main.py': _local('main.py', 10, _at(2000))},
          directories: const {},
          root: '/root',
          truncated: true,
        ),
        board: _snapshot(const {}),
      );

      expect(plan.truncated, isTrue);
      expect(plan.defaultSelection.map((entry) => entry.relativePath), [
        'main.py',
      ]);
    });

    test('a complete scan still offers board-only rows', () {
      final plan = buildSyncPlan(
        local: _snapshot(const {}),
        board: _snapshot({'boot.py': _board('boot.py', 7, _at(2000))}),
      );

      expect(plan.truncated, isFalse);
      expect(plan.entries.single.selectable, isTrue);
      expect(plan.defaultSelection.map((entry) => entry.relativePath), [
        'boot.py',
      ]);
    });
  });

  group('normalizeSyncRelativePath', () {
    test('normalizes separators and leading markers', () {
      expect(normalizeSyncRelativePath('lib\\a.py'), 'lib/a.py');
      expect(normalizeSyncRelativePath('./lib/a.py'), 'lib/a.py');
      expect(normalizeSyncRelativePath('/lib/a.py'), 'lib/a.py');
      expect(normalizeSyncRelativePath('lib//a.py'), 'lib/a.py');
      expect(normalizeSyncRelativePath('.'), '');
    });
  });

  group('BoardSyncEntry.copyWith', () {
    test('recomputes direction and clears the note on override', () {
      final conflict = buildSyncEntry(
        relativePath: 'a.py',
        local: _local('a.py', 20, _at(2000)),
        board: _board('a.py', 10, _at(2000)),
      );
      expect(conflict.action, BoardSyncAction.conflict);

      final overridden = conflict.copyWith(
        action: BoardSyncAction.uploadChanged,
      );

      expect(overridden.action, BoardSyncAction.uploadChanged);
      expect(overridden.direction, BoardSyncDirection.localToBoard);
      expect(overridden.selectable, isTrue);
      expect(overridden.note, isNull);
    });

    test('keeps the ignore flag when the action is overridden', () {
      final ignored = buildSyncEntry(
        relativePath: 'build/a.py',
        local: _local('build/a.py', 10, _at(2000)),
        board: _board('build/a.py', 20, _at(2000)),
      ).copyWith(ignoredByDefault: true);

      final overridden = ignored.copyWith(
        action: BoardSyncAction.uploadChanged,
      );

      expect(overridden.ignoredByDefault, isTrue);
    });
  });
}
