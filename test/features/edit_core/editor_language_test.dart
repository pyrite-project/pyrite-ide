import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/edit_core/editor_language.dart';

void main() {
  group('resolveEditorLanguage', () {
    test('picks the grammar from the file extension', () {
      expect(resolveEditorLanguage('/p/main.py').id, 'python');
      expect(resolveEditorLanguage('/p/config.json').id, 'json');
      expect(resolveEditorLanguage('/p/README.md').id, 'markdown');
      expect(resolveEditorLanguage('/p/values.yaml').id, 'yaml');
      expect(resolveEditorLanguage('/p/values.yml').id, 'yaml');
      expect(resolveEditorLanguage('/p/modemenu.h').id, 'c');
      expect(resolveEditorLanguage('/p/umqtt.c').id, 'c');
      expect(resolveEditorLanguage('/p/build.sh').id, 'shell');
      expect(resolveEditorLanguage('/p/pyproject.toml').id, 'ini');
      expect(resolveEditorLanguage('/p/index.html').id, 'xml');
    });

    test('is case insensitive', () {
      expect(resolveEditorLanguage('/p/MAIN.PY').id, 'python');
      expect(resolveEditorLanguage('/p/Config.JSON').id, 'json');
    });

    test('falls back to Python for unknown, missing or empty paths', () {
      expect(resolveEditorLanguage('/p/main.pyc').id, 'python');
      expect(resolveEditorLanguage('/p/Makefile').id, 'python');
      expect(resolveEditorLanguage('/p/noextension').id, 'python');
      expect(resolveEditorLanguage('').id, 'python');
      expect(resolveEditorLanguage(null).id, 'python');
    });

    test('reuses one Mode instance per grammar', () {
      // SyntaxHighlighter keys its cache on the Mode's hash code, so handing
      // out shared instances avoids re-registering a grammar per tab.
      expect(
        identical(
          resolveEditorLanguage('/a/one.py').mode,
          resolveEditorLanguage('/b/two.py').mode,
        ),
        isTrue,
      );
    });
  });
}
