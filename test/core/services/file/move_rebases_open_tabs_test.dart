import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/file_open_codec.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_backend.dart';
import 'package:pyrite_ide/core/services/file/board_provider.dart';
import 'package:pyrite_ide/core/services/file/board_tree.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_tree.dart';
import 'package:super_tree/super_tree.dart';
import 'package:tabbed_view/tabbed_view.dart';

/// A controller stand-in exposing the members the move/save paths touch.
class _StubEditorController implements CodeForgeController {
  _StubEditorController(this._text);

  String _text;
  final List<VoidCallback> _listeners = [];

  @override
  String get text => _text;

  @override
  set text(String value) => _text = value;

  @override
  int get contentVersion => 0;

  @override
  bool readOnly = false;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Registers controllers without going through the Rust-backed open flow.
class _StubControllerMap extends EditorControllerMapNotifier {
  _StubControllerMap(super.ref, Map<String, CodeForgeController> controllers) {
    state = controllers;
  }
}

/// A tree rebuild would re-read the real workspace and is irrelevant here.
class _NoopLocalFileItemsNotifier extends LocalFileItemsNotifier {
  _NoopLocalFileItemsNotifier(super.ref);

  @override
  Future<List<TreeNode<FileSystemItem>>> buildRootFileListItems() async =>
      const [];
}

class _NoopBoardFileItemsNotifier extends BoardFileItemsNotifier {
  _NoopBoardFileItemsNotifier(super.ref);

  @override
  Future<List<TreeNode<FileSystemItem>>> buildRootFileListItems() async =>
      const [];
}

/// In-memory board backend that records moves and treats unknown paths as
/// absent, which is what the move conflict check expects.
class _FakeBoardBackend implements BoardFileBackend {
  final Map<String, String> files = {};
  final List<(String, String)> moves = [];

  @override
  Future<List<BoardFileEntry>> listDirectory({String path = '/'}) async =>
      const [];

  @override
  Future<List<BoardFileEntry>> listTree({
    String path = '/',
    bool includeMetadata = false,
  }) async => const [];

  @override
  Future<String> readTextFile(String path) async => files[path] ?? '';

  @override
  Future<Uint8List> readFileBytes(
    String path, {
    void Function(int received, int total)? onProgress,
  }) async => Uint8List(0);

  @override
  Future<void> writeTextFile(String path, String content) async {
    files[path] = content;
  }

  @override
  Future<void> writeFileBytes(
    String path,
    List<int> bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    files[path] = String.fromCharCodes(bytes);
  }

  @override
  Future<void> deleteFile(String path) async {
    files.remove(path);
  }

  @override
  Future<void> deleteFolder(String path) async {
    files.removeWhere((filePath, _) => filePath.startsWith('$path/'));
  }

  @override
  Future<void> rename(String path, String newName) async {}

  @override
  Future<void> move(String oldPath, String newPath) async {
    moves.add((oldPath, newPath));
    final content = files.remove(oldPath);
    if (content != null) files[newPath] = content;
  }

  @override
  Future<void> createFolder(String path) async {}

  @override
  Future<void> pathExists(String path) async {
    if (!files.containsKey(path)) {
      throw BoardFileBackendException('missing: $path');
    }
  }

  @override
  Future<int?> freeSpaceBytes({String path = '/'}) async => null;

  @override
  Future<Map<String, int>> hashFiles(Iterable<String> paths) async => const {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory project;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pyrite_move_rebase_');
    project = Directory(path.join(root.path, 'proj'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  ProviderContainer createContainer({
    Map<String, CodeForgeController> controllers = const {},
    BoardFileBackend? boardBackend,
  }) {
    final container = ProviderContainer(
      overrides: [
        localFileItemsProvider.overrideWith(_NoopLocalFileItemsNotifier.new),
        boardFileItemsProvider.overrideWith(_NoopBoardFileItemsNotifier.new),
        editorControllerMapProvider.overrideWith(
          (ref) => _StubControllerMap(ref, Map.of(controllers)),
        ),
        if (boardBackend != null)
          boardFileBackendProvider.overrideWithValue(boardBackend),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  TabData openTab(
    ProviderContainer container,
    File file,
    CodeForgeController controller, {
    bool isSaved = true,
    String? encoding,
    bool byteOrderMark = false,
    bool isBoardFile = false,
    String? boardFilePath,
  }) {
    final tab = TabData(
      text: path.basename(file.path),
      value: TabDataValue(
        type: 'file',
        filePath: file.path,
        file: file,
        editorController: controller,
        isSaved: isSaved,
        encoding: encoding,
        byteOrderMark: byteOrderMark,
        isBoardFile: isBoardFile,
        boardFilePath: boardFilePath,
      ),
    );
    final group = container.read(tabbedViewControllerProvider);
    group.addTab(tab);
    group.selectedIndex = group.tabs.indexOf(tab);
    return tab;
  }

  Future<void> pumpShell(WidgetTester tester, ProviderContainer container) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ),
    );
  }

  testWidgets('moving an open file rebases the tab and saves to the new path', (
    tester,
  ) async {
    final source = File(path.join(project.path, 'a.py'))
      ..writeAsStringSync('print(1)');
    final lib = Directory(path.join(project.path, 'lib'))..createSync();
    final controller = _StubEditorController('print(2)');
    final container = createContainer(controllers: {source.path: controller});
    final tab = openTab(
      container,
      source,
      controller,
      isSaved: false,
      encoding: 'gbk',
      byteOrderMark: true,
    );
    await pumpShell(tester, container);
    final context = tester.element(find.byType(Scaffold));

    await tester.runAsync(
      () => container.read(fileProvider.notifier).moveLocalNodes(context, [
        TreeNode<FileSystemItem>(id: source.path, data: FileItem('a.py')),
      ], lib.path),
    );

    final newPath = path.join(lib.path, 'a.py');
    final value = editorTabValueOf(tab)!;
    expect(value.filePath, newPath);
    expect(value.file!.path, newPath);
    expect(value.isSaved, isFalse);
    expect(value.encoding, 'gbk');
    expect(value.byteOrderMark, isTrue);
    expect(source.existsSync(), isFalse);
    expect(File(newPath).readAsStringSync(), 'print(1)');

    controller.text = 'print(3)';
    final saved = await tester.runAsync(
      () => container.read(fileProvider.notifier).saveTab(tab),
    );

    expect(saved, isTrue);
    expect(
      File(newPath).readAsBytesSync(),
      encodeFileText('print(3)', encoding: 'gbk', byteOrderMark: true),
    );
    expect(source.existsSync(), isFalse);
  });

  testWidgets('moving a folder rebases every open descendant tab', (
    tester,
  ) async {
    final package = Directory(path.join(project.path, 'pkg'))..createSync();
    final nested = Directory(path.join(package.path, 'sub'))..createSync();
    final top = File(path.join(package.path, 'a.py'))..writeAsStringSync('top');
    final deep = File(path.join(nested.path, 'b.py'))
      ..writeAsStringSync('deep');
    final lib = Directory(path.join(project.path, 'lib'))..createSync();
    final topController = _StubEditorController('top');
    final deepController = _StubEditorController('deep');
    final container = createContainer(
      controllers: {top.path: topController, deep.path: deepController},
    );
    final topTab = openTab(container, top, topController);
    final deepTab = openTab(container, deep, deepController);
    await pumpShell(tester, container);
    final context = tester.element(find.byType(Scaffold));

    await tester.runAsync(
      () => container.read(fileProvider.notifier).moveLocalNodes(context, [
        TreeNode<FileSystemItem>(id: package.path, data: FolderItem('pkg')),
      ], lib.path),
    );

    final movedTop = path.join(lib.path, 'pkg', 'a.py');
    final movedDeep = path.join(lib.path, 'pkg', 'sub', 'b.py');
    expect(editorTabValueOf(topTab)!.filePath, movedTop);
    expect(editorTabValueOf(topTab)!.file!.path, movedTop);
    expect(editorTabValueOf(deepTab)!.filePath, movedDeep);
    expect(editorTabValueOf(deepTab)!.file!.path, movedDeep);
    expect(File(movedTop).readAsStringSync(), 'top');
    expect(File(movedDeep).readAsStringSync(), 'deep');
  });

  testWidgets('moving a board file rebases its tab and mirror cache', (
    tester,
  ) async {
    final cacheRoot = Directory(path.join(root.path, 'board_cache'))
      ..createSync();
    final cacheFile = File(path.join(cacheRoot.path, 'pkg', 'a.py'));
    final backend = _FakeBoardBackend()..files['/pkg/a.py'] = 'print(1)';
    final controller = _StubEditorController('print(2)');
    final container = createContainer(
      controllers: {cacheFile.path: controller},
      boardBackend: backend,
    );
    final tab = openTab(
      container,
      cacheFile,
      controller,
      isSaved: false,
      isBoardFile: true,
      boardFilePath: '/pkg/a.py',
    );
    await pumpShell(tester, container);
    final context = tester.element(find.byType(Scaffold));

    await tester.runAsync(
      () => container.read(boardProvider).moveBoardNodes(context, [
        TreeNode<FileSystemItem>(id: '/pkg/a.py', data: FileItem('a.py')),
      ], '/lib'),
    );

    final value = editorTabValueOf(tab)!;
    final newCachePath = path.join(cacheRoot.path, 'lib', 'a.py');
    expect(value.boardFilePath, '/lib/a.py');
    expect(value.filePath, newCachePath);
    expect(value.file!.path, newCachePath);
    expect(value.isSaved, isFalse);
    expect(backend.moves, [('/pkg/a.py', '/lib/a.py')]);
    expect(File(newCachePath).readAsStringSync(), 'print(2)');
  });
}
