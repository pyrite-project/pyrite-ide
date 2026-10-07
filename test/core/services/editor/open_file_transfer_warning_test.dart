import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:tabbed_view/tabbed_view.dart';

/// A stand-in for the editor controller that only provides what the reseed
/// reads (`text`). The real controller builds a Rust-backed rope, which is
/// not initialized in plain unit tests.

void main() {
  test('matches an open board tab by logical board path', () {
    final tabs = [
      _fileTab(
        filePath: path.join('cache', 'lib', 'main.py'),
        boardFilePath: '/lib/main.py',
      ),
    ];

    expect(
      findOpenFilesAffectedByTransfer(
        tabs,
        boardFiles: true,
        filePaths: ['/lib/main.py'],
      ),
      {'/lib/main.py'},
    );
  });

  test('local matching ignores board cache files', () {
    final sharedCachePath = path.join('cache', 'main.py');
    final tabs = [
      _fileTab(filePath: sharedCachePath, boardFilePath: '/main.py'),
      _fileTab(filePath: path.join('workspace', 'main.py')),
    ];

    expect(
      findOpenFilesAffectedByTransfer(
        tabs,
        boardFiles: false,
        filePaths: [sharedCachePath, path.join('workspace', 'main.py')],
      ),
      {path.join('workspace', 'main.py')},
    );
  });

  test('folder matching includes descendants but not sibling prefixes', () {
    final tabs = [
      _fileTab(filePath: path.join('workspace', 'lib', 'main.py')),
      _fileTab(filePath: path.join('workspace', 'library', 'main.py')),
    ];

    expect(
      findOpenFilesAffectedByTransfer(
        tabs,
        boardFiles: false,
        folderPaths: [path.join('workspace', 'lib')],
      ),
      {path.join('workspace', 'lib', 'main.py')},
    );
  });

  test('marks an overwritten open board tab as unsaved', () {
    final tab = _fileTab(
      filePath: path.join('cache', 'lib', 'main.py'),
      boardFilePath: '/lib/main.py',
    );

    final result = markOpenFilesAffectedByTransferUnsaved(
      [tab],
      boardFiles: true,
      filePaths: ['/lib/main.py'],
    );

    expect(result.affectedPaths, {'/lib/main.py'});
    expect(result.newlyUnsaved, isTrue);
    expect((tab.value as TabDataValue).isSaved, isFalse);
    expect(tab.leading, isNotNull);
  });

  test('marks all open local descendants but leaves unrelated tabs saved', () {
    final first = _fileTab(filePath: path.join('workspace', 'lib', 'first.py'));
    final second = _fileTab(
      filePath: path.join('workspace', 'lib', 'nested', 'second.py'),
    );
    final unrelated = _fileTab(
      filePath: path.join('workspace', 'other', 'third.py'),
    );

    final result = markOpenFilesAffectedByTransferUnsaved(
      [first, second, unrelated],
      boardFiles: false,
      folderPaths: [path.join('workspace', 'lib')],
    );

    expect(result.affectedPaths, {
      path.join('workspace', 'lib', 'first.py'),
      path.join('workspace', 'lib', 'nested', 'second.py'),
    });
    expect((first.value as TabDataValue).isSaved, isFalse);
    expect((second.value as TabDataValue).isSaved, isFalse);
    expect((unrelated.value as TabDataValue).isSaved, isTrue);
  });

  test('local overwrite does not dirty an open board cache tab', () {
    final cachePath = path.join('cache', 'main.py');
    final boardTab = _fileTab(filePath: cachePath, boardFilePath: '/main.py');

    final result = markOpenFilesAffectedByTransferUnsaved(
      [boardTab],
      boardFiles: false,
      filePaths: [cachePath],
    );

    expect(result.affectedPaths, isEmpty);
    expect(result.newlyUnsaved, isFalse);
    expect((boardTab.value as TabDataValue).isSaved, isTrue);
  });

  test('repeated overwrite keeps the tab unsaved without a new transition', () {
    final tab = _fileTab(filePath: path.join('workspace', 'main.py'));
    final targets = [path.join('workspace', 'main.py')];

    final first = markOpenFilesAffectedByTransferUnsaved(
      [tab],
      boardFiles: false,
      filePaths: targets,
    );
    final second = markOpenFilesAffectedByTransferUnsaved(
      [tab],
      boardFiles: false,
      filePaths: targets,
    );

    expect(first.newlyUnsaved, isTrue);
    expect(second.affectedPaths, targets.toSet());
    expect(second.newlyUnsaved, isFalse);
    expect((tab.value as TabDataValue).isSaved, isFalse);
  });

  test('reseeds an overwritten board tab baseline under its tab path', () {
    final cachePath = path.join('cache', 'lib', 'main.py');
    final tab = _fileTab(
      filePath: cachePath,
      boardFilePath: '/lib/main.py',
      controller: _FakeEditorController('buffer'),
    );

    final baselines = reseedOpenFileTransferBaselines(
      [tab],
      boardFiles: true,
      affectedPaths: {'/lib/main.py'},
    );

    // The unsaved listener diffs under the tab's `filePath`, not the board
    // path, so the reseed has to land there to have any effect.
    expect(baselines, {cachePath: 'buffer'});
  });

  test('reseeds an overwritten local tab baseline under its path', () {
    final filePath = path.join('workspace', 'main.py');
    final tab = _fileTab(
      filePath: filePath,
      controller: _FakeEditorController('buffer'),
    );

    final baselines = reseedOpenFileTransferBaselines(
      [tab],
      boardFiles: false,
      affectedPaths: {filePath},
    );

    expect(baselines, {filePath: 'buffer'});
  });

  test(
    'skips tabs the transfer did not touch and tabs without controllers',
    () {
      final affected = _fileTab(
        filePath: path.join('workspace', 'hit.py'),
        controller: _FakeEditorController('buffer'),
      );
      final unrelated = _fileTab(
        filePath: path.join('workspace', 'miss.py'),
        controller: _FakeEditorController('buffer'),
      );

      final baselines = reseedOpenFileTransferBaselines(
        [affected, unrelated],
        boardFiles: false,
        affectedPaths: {path.join('workspace', 'hit.py')},
      );

      expect(baselines.keys, [path.join('workspace', 'hit.py')]);
    },
  );

  testWidgets('saving an unsaved file tab restores its file icon', (
    tester,
  ) async {
    final tab = _fileTab(filePath: path.join('workspace', 'main.py'));
    markOpenFilesAffectedByTransferUnsaved(
      [tab],
      boardFiles: false,
      filePaths: [path.join('workspace', 'main.py')],
    );

    expect(markFileTabSaved(tab), isTrue);
    expect((tab.value as TabDataValue).isSaved, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) =>
              tab.leading!(context, TabStatus.selected) ??
              const SizedBox.shrink(),
        ),
      ),
    );

    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsNothing);
  });
}

TabData _fileTab({
  required String filePath,
  String? boardFilePath,
  CodeForgeController? controller,
}) {
  return TabData(
    text: path.basename(filePath),
    value: TabDataValue(
      type: 'file',
      filePath: filePath,
      isBoardFile: boardFilePath != null,
      boardFilePath: boardFilePath,
      editorController: controller,
    ),
  );
}

class _FakeEditorController implements CodeForgeController {
  _FakeEditorController(this.bufferText);

  final String bufferText;

  @override
  String get text => bufferText;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
