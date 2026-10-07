import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/shared/tabbed_view/unsaved_tab_guard.dart';
import 'package:tabbed_view/src/tab_data.dart';

/// Records the tabs handed to [FileNotifier.saveTab] instead of touching disk.
class _RecordingFileNotifier extends FileNotifier {
  _RecordingFileNotifier(super.ref, this.savedTabPaths);

  final List<String> savedTabPaths;

  @override
  Future<void> saveTab(TabData? tab) async {
    final value = tab?.value;
    if (value is TabDataValue) savedTabPaths.add(value.filePath);
  }
}

TabData _tab({required bool isSaved, String path = '/tmp/a.py'}) => TabData(
  text: path,
  value: TabDataValue(type: 'file', filePath: path, isSaved: isSaved),
);

/// Hosts a single button whose press runs [onPressed] with a live context, the
/// way the tab close button and the tab context menu do.
Widget _harness({
  required List<String> savedTabPaths,
  required void Function(BuildContext context) onPressed,
}) {
  return ProviderScope(
    overrides: [
      fileProvider.overrideWith(
        (ref) => _RecordingFileNotifier(ref, savedTabPaths),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onPressed(context),
            child: const Text('close'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('isTabUnsaved', () {
    test('reports only dirty file tabs', () {
      expect(isTabUnsaved(_tab(isSaved: false)), isTrue);
      expect(isTabUnsaved(_tab(isSaved: true)), isFalse);
      expect(
        isTabUnsaved(TabData(text: 'plugin', value: {'type': 'page'})),
        isFalse,
      );
    });
  });

  group('confirmCloseUnsavedTab', () {
    testWidgets('a clean tab closes without any dialog', (tester) async {
      final saved = <String>[];
      late Future<bool> result;

      await tester.pumpWidget(
        _harness(
          savedTabPaths: saved,
          onPressed: (context) =>
              result = confirmCloseUnsavedTab(context, _tab(isSaved: true)),
        ),
      );

      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();

      expect(await result, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(saved, isEmpty);
    });

    testWidgets('cancel aborts the close and leaves the tab dirty', (
      tester,
    ) async {
      final saved = <String>[];
      final tab = _tab(isSaved: false);
      late Future<bool> result;

      await tester.pumpWidget(
        _harness(
          savedTabPaths: saved,
          onPressed: (context) => result = confirmCloseUnsavedTab(context, tab),
        ),
      );

      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text(I18nKey.tabUnsavedDialogCancel.fallback));
      await tester.pumpAndSettle();

      expect(await result, isFalse);
      expect(isTabUnsaved(tab), isTrue);
      expect(saved, isEmpty);
    });

    testWidgets('discard closes without writing the file', (tester) async {
      final saved = <String>[];
      late Future<bool> result;

      await tester.pumpWidget(
        _harness(
          savedTabPaths: saved,
          onPressed: (context) =>
              result = confirmCloseUnsavedTab(context, _tab(isSaved: false)),
        ),
      );

      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(I18nKey.tabUnsavedDialogDiscard.fallback));
      await tester.pumpAndSettle();

      expect(await result, isTrue);
      expect(saved, isEmpty);
    });

    testWidgets('save writes the tab being closed, then allows the close', (
      tester,
    ) async {
      final saved = <String>[];
      late Future<bool> result;

      await tester.pumpWidget(
        _harness(
          savedTabPaths: saved,
          onPressed: (context) => result = confirmCloseUnsavedTab(
            context,
            _tab(isSaved: false, path: '/tmp/dirty.py'),
          ),
        ),
      );

      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(I18nKey.tabUnsavedDialogSave.fallback));
      await tester.pumpAndSettle();

      expect(await result, isTrue);
      // The tab being closed is saved, not whichever one happens to be active.
      expect(saved, ['/tmp/dirty.py']);
    });
  });
}
