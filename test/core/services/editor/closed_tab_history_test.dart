import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/closed_tab_history.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:tabbed_view/tabbed_view.dart';

/// A controller that only has what closing and capturing read: the buffer and
/// its selection. The real controller builds a Rust-backed rope.
class _FakeEditorController implements CodeForgeController {
  @override
  String text = '';

  @override
  TextSelection selection = const TextSelection(
    baseOffset: -1,
    extentOffset: -1,
  );

  @override
  int get length => text.length;

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not read by the closed-tab capture: $invocation');
}

ClosedTabRecord _record(
  String path, {
  String text = 'buffer',
  String? savedText = 'saved',
  bool isSaved = true,
  String? encoding = 'utf8',
  bool byteOrderMark = false,
  int? caretOffset = 0,
}) => ClosedTabRecord(
  path: path,
  text: text,
  savedText: savedText,
  isSaved: isSaved,
  encoding: encoding,
  byteOrderMark: byteOrderMark,
  caretOffset: caretOffset,
);

TabData _fileTab(
  String path, {
  required CodeForgeController controller,
  bool isSaved = true,
  bool isBoardFile = false,
  String? encoding,
  bool byteOrderMark = false,
}) => TabData(
  text: path.split('/').last,
  value: TabDataValue(
    type: 'file',
    filePath: path,
    editorController: controller,
    isSaved: isSaved,
    isBoardFile: isBoardFile ? true : null,
    encoding: encoding,
    byteOrderMark: byteOrderMark,
  ),
);

void main() {
  group('ClosedTabHistory', () {
    test('keeps records newest first', () {
      final history = ClosedTabHistory()
        ..push(_record('/a.py'))
        ..push(_record('/b.py'));

      expect(history.records.map((record) => record.path), ['/b.py', '/a.py']);
      expect(history.newest?.path, '/b.py');
      expect(history.length, 2);
      expect(history.isNotEmpty, isTrue);
    });

    test('dedupes by path, keeping only the newest record', () {
      final history = ClosedTabHistory()
        ..push(_record('/a.py', text: 'old'))
        ..push(_record('/b.py'))
        ..push(_record('/a.py', text: 'new'));

      expect(history.records.map((record) => record.path), ['/a.py', '/b.py']);
      expect(history.newest?.text, 'new');
    });

    test('drops the oldest record past the cap', () {
      final history = ClosedTabHistory(maxLength: 3);
      for (var i = 0; i < 5; i++) {
        history.push(_record('/$i.py'));
      }

      expect(history.records.map((record) => record.path), [
        '/4.py',
        '/3.py',
        '/2.py',
      ]);
    });

    test('the default cap is ten', () {
      final history = ClosedTabHistory();
      for (var i = 0; i < 12; i++) {
        history.push(_record('/$i.py'));
      }

      expect(history.length, ClosedTabHistory.defaultMaxLength);
      expect(history.records.first.path, '/11.py');
      expect(history.records.last.path, '/2.py');
    });

    test('take removes and returns the newest record', () {
      final history = ClosedTabHistory()
        ..push(_record('/a.py'))
        ..push(_record('/b.py'));

      expect(history.take()?.path, '/b.py');
      expect(history.take()?.path, '/a.py');
      expect(history.take(), isNull);
      expect(history.isEmpty, isTrue);
    });

    test('removing forgets one path and reports whether it was there', () {
      final history = ClosedTabHistory()
        ..push(_record('/a.py'))
        ..push(_record('/b.py'));

      expect(history.remove('/a.py'), isTrue);
      expect(history.records.map((record) => record.path), ['/b.py']);
      expect(history.remove('/a.py'), isFalse);
    });

    test('clear forgets everything', () {
      final history = ClosedTabHistory()
        ..push(_record('/a.py'))
        ..push(_record('/b.py'));

      history.clear();

      expect(history.isEmpty, isTrue);
      expect(history.take(), isNull);
    });
  });

  group('capturing a closed tab', () {
    ProviderContainer newContainer() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container;
    }

    test(
      'records the buffer, saved baseline and caret before disposing',
      () async {
        final container = newContainer();
        final notifier = container.read(tabbedViewControllerProvider.notifier);
        final controller = _FakeEditorController()..text = 'saved text';
        const path = '/nonexistent/pyrite_closed_tab_capture/a.py';
        final tab = _fileTab(
          path,
          controller: controller,
          isSaved: true,
          encoding: 'gbk',
          byteOrderMark: true,
        );

        // Seed the saved baseline the way a save would.
        notifier.afterFileSave(tab);
        controller.text = 'edited text';
        controller.selection = const TextSelection.collapsed(offset: 4);
        (tab.value as TabDataValue).isSaved = false;

        await notifier.afterTabClose(tab);

        final record = container.read(closedTabHistoryProvider).records.single;
        expect(record.path, path);
        expect(record.text, 'edited text');
        expect(record.savedText, 'saved text');
        expect(record.isSaved, isFalse);
        expect(record.encoding, 'gbk');
        expect(record.byteOrderMark, isTrue);
        expect(record.caretOffset, 4);
      },
    );

    test('records a null caret when the selection was invalid', () async {
      final container = newContainer();
      final notifier = container.read(tabbedViewControllerProvider.notifier);
      final controller = _FakeEditorController()..text = 'text';
      final tab = _fileTab(
        '/nonexistent/pyrite_closed_tab_capture/b.py',
        controller: controller,
      );

      await notifier.afterTabClose(tab);

      expect(
        container.read(closedTabHistoryProvider).records.single.caretOffset,
        isNull,
      );
    });

    test('skips board files', () async {
      final container = newContainer();
      final notifier = container.read(tabbedViewControllerProvider.notifier);
      final tab = _fileTab(
        '/nonexistent/pyrite_closed_tab_capture/board.py',
        controller: _FakeEditorController()..text = 'board',
        isBoardFile: true,
      );

      await notifier.afterTabClose(tab);

      expect(container.read(closedTabHistoryProvider).isEmpty, isTrue);
    });

    test('skips git diffs and plugin views', () async {
      final container = newContainer();
      final notifier = container.read(tabbedViewControllerProvider.notifier);
      final diff = TabData(
        text: 'main.py · staged',
        value: TabDataValue(
          type: 'git_diff',
          filePath: 'git-diff:staged:/proj/main.py',
          editorController: _FakeEditorController()..text = 'diff',
        ),
      );
      final pluginView = TabData(
        text: 'Outline',
        value: TabDataValue(
          type: TabDataValue.pluginViewType,
          filePath: 'plugin://demo/outline#1',
          pluginId: 'demo',
          viewId: 'outline',
          viewInstanceId: '1',
          renderer: 'native.outline',
        ),
      );

      await notifier.afterTabClose(diff);
      await notifier.afterTabClose(pluginView);

      expect(container.read(closedTabHistoryProvider).isEmpty, isTrue);
    });

    test('a second close of the same path replaces the record', () async {
      final container = newContainer();
      final notifier = container.read(tabbedViewControllerProvider.notifier);
      const path = '/nonexistent/pyrite_closed_tab_capture/c.py';

      await notifier.afterTabClose(
        _fileTab(path, controller: _FakeEditorController()..text = 'first'),
      );
      await notifier.afterTabClose(
        _fileTab(path, controller: _FakeEditorController()..text = 'second'),
      );

      final history = container.read(closedTabHistoryProvider);
      expect(history.length, 1);
      expect(history.newest?.text, 'second');
    });
  });
}
