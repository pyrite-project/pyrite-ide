import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/device/board_sync_plan.dart';
import 'package:pyrite_ide/core/services/device/board_sync_service.dart';
import 'package:pyrite_ide/core/services/device/transfer_control.dart';
import 'package:pyrite_ide/core/services/file/board_backend.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';

/// In-memory BoardFileBackend that records every write and never touches a
/// device. Only the methods the sync executor actually calls are implemented.
class _FakeBoardBackend implements BoardFileBackend {
  _FakeBoardBackend({this.failOnPaths = const {}});

  final Set<String> failOnPaths;
  final Map<String, Uint8List> files = {};
  final Set<String> folders = {};
  final List<String> writtenPaths = [];

  /// Test hook invoked with the written path, used to cancel mid-transfer.
  void Function(String path)? onWrite;

  @override
  Future<List<BoardFileEntry>> listDirectory({String path = '/'}) async {
    throw UnimplementedError();
  }

  @override
  Future<List<BoardFileEntry>> listTree({
    String path = '/',
    bool includeMetadata = false,
  }) async {
    final entries = <BoardFileEntry>[];
    for (final entry in files.entries) {
      entries.add(
        BoardFileEntry(
          path: '/${entry.key}',
          name: _boardPath.basename(entry.key),
          type: BoardFileEntryType.file,
          size: entry.value.length,
        ),
      );
    }
    return entries;
  }

  @override
  Future<String> readTextFile(String path) async =>
      String.fromCharCodes(files[path.replaceFirst('/', '')] ?? const []);

  @override
  Future<Uint8List> readFileBytes(
    String path, {
    void Function(int received, int total)? onProgress,
  }) async {
    final bytes = files[path.replaceFirst('/', '')] ?? Uint8List(0);
    onProgress?.call(bytes.length, bytes.length);
    return bytes;
  }

  @override
  Future<void> writeTextFile(String path, String content) async {}

  @override
  Future<void> writeFileBytes(
    String path,
    List<int> bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final key = path.replaceFirst('/', '');
    if (failOnPaths.contains(key)) {
      throw const BoardFileBackendException('simulated write failure');
    }
    writtenPaths.add(key);
    files[key] = Uint8List.fromList(bytes);
    onWrite?.call(key);
    onProgress?.call(bytes.length, bytes.length);
  }

  @override
  Future<void> deleteFile(String path) async {}

  @override
  Future<void> deleteFolder(String path) async {}

  @override
  Future<void> rename(String path, String newName) async {}

  @override
  Future<void> move(String oldPath, String newPath) async {}

  @override
  Future<void> createFolder(String path) async {
    folders.add(path);
  }

  @override
  Future<void> pathExists(String path) async {}

  @override
  Future<int?> freeSpaceBytes({String path = '/'}) async => null;
}

final _boardPath = path.Context(style: path.Style.posix);

/// Test-only provider so [BoardFileOps] can be built from a real `Ref`
/// instead of handing it a `ProviderContainer`.
final _testOpsProvider = Provider<BoardFileOps>((ref) => BoardFileOps(ref));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pyrite_sync_exec_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<File> writeLocal(String relative, String content) async {
    final file = File(path.join(tempDir.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  BoardSyncEntry uploadEntry(String relative, int size) => BoardSyncEntry(
    relativePath: relative,
    action: BoardSyncAction.uploadNew,
    direction: BoardSyncDirection.localToBoard,
    local: SyncFileInfo(relativePath: relative, size: size),
  );

  BoardSyncEntry downloadEntry(String relative, int size) => BoardSyncEntry(
    relativePath: relative,
    action: BoardSyncAction.downloadNew,
    direction: BoardSyncDirection.boardToLocal,
    board: SyncFileInfo(relativePath: relative, size: size),
  );

  BoardSyncPlan planOf(List<BoardSyncEntry> entries) =>
      BoardSyncPlan(entries: entries, localRoot: tempDir.path);

  test('uploads only the selected entries through writeFileBytes', () async {
    await writeLocal('main.py', 'print(1)');
    await writeLocal('skip.py', 'skip');
    final backend = _FakeBoardBackend();
    final container = ProviderContainer(
      overrides: [boardFileBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);

    final progress = container.read(fileTransferProgressProvider.notifier);
    final executor = BoardSyncExecutor(
      ops: container.read(_testOpsProvider),
      progress: progress,
    );

    final result = await executor.execute(
      plan: planOf([uploadEntry('main.py', 8), uploadEntry('skip.py', 4)]),
      localRoot: tempDir.path,
      selectedPaths: {'main.py'},
    );

    expect(result.uploaded, 1);
    expect(result.downloaded, 0);
    expect(result.hasFailures, isFalse);
    expect(backend.writtenPaths, ['main.py']);
    expect(String.fromCharCodes(backend.files['main.py']!), 'print(1)');
    expect(progress.state.cancelled, isFalse);
  });

  test('downloads board files into the local workspace', () async {
    final backend = _FakeBoardBackend();
    backend.files['boot.py'] = Uint8List.fromList('import sys'.codeUnits);
    final container = ProviderContainer(
      overrides: [boardFileBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);

    final executor = BoardSyncExecutor(
      ops: container.read(_testOpsProvider),
      progress: container.read(fileTransferProgressProvider.notifier),
    );

    final result = await executor.execute(
      plan: planOf([downloadEntry('boot.py', 10)]),
      localRoot: tempDir.path,
    );

    expect(result.downloaded, 1);
    final localFile = File(path.join(tempDir.path, 'boot.py'));
    expect(await localFile.exists(), isTrue);
    expect(await localFile.readAsString(), 'import sys');
  });

  test('creates the required board directories before uploading', () async {
    await writeLocal('lib/deep/a.py', 'a');
    final backend = _FakeBoardBackend();
    final container = ProviderContainer(
      overrides: [boardFileBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);

    final plan = BoardSyncPlan(
      entries: [
        BoardSyncEntry(
          relativePath: 'lib/deep/a.py',
          action: BoardSyncAction.uploadNew,
          direction: BoardSyncDirection.localToBoard,
          local: const SyncFileInfo(relativePath: 'lib/deep/a.py', size: 1),
        ),
      ],
    );
    final executor = BoardSyncExecutor(
      ops: container.read(_testOpsProvider),
      progress: container.read(fileTransferProgressProvider.notifier),
    );

    await executor.execute(plan: plan, localRoot: tempDir.path);

    expect(backend.folders, containsAll(['/lib', '/lib/deep']));
    expect(backend.writtenPaths, ['lib/deep/a.py']);
  });

  test('cancellation stops between files and reports it', () async {
    await writeLocal('a.py', 'a');
    await writeLocal('b.py', 'b');
    await writeLocal('c.py', 'c');
    final backend = _FakeBoardBackend();
    final container = ProviderContainer(
      overrides: [boardFileBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);

    final progress = container.read(fileTransferProgressProvider.notifier);
    final executor = BoardSyncExecutor(
      ops: container.read(_testOpsProvider),
      progress: progress,
    );
    final token = progress.beginCancelToken();

    final plan = planOf([
      uploadEntry('a.py', 1),
      uploadEntry('b.py', 1),
      uploadEntry('c.py', 1),
    ]);

    final result = await executor.execute(
      plan: plan,
      localRoot: tempDir.path,
      cancel: token,
    );

    expect(result.cancelled, isFalse);
    expect(backend.writtenPaths, ['a.py', 'b.py', 'c.py']);

    // Mid-run cancellation: the fake backend cancels the token while writing
    // the first file, so file 1 must complete and files 2/3 must not start.
    backend.writtenPaths.clear();
    backend.onWrite = (key) {
      if (key == 'a.py') progress.requestCancel();
    };
    final midRun = await executor.execute(plan: plan, localRoot: tempDir.path);

    expect(midRun.cancelled, isTrue);
    expect(midRun.uploaded, 1);
    expect(backend.writtenPaths, ['a.py']);
    expect(progress.state.cancelled, isTrue);
    backend.onWrite = null;

    // Cancel up front: nothing may be written and the state must be clean.
    backend.writtenPaths.clear();
    final cancelledToken = FileTransferCancelToken()..cancel();
    final cancelled = await executor.execute(
      plan: plan,
      localRoot: tempDir.path,
      cancel: cancelledToken,
    );

    expect(cancelled.cancelled, isTrue);
    expect(cancelled.uploaded, 0);
    expect(backend.writtenPaths, isEmpty);
    expect(progress.state.cancelled, isTrue);
  });

  test('a single failed file does not abort the rest of the plan', () async {
    await writeLocal('ok.py', 'ok');
    await writeLocal('bad.py', 'bad');
    final backend = _FakeBoardBackend(failOnPaths: {'bad.py'});
    final container = ProviderContainer(
      overrides: [boardFileBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);

    final executor = BoardSyncExecutor(
      ops: container.read(_testOpsProvider),
      progress: container.read(fileTransferProgressProvider.notifier),
    );

    final result = await executor.execute(
      plan: planOf([uploadEntry('bad.py', 3), uploadEntry('ok.py', 2)]),
      localRoot: tempDir.path,
    );

    expect(result.uploaded, 1);
    expect(result.failed.length, 1);
    expect(result.failed.single.entry.relativePath, 'bad.py');
    expect(backend.writtenPaths, ['ok.py']);
  });
}
