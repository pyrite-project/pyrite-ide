import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor/external_file_change.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:tabbed_view/src/tab_data.dart';

/// A controller stand-in with just the buffer and read-only flag the save
/// path touches. The real controller needs the Rust rope initialized.
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
      throw UnsupportedError('not read by the save path: $invocation');
}

/// Records how many times the bytes actually reached the writer and lets the
/// test run code in the middle of the write, the way a user typing while a
/// slow save is in flight would.
class _TestFileNotifier extends FileNotifier {
  _TestFileNotifier(super.ref);

  int writes = 0;
  void Function()? beforeWrite;

  @override
  Future<void> writeTabText(TabDataValue value, String text) async {
    writes++;
    beforeWrite?.call();
    // Synchronous on purpose: the widget tests run under fake async, where a
    // real file write's completion would never be delivered.
    value.file!.writeAsStringSync(text);
  }
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [fileProvider.overrideWith(_TestFileNotifier.new)],
  );
  addTearDown(container.dispose);
  return container;
}

/// Feeds the reconciliation the disk state the tests are pretending is there,
/// instead of reading the real file inside the fake-async zone.
void _stubDisk(ProviderContainer container, String text) {
  final editor = container.read(tabbedViewControllerProvider.notifier);
  editor.diskStampReader = (file) async =>
      FileDiskStamp(modified: DateTime.utc(2026, 1, 1), size: text.length);
  editor.diskTextReader = (file) async => text;
}

TabData _tab(
  File file,
  _FakeEditorController controller, {
  required bool isSaved,
}) => TabData(
  text: file.uri.pathSegments.last,
  value: TabDataValue(
    type: 'file',
    filePath: file.path,
    file: file,
    editorController: controller,
    isSaved: isSaved,
  ),
);

Future<void> _pumpShell(WidgetTester tester, ProviderContainer container) {
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

/// Pumps frames until [finder] matches, e.g. while the save path reads the
/// disk before raising its conflict dialog.
Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 500 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pyrite_save_consistency_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('content typed while the bytes are written stays unsaved', () async {
    final file = File('${dir.path}${Platform.pathSeparator}slow.py')
      ..writeAsStringSync('');
    final controller = _FakeEditorController('written');
    final value = TabDataValue(
      type: 'file',
      filePath: file.path,
      file: file,
      editorController: controller,
      isSaved: true,
    );
    final tab = TabData(text: 'slow.py', value: value);
    final container = _container();
    final notifier = container.read(fileProvider.notifier) as _TestFileNotifier;
    notifier.beforeWrite = () => controller.text = 'written typed';

    final saved = await notifier.saveTab(tab);

    expect(saved, isTrue);
    // What reached the disk is what was captured before the await; the
    // characters typed during the write are not part of it.
    expect(file.readAsStringSync(), 'written');
    expect(value.isSaved, isFalse);
  });

  testWidgets('keeping the editor content writes the buffer on save', (
    tester,
  ) async {
    final file = File('${dir.path}${Platform.pathSeparator}keep.py')
      ..writeAsStringSync('disk\n');
    final controller = _FakeEditorController('buffer\n');
    final tab = _tab(file, controller, isSaved: false);
    final container = _container();
    final notifier = container.read(fileProvider.notifier) as _TestFileNotifier;
    _stubDisk(container, 'disk\n');
    await _pumpShell(tester, container);

    final keep = find.text(I18nKey.editorFileChangedOnDiskKeep.fallback);
    final save = notifier.saveTab(tab);
    await _pumpUntilFound(tester, keep);
    expect(keep, findsOneWidget);

    await tester.tap(keep);
    await tester.pumpAndSettle();

    // The very save that raised the prompt has to write the buffer, and it
    // must do so exactly once.
    expect(await save, isTrue);
    expect(file.readAsStringSync(), 'buffer\n');
    expect(notifier.writes, 1);
    expect((tab.value as TabDataValue).isSaved, isTrue);
  });

  testWidgets('cancelling the save conflict leaves the disk untouched', (
    tester,
  ) async {
    final file = File('${dir.path}${Platform.pathSeparator}cancel.py')
      ..writeAsStringSync('disk\n');
    final controller = _FakeEditorController('buffer\n');
    final tab = _tab(file, controller, isSaved: false);
    final container = _container();
    final notifier = container.read(fileProvider.notifier) as _TestFileNotifier;
    _stubDisk(container, 'disk\n');
    await _pumpShell(tester, container);

    final cancel = find.text(I18nKey.commonCancel.fallback);
    final save = notifier.saveTab(tab);
    await _pumpUntilFound(tester, cancel);
    expect(cancel, findsOneWidget);

    await tester.tap(cancel);
    await tester.pumpAndSettle();

    expect(await save, isFalse);
    expect(file.readAsStringSync(), 'disk\n');
    expect(notifier.writes, 0);
    expect((tab.value as TabDataValue).isSaved, isFalse);
  });
}
