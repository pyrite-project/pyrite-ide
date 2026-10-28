import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/search/project_file_index.dart';
import 'package:pyrite_ide/features/command_palette/command_palette.dart';
import 'package:pyrite_ide/features/command_palette/palette_entry.dart';

PaletteEntry _entry(
  String id, {
  required String title,
  PaletteCategory category = PaletteCategory.command,
  bool enabled = true,
  void Function()? onSelect,
}) => PaletteEntry(
  id: id,
  title: title,
  category: category,
  enabled: enabled,
  onSelect: onSelect == null ? null : (context, ref) async => onSelect(),
);

/// Opens the palette the way the app does: through a dialog route, so the
/// tests exercise the real dismissal path.
///
/// [settle] is false when the palette shows a perpetual animation -- a loading
/// spinner never settles, so waiting for one would time out.
Future<void> _openPalette(
  WidgetTester tester, {
  required List<PaletteEntry> entries,
  PaletteLaunchMode mode = PaletteLaunchMode.commands,
  PaletteFileIndexState? fileIndexState,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showCommandPalette(
                  context,
                  entries: entries,
                  mode: mode,
                  fileIndexState: fileIndexState,
                ),
                child: const Text('open palette'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open palette'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Long enough for the dialog's transition to finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  testWidgets('lists entries and filters them as the user types', (
    tester,
  ) async {
    await _openPalette(
      tester,
      entries: [
        _entry('open', title: 'Open File'),
        _entry('save', title: 'Save File'),
      ],
    );

    expect(find.text('Open File'), findsOneWidget);
    expect(find.text('Save File'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'save');
    await tester.pumpAndSettle();

    expect(find.text('Open File'), findsNothing);
    expect(find.text('Save File'), findsOneWidget);
  });

  testWidgets('arrow keys move the selection and enter runs it', (
    tester,
  ) async {
    var opened = 0;
    var saved = 0;
    await _openPalette(
      tester,
      entries: [
        _entry('open', title: 'Open File', onSelect: () => opened++),
        _entry('save', title: 'Save File', onSelect: () => saved++),
      ],
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(saved, 1);
    expect(opened, 0);
    // Running an entry closes the palette.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('escape closes the palette without running anything', (
    tester,
  ) async {
    var runs = 0;
    await _openPalette(
      tester,
      entries: [_entry('open', title: 'Open File', onSelect: () => runs++)],
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(runs, 0);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a disabled entry is listed but cannot be run', (tester) async {
    var runs = 0;
    await _openPalette(
      tester,
      entries: [
        _entry(
          'split',
          title: 'Split Editor',
          enabled: false,
          onSelect: () => runs++,
        ),
      ],
    );

    expect(find.text('Split Editor'), findsOneWidget);
    await tester.tap(find.text('Split Editor'));
    await tester.pumpAndSettle();

    expect(runs, 0);
    // Still open: a disabled row does not dismiss the palette.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a file index still loading reports progress', (tester) async {
    await _openPalette(
      tester,
      entries: [_entry('open', title: 'Open File')],
      fileIndexState: PaletteFileIndexState.loading(),
      settle: false,
    );

    expect(find.text('正在索引项目文件…'), findsOneWidget);
  });

  testWidgets('a failed file index offers a retry that re-runs the scan', (
    tester,
  ) async {
    var retried = 0;
    await _openPalette(
      tester,
      entries: [_entry('open', title: 'Open File')],
      fileIndexState: PaletteFileIndexState.failure(
        const FileSystemException('nope'),
        onRetry: () => retried++,
      ),
    );

    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(retried, 1);
  });

  testWidgets('a > query hides project files', (tester) async {
    await _openPalette(
      tester,
      mode: PaletteLaunchMode.files,
      entries: [_entry('save', title: 'Save File')],
      fileIndexState: PaletteFileIndexState.ready(const [
        ProjectFileEntry(
          path: '/project/lib/save.py',
          relativePath: 'lib/save.py',
          name: 'save.py',
        ),
      ]),
    );

    expect(find.text('save.py'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '> save');
    await tester.pumpAndSettle();

    expect(find.text('save.py'), findsNothing);
    expect(find.text('Save File'), findsOneWidget);
  });
}
