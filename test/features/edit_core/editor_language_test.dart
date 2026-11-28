import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/edit_core/editor_language.dart';
import 'package:re_highlight/re_highlight.dart';

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

  group('python grammar keyword classes', () {
    final highlight = Highlight()
      ..registerLanguage('python', resolveEditorLanguage('/p/main.py').mode);

    Set<String> scopesOf(String code, String word) {
      final scopes = <String>{};
      final recorder = _ScopeRecorder();
      highlight.highlight(code: code, language: 'python').render(recorder);
      for (final entry in recorder.textsByScope.entries) {
        if (entry.value.any((t) => t.trim() == word)) scopes.add(entry.key);
      }
      return scopes.isEmpty ? {'<none>'} : scopes;
    }

    test('peripherals carry the type scope, modules stay plain', () {
      final code = 'import machine\n'
          'from machine import Pin\n'
          'import utime\n'
          'led = Pin(2, Pin.OUT)\n'
          'net = network.WLAN(network.STA_IF)\n'
          'utime.sleep_ms(10)\n';
      // A module is imported, not built in — plain text, like every
      // conventional Python theme colors it.
      expect(scopesOf(code, 'machine'), {'<none>'});
      expect(scopesOf(code, 'utime'), {'<none>'});
      expect(scopesOf(code, 'network'), {'<none>'});
      expect(scopesOf(code, 'Pin'), contains('type'));
      expect(scopesOf(code, 'WLAN'), contains('type'));
    });

    test('stock keyword classes stay intact', () {
      final code = 'def f(x):\n'
          '    print(len(str(x)))\n'
          '    while x:\n'
          '        x -= 1\n';
      expect(scopesOf(code, 'def'), contains('keyword'));
      expect(scopesOf(code, 'while'), contains('keyword'));
      expect(scopesOf(code, 'print'), contains('built_in'));
      expect(scopesOf(code, 'len'), contains('built_in'));
      expect(scopesOf(code, 'str'), contains('built_in'));
    });

    test('self carries variable.language so themes can style it', () {
      final code = 'class A:\n'
          '    def b(self):\n'
          '        self.x = 1\n'
          '        return self\n';
      expect(scopesOf(code, 'self'), contains('variable.language'));
    });

    test('cls carries variable.language', () {
      final code = 'class A:\n'
          '    def b(cls):\n'
          '        return cls\n';
      expect(scopesOf(code, 'cls'), contains('variable.language'));
    });

    test('plain identifiers stay unstyled', () {
      final code = 'app = App()\napp.count = 1\n';
      expect(scopesOf(code, 'app'), {'<none>'});
      expect(scopesOf(code, 'count'), {'<none>'});
    });
  });
}

class _ScopeRecorder implements HighlightRenderer {
  final List<String> stack = [];
  final Map<String, List<String>> textsByScope = {};

  @override
  void openNode(DataNode node) {
    final scope = node.scope;
    if (scope != null) stack.add(scope);
  }

  @override
  void closeNode(DataNode node) {
    if (stack.isNotEmpty) stack.removeLast();
  }

  @override
  void addText(String text) {
    if (text.trim().isEmpty) return;
    final scope = stack.isEmpty ? '<root>' : stack.last;
    textsByScope.putIfAbsent(scope, () => []).add(text);
  }
}
