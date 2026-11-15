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
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:tabbed_view/src/tab_data.dart';

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

class _TestFileNotifier extends FileNotifier {
  _TestFileNotifier(super.ref);

  int writes = 0;

  @override
  Future<void> writeTabText(TabDataValue value, String text) async {
    writes++;
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

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 500 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pyrite_undecodable_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  testWidgets('an undecodable disk file is not prompted for twice and a save '
      'is refused with a message', (tester) async {
    final file = File('${dir.path}${Platform.pathSeparator}binary.dat')
      ..writeAsBytesSync([0xff, 0xfe, 0x00, 0x01]);
    final controller = _FakeEditorController('buffer\n');
    final tab = TabData(
      text: 'binary.dat',
      value: TabDataValue(
        type: 'file',
        filePath: file.path,
        file: file,
        editorController: controller,
        isSaved: false,
      ),
    );
    final container = _container();
    final notifier = container.read(fileProvider.notifier) as _TestFileNotifier;
    final editor = container.read(tabbedViewControllerProvider.notifier);
    editor.diskStampReader = (file) async =>
        FileDiskStamp(modified: DateTime.utc(2026, 1, 1), size: 4);
    editor.diskTextReader = (file) async => null;
    await _pumpShell(tester, container);

    final reload = find.text(I18nKey.editorFileChangedOnDiskReload.fallback);

    // First save: the conflict prompt appears; reload cannot decode the bytes.
    final firstSave = notifier.saveTab(tab);
    await _pumpUntilFound(tester, reload);
    expect(reload, findsOneWidget);

    await tester.tap(reload);
    await tester.pumpAndSettle();

    expect(await firstSave, isFalse);
    expect(notifier.writes, 0);
    expect(file.readAsBytesSync(), [0xff, 0xfe, 0x00, 0x01]);
    final messages = container.read(ideMessageProvider);
    expect(
      messages.where((entry) => entry.message.contains('无法作为文本读取')),
      hasLength(1),
    );

    // Second save: the same bytes must not reopen the prompt, but the refusal
    // is still reported.
    final secondSave = notifier.saveTab(tab);
    await tester.pumpAndSettle();

    expect(reload, findsNothing);
    expect(await secondSave, isFalse);
    expect(notifier.writes, 0);
    expect(
      container
          .read(ideMessageProvider)
          .where((entry) => entry.message.contains('无法作为文本读取')),
      hasLength(1),
    );

    // Let the warning's dismissal timer run out inside the test zone.
    await tester.pump(const Duration(seconds: 13));
  });
}
