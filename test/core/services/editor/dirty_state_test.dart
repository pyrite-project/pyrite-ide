import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:tabbed_view/tabbed_view.dart';

/// The modified indicator is driven by [resolveDirtyState] rather than by
/// `contentVersion`, because a version bump does not imply an edit.
void main() {
  group('resolveDirtyState', () {
    test('marks a clean tab dirty when the buffer diverges', () {
      expect(
        resolveDirtyState(
          savedText: 'a = 1\n',
          currentText: 'a = 2\n',
          isSaved: true,
        ),
        isFalse,
      );
    });

    test('leaves a clean tab clean when the text is unchanged', () {
      // The case that regressed: a mutating API ran, so the version moved,
      // but the buffer came back with identical content.
      expect(
        resolveDirtyState(
          savedText: 'a = 1\n',
          currentText: 'a = 1\n',
          isSaved: true,
        ),
        isNull,
      );
    });

    test('clears the dot when an edit is undone back to the saved text', () {
      expect(
        resolveDirtyState(
          savedText: 'a = 1\n',
          currentText: 'a = 1\n',
          isSaved: false,
        ),
        isTrue,
      );
    });

    test('leaves a dirty tab dirty when still different from saved', () {
      expect(
        resolveDirtyState(
          savedText: 'a = 1\n',
          currentText: 'a = 2\n',
          isSaved: false,
        ),
        isNull,
      );
    });

    test('treats a reformat to identical bytes as unmodified', () {
      const saved = 'def f():\n    return 1\n';
      // A distinct String instance guards against the comparison degrading
      // into an identity check rather than a value comparison.
      expect(
        resolveDirtyState(
          savedText: saved,
          currentText: String.fromCharCodes(saved.codeUnits),
          isSaved: true,
        ),
        isNull,
      );
    });

    test('keeps the current flag when no baseline is known', () {
      // An unreadable file must not be guessed either way.
      expect(
        resolveDirtyState(
          savedText: null,
          currentText: 'anything',
          isSaved: true,
        ),
        isNull,
      );
      expect(
        resolveDirtyState(
          savedText: null,
          currentText: 'anything',
          isSaved: false,
        ),
        isNull,
      );
    });

    test('detects a whitespace-only difference as a real change', () {
      expect(
        resolveDirtyState(
          savedText: 'a = 1\n',
          currentText: 'a = 1 \n',
          isSaved: true,
        ),
        isFalse,
      );
    });
  });

  group('applyDirtyState (decision applied to the tab flag)', () {
    // The first cut of this fix tested only [resolveDirtyState], and shipped a
    // caller that branched on the returned `isSaved` flag as though it were a
    // "became dirty" flag. Both outcomes were inverted, so a genuine edit
    // marked the tab saved and the indicator went dark. These tests assert the
    // resulting flag, which is what the tab actually renders from.
    test('a real edit marks the tab unsaved', () {
      final tab = _fileTab('main.py');

      final changed = applyDirtyState(
        tab,
        savedText: 'a = 1\n',
        currentText: 'a = 2\n',
      );

      expect(changed, isTrue);
      expect((tab.value as TabDataValue).isSaved, isFalse);
    });

    test('an unchanged buffer leaves the tab saved', () {
      final tab = _fileTab('main.py');

      final changed = applyDirtyState(
        tab,
        savedText: 'a = 1\n',
        currentText: 'a = 1\n',
      );

      expect(changed, isFalse);
      expect((tab.value as TabDataValue).isSaved, isTrue);
    });

    test('undoing back to the saved text marks the tab saved again', () {
      final tab = _fileTab('main.py');
      applyDirtyState(tab, savedText: 'a = 1\n', currentText: 'a = 2\n');
      expect((tab.value as TabDataValue).isSaved, isFalse);

      final changed = applyDirtyState(
        tab,
        savedText: 'a = 1\n',
        currentText: 'a = 1\n',
      );

      expect(changed, isTrue);
      expect((tab.value as TabDataValue).isSaved, isTrue);
    });

    test('an already-dirty tab stays dirty without a second transition', () {
      final tab = _fileTab('main.py');
      applyDirtyState(tab, savedText: 'a = 1\n', currentText: 'a = 2\n');

      final changed = applyDirtyState(
        tab,
        savedText: 'a = 1\n',
        currentText: 'a = 3\n',
      );

      expect(changed, isFalse);
      expect((tab.value as TabDataValue).isSaved, isFalse);
    });

    test('a missing baseline never moves the flag', () {
      final clean = _fileTab('clean.py');
      expect(
        applyDirtyState(clean, savedText: null, currentText: 'edited\n'),
        isFalse,
      );
      expect((clean.value as TabDataValue).isSaved, isTrue);

      final dirty = _fileTab('dirty.py');
      applyDirtyState(dirty, savedText: 'a = 1\n', currentText: 'a = 2\n');
      expect(
        applyDirtyState(dirty, savedText: null, currentText: 'a = 3\n'),
        isFalse,
      );
      expect((dirty.value as TabDataValue).isSaved, isFalse);
    });
  });
}

TabData _fileTab(String filePath) {
  return TabData(
    text: filePath,
    value: TabDataValue(type: 'file', filePath: filePath),
  );
}
