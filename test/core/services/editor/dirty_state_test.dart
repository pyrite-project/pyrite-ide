import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';

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
}
