import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_forge/code_forge.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/external_file_change.dart';
import 'package:pyrite_ide/core/services/editor/file_open_codec.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_backend.dart';
import 'package:pyrite_ide/core/services/file/board_provider.dart';
import 'package:pyrite_ide/core/services/file/board_tree.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:tabbed_view/src/tab_data.dart';

/// A controller stand-in with just the buffer and read-only flag the transfer
/// save path touches. The real controller needs the Rust rope initialized.
class _FakeEditorController implements CodeForgeController {
  _FakeEditorController(this._text);

  String _text;

  @override
  String get text => _text;

  @override
  set text(String value) => _text = value;

  @override
  bool readOnly = false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not read by the transfer path: $invocation');
}

/// Registers controllers without going through the Rust-backed open flow.
class _StubControllerMap extends EditorControllerMapNotifier {
  _StubControllerMap(super.ref, Map<String, CodeForgeController> controllers) {
    state = controllers;
  }
}

/// In-memory board backend, recording every read and upload so the tests can
/// tell whether the transfer ran at all.
class _FakeBoardBackend implements BoardFileBackend {
  final Map<String, String> files = {};
  final List<String> reads = [];
  final List<(String, String)> uploads = [];

  @override
  Future<List<BoardFileEntry>> listDirectory({String path = '/'}) async {
    if (path != '/') return const [];
    return [
      for (final entry in files.entries)
        BoardFileEntry(
          path: entry.key,
          name: entry.key.substring(1),
          type: BoardFileEntryType.file,
        ),
    ];
  }

  @override
  Future<List<BoardFileEntry>> listTree({
    String path = '/',
    bool includeMetadata = false,
  }) => listDirectory(path: path);

  @override
  Future<String> readTextFile(String path) async {
    reads.add(path);
    return files[path] ?? '';
  }

  @override
  Future<Uint8List> readFileBytes(
    String path, {
    void Function(int received, int total)? onProgress,
  }) async {
    reads.add(path);
    return Uint8List.fromList(utf8.encode(files[path] ?? ''));
  }

  @override
  Future<void> writeTextFile(String path, String content) async {
    files[path] = content;
    uploads.add((path, content));
  }

  @override
  Future<void> writeFileBytes(
    String path,
    List<int> bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    files[path] = utf8.decode(bytes);
    uploads.add((path, files[path]!));
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
  Future<void> createFolder(String path) async {}

  @override
  Future<void> pathExists(String path) async {}

  @override
  Future<int?> freeSpaceBytes({String path = '/'}) async => null;

  @override
  Future<Map<String, int>> hashFiles(Iterable<String> paths) async => const {};
}

/// Writes the tab's bytes synchronously, in the tab's own encoding. A real
/// [File.writeAsBytes] future never completes inside the fake-async zone the
/// widget tests run in.
class _TestFileNotifier extends FileNotifier {
  _TestFileNotifier(super.ref);

  int writes = 0;
  final List<String> writtenTexts = [];

  @override
  Future<void> writeTabText(TabDataValue value, String text) async {
    writes++;
    writtenTexts.add(text);
    value.file!.writeAsBytesSync(
      encodeFileText(
        text,
        encoding: value.encoding,
        byteOrderMark: value.byteOrderMark,
      ),
      flush: true,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory workspace;
  late _FakeBoardBackend backend;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pyrite_transfer_save_');
    workspace = Directory(path.join(root.path, 'workspace'))
      ..createSync(recursive: true);
    backend = _FakeBoardBackend();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  ProviderContainer containerWith(
    Map<String, CodeForgeController> controllers,
  ) {
    final container = ProviderContainer(
      overrides: [
        fileProvider.overrideWith(_TestFileNotifier.new),
        boardFileBackendProvider.overrideWithValue(backend),
        editorControllerMapProvider.overrideWith(
          (ref) => _StubControllerMap(ref, controllers),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Pretend the files on disk match the last baseline the editor recorded,
    // so a save does not raise its external-change prompt. The transfer's own
    // reads go through the notifier seam below, not this stub.
    final tabs = container.read(tabbedViewControllerProvider.notifier);
    tabs.diskStampReader = (file) async =>
        FileDiskStamp(modified: DateTime.utc(2026, 1, 1), size: 0);
    tabs.diskTextReader = (file) async => '';
    return container;
  }

  TabData tabFor(
    File file,
    CodeForgeController controller, {
    required bool isSaved,
    String? encoding,
    bool byteOrderMark = false,
    bool readOnly = false,
  }) {
    controller.readOnly = readOnly;
    return TabData(
      text: path.basename(file.path),
      value: TabDataValue(
        type: 'file',
        filePath: file.path,
        file: file,
        editorController: controller,
        isSaved: isSaved,
        encoding: encoding,
        byteOrderMark: byteOrderMark,
      ),
    );
  }

  void openTabs(
    ProviderContainer container,
    List<TabData> tabs, {
    required TabData focused,
  }) {
    final group = container.read(tabbedViewControllerProvider);
    for (final tab in tabs) {
      group.addTab(tab);
    }
    group.selectedIndex = group.tabs.indexOf(focused);
    expect(
      editorTabValueOf(group.selectedTab)?.filePath,
      (focused.value as TabDataValue).filePath,
    );
  }

  Future<void> pumpShell(WidgetTester tester, ProviderContainer container) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int frames = 500,
  }) async {
    for (var i = 0; i < frames && !condition(); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// Sets up a board file at `/main.py` whose mirror is [mirrorFile], with the
  /// board tree focused on that file.
  Future<void> focusBoardFile(
    WidgetTester tester,
    ProviderContainer container,
    File mirrorFile,
  ) async {
    container.read(boardProvider).mirrorFileReader = (boardPath) async =>
        mirrorFile;
    unawaited(
      container.read(boardFileItemsProvider.notifier).buildRootFileListItems(),
    );
    await pumpUntil(
      tester,
      () =>
          container
              .read(boardFileTreeViewControllerProvider)
              .findNodeById('/main.py') !=
          null,
    );
    container
        .read(boardFileTreeViewControllerProvider)
        .setSelectedNodeId('/main.py');
  }

  testWidgets('download saves the tab the conflict dialog compared', (
    tester,
  ) async {
    final mirrorFile = File(path.join(root.path, 'main.py'))
      ..writeAsStringSync('mirror old');
    final otherFile = File(path.join(workspace.path, 'b.py'))
      ..writeAsStringSync('focused tab old');
    final compared = _FakeEditorController('编辑器内容');
    final focused = _FakeEditorController('focused buffer');
    final comparedTab = tabFor(
      mirrorFile,
      compared,
      isSaved: false,
      // A GBK tab has to be written back in GBK; a plain UTF-8 save would
      // transcode it and corrupt the file.
      encoding: 'gbk',
    );
    final focusedTab = tabFor(otherFile, focused, isSaved: false);
    backend.files['/main.py'] = 'board old';

    final container = containerWith({mirrorFile.path: compared});
    container.read(fileProvider.notifier).setDirectory(workspace);
    openTabs(container, [comparedTab, focusedTab], focused: focusedTab);
    await pumpShell(tester, container);
    await focusBoardFile(tester, container, mirrorFile);

    final context = tester.element(find.byType(Scaffold));
    unawaited(container.read(boardProvider).downloadSelectedBoardItem(context));
    await pumpUntil(
      tester,
      () =>
          find.text(I18nKey.dialogEditorContent.fallback).evaluate().isNotEmpty,
    );
    await tester.tap(find.text(I18nKey.dialogEditorContent.fallback));

    // The compared tab is the one the dialog showed, not the focused one.
    await pumpUntil(
      tester,
      () => gbk.decode(mirrorFile.readAsBytesSync()) == '编辑器内容',
    );
    expect(gbk.decode(mirrorFile.readAsBytesSync()), '编辑器内容');
    expect(otherFile.readAsStringSync(), 'focused tab old');
    expect(
      (container.read(fileProvider.notifier) as _TestFileNotifier).writtenTexts,
      ['编辑器内容'],
    );
  });

  testWidgets('upload sends the bytes the save wrote, not the stale file', (
    tester,
  ) async {
    final sourceFile = File(path.join(workspace.path, 'a.py'))
      ..writeAsStringSync('old local');
    final otherFile = File(path.join(workspace.path, 'b.py'))
      ..writeAsStringSync('focused tab old');
    final compared = _FakeEditorController('new buffer');
    final focused = _FakeEditorController('focused buffer');
    final comparedTab = tabFor(sourceFile, compared, isSaved: false);
    final focusedTab = tabFor(otherFile, focused, isSaved: false);
    // The device already holds what the save will produce, so the only
    // conflict is between the stale local file and the editor buffer.
    backend.files['/a.py'] = 'new buffer';

    final container = containerWith({sourceFile.path: compared});
    container.read(fileProvider.notifier).setDirectory(workspace);
    final notifier = container.read(fileProvider.notifier) as _TestFileNotifier;
    var reads = 0;
    // Reads go through the fake-async-safe seam, and read the real bytes the
    // synchronous test writer just put on disk.
    notifier.localTextReader = (sourcePath) async {
      reads++;
      return File(sourcePath).readAsStringSync();
    };
    openTabs(container, [comparedTab, focusedTab], focused: focusedTab);
    await pumpShell(tester, container);

    final context = tester.element(find.byType(Scaffold));
    unawaited(
      notifier.uploadSelectedLocalFileItem(context, selectedTab: comparedTab),
    );
    await pumpUntil(
      tester,
      () =>
          find.text(I18nKey.dialogEditorContent.fallback).evaluate().isNotEmpty,
    );
    await tester.tap(find.text(I18nKey.dialogEditorContent.fallback));

    // The upload starts only after the write: what reaches the device is the
    // editor buffer, not the bytes that were on disk when the dialog opened.
    await pumpUntil(tester, () => backend.uploads.isNotEmpty);
    expect(backend.uploads, [('/a.py', 'new buffer')]);
    expect(sourceFile.readAsStringSync(), 'new buffer');
    expect(otherFile.readAsStringSync(), 'focused tab old');
    expect(reads, greaterThanOrEqualTo(2));
    // Let the transfer-progress auto-clear and the success message expire
    // before the test binding checks for pending timers.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a refused save aborts the download before it reads again', (
    tester,
  ) async {
    final mirrorFile = File(path.join(root.path, 'main.py'))
      ..writeAsStringSync('mirror old');
    final otherFile = File(path.join(workspace.path, 'b.py'))
      ..writeAsStringSync('focused tab old');
    final compared = _FakeEditorController('board edit');
    final focused = _FakeEditorController('focused buffer');
    final comparedTab = tabFor(
      mirrorFile,
      compared,
      isSaved: false,
      readOnly: true,
    );
    final focusedTab = tabFor(otherFile, focused, isSaved: false);
    backend.files['/main.py'] = 'board old';

    final container = containerWith({mirrorFile.path: compared});
    container.read(fileProvider.notifier).setDirectory(workspace);
    openTabs(container, [comparedTab, focusedTab], focused: focusedTab);
    await pumpShell(tester, container);
    await focusBoardFile(tester, container, mirrorFile);

    final context = tester.element(find.byType(Scaffold));
    unawaited(container.read(boardProvider).downloadSelectedBoardItem(context));
    await pumpUntil(
      tester,
      () =>
          find.text(I18nKey.dialogEditorContent.fallback).evaluate().isNotEmpty,
    );
    await tester.tap(find.text(I18nKey.dialogEditorContent.fallback));
    // Let the refused save and everything queued behind it settle.
    await pumpUntil(tester, () => false, frames: 200);

    // Only the comparison read happened; the download itself never started.
    expect(backend.reads, ['/main.py']);
    expect(mirrorFile.readAsStringSync(), 'mirror old');
    expect(otherFile.readAsStringSync(), 'focused tab old');
  });

  testWidgets('a refused save aborts the upload before it reads again', (
    tester,
  ) async {
    final sourceFile = File(path.join(workspace.path, 'a.py'))
      ..writeAsStringSync('old local');
    final otherFile = File(path.join(workspace.path, 'b.py'))
      ..writeAsStringSync('focused tab old');
    final compared = _FakeEditorController('new buffer');
    final focused = _FakeEditorController('focused buffer');
    final comparedTab = tabFor(
      sourceFile,
      compared,
      isSaved: false,
      readOnly: true,
    );
    final focusedTab = tabFor(otherFile, focused, isSaved: false);

    final container = containerWith({sourceFile.path: compared});
    container.read(fileProvider.notifier).setDirectory(workspace);
    final notifier = container.read(fileProvider.notifier) as _TestFileNotifier;
    var reads = 0;
    notifier.localTextReader = (sourcePath) async {
      reads++;
      return File(sourcePath).readAsStringSync();
    };
    openTabs(container, [comparedTab, focusedTab], focused: focusedTab);
    await pumpShell(tester, container);

    final context = tester.element(find.byType(Scaffold));
    unawaited(
      notifier.uploadSelectedLocalFileItem(context, selectedTab: comparedTab),
    );
    await pumpUntil(
      tester,
      () =>
          find.text(I18nKey.dialogEditorContent.fallback).evaluate().isNotEmpty,
    );
    await tester.tap(find.text(I18nKey.dialogEditorContent.fallback));
    await pumpUntil(tester, () => false, frames: 200);

    expect(reads, 1);
    expect(backend.uploads, isEmpty);
    expect(sourceFile.readAsStringSync(), 'old local');
    expect(otherFile.readAsStringSync(), 'focused tab old');
  });
}
