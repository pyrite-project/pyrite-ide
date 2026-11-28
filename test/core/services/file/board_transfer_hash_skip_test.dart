import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/device/file_hash.dart';
import 'package:pyrite_ide/core/services/device/sync_ignore.dart';
import 'package:pyrite_ide/core/services/file/board_backend.dart';

/// In-memory BoardFileBackend that stores files under keys without the
/// leading slash. Only the methods the folder transfers actually call are
/// implemented.
class _FakeBoardBackend implements BoardFileBackend {
  final Map<String, Uint8List> files = {};
  final Set<String> folders = {};
  final List<String> writtenPaths = [];

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
      final boardPath = '/${entry.key}';
      if (path != '/' && !boardPath.startsWith('$path/')) continue;
      entries.add(
        BoardFileEntry(
          path: boardPath,
          name: _boardPath.basename(entry.key),
          type: BoardFileEntryType.file,
          size: includeMetadata ? entry.value.length : null,
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
    return files[path.replaceFirst('/', '')] ?? Uint8List(0);
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
    writtenPaths.add(key);
    files[key] = Uint8List.fromList(bytes);
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
    final parent = _boardPath.dirname(path);
    if (parent != '/' && !folders.contains(parent)) {
      throw const BoardFileBackendException('OSError: [Errno 2] ENOENT');
    }
    folders.add(path);
  }

  @override
  Future<void> pathExists(String path) async {}

  @override
  Future<int?> freeSpaceBytes({String path = '/'}) async => null;

  @override
  Future<Map<String, int>> hashFiles(Iterable<String> paths) async {
    final checksums = <String, int>{};
    for (final boardPath in paths) {
      final data = files[boardPath.replaceFirst('/', '')];
      if (data != null) checksums[boardPath] = crc32OfBytes(data);
    }
    return checksums;
  }
}

final _boardPath = path.Context(style: path.Style.posix);

/// Test-only providers so [BoardFileOps] and [BoardTransfer] can be built from
/// a real `Ref` instead of handing them a `ProviderContainer`.
final _testOpsProvider = Provider<BoardFileOps>(BoardFileOps.new);
final _testTransferProvider = Provider<BoardTransfer>(
  (ref) => BoardTransfer(ref, ref.read(_testOpsProvider)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pyrite_board_transfer_');
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

  BoardTransfer transferOf(ProviderContainer container) =>
      container.read(_testTransferProvider);

  test('uploadFolder skips files the board already holds', () async {
    await writeLocal('a.py', 'same-content');
    await writeLocal('b.py', 'local-side');
    final backend = _FakeBoardBackend();
    backend.files['target/a.py'] = Uint8List.fromList('same-content'.codeUnits);
    backend.files['target/b.py'] = Uint8List.fromList('board-side'.codeUnits);
    final container = ProviderContainer(
      overrides: [boardFileBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);

    final skipped = await transferOf(
      container,
    ).uploadFolder(tempDir.path, '/target', preflightSpace: false);

    expect(skipped, 1);
    expect(backend.writtenPaths, ['target/b.py']);
    expect(String.fromCharCodes(backend.files['target/b.py']!), 'local-side');
    expect(String.fromCharCodes(backend.files['target/a.py']!), 'same-content');
  });

  test('uploadFolder transfers everything when sizes differ', () async {
    await writeLocal('a.py', 'short');
    final backend = _FakeBoardBackend();
    backend.files['target/a.py'] = Uint8List.fromList('much longer'.codeUnits);
    final container = ProviderContainer(
      overrides: [boardFileBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);

    final skipped = await transferOf(
      container,
    ).uploadFolder(tempDir.path, '/target', preflightSpace: false);

    expect(skipped, 0);
    expect(backend.writtenPaths, ['target/a.py']);
    expect(String.fromCharCodes(backend.files['target/a.py']!), 'short');
  });

  test('uploadFolder never transfers what .pyrsyncignore covers', () async {
    await writeLocal('main.py', 'print(1)');
    await writeLocal('build/out.bin', 'artifact');
    await writeLocal('build/deep/out.bin', 'artifact');
    await writeLocal('vendor/lib.py', 'vendored');
    await writeLocal('.pyrsyncignore', 'build\nvendor\n');
    final backend = _FakeBoardBackend();
    final container = ProviderContainer(
      overrides: [boardFileBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);

    final ignore = await loadSyncIgnoreFilter(tempDir.path);
    await transferOf(container).uploadFolder(
      tempDir.path,
      '/target',
      preflightSpace: false,
      ignore: ignore,
    );

    // Only the file the ignore list does not mention reaches the board: the
    // ignored trees are not written, and neither are their directories.
    expect(backend.writtenPaths, ['target/main.py']);
    expect(backend.folders, isNot(contains('/target/build')));
    expect(backend.folders, isNot(contains('/target/vendor')));
  });

  test('uploadFolder transfers everything when no filter is passed', () async {
    await writeLocal('main.py', 'print(1)');
    await writeLocal('build/out.bin', 'artifact');
    final backend = _FakeBoardBackend();
    final container = ProviderContainer(
      overrides: [boardFileBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);

    await transferOf(
      container,
    ).uploadFolder(tempDir.path, '/target', preflightSpace: false);

    expect(backend.writtenPaths, ['target/build/out.bin', 'target/main.py']);
  });

  test('downloadFolder skips files the workspace already holds', () async {
    final backend = _FakeBoardBackend();
    backend.files['src/a.py'] = Uint8List.fromList('same-content'.codeUnits);
    backend.files['src/b.py'] = Uint8List.fromList('board-side'.codeUnits);
    final container = ProviderContainer(
      overrides: [boardFileBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);
    final targetDir = path.join(tempDir.path, 'workspace');
    await writeLocal('workspace/a.py', 'same-content');

    final skipped = await transferOf(
      container,
    ).downloadFolder('/src', targetDir);

    expect(skipped, 1);
    expect(
      await File(path.join(targetDir, 'a.py')).readAsString(),
      'same-content',
    );
    expect(
      await File(path.join(targetDir, 'b.py')).readAsString(),
      'board-side',
    );
  });
}
