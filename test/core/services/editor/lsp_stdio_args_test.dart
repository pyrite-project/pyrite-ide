import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stdio_args.dart';

void main() {
  group('splitLspStdioArgs', () {
    test('splits a plain command line on runs of whitespace', () {
      expect(splitLspStdioArgs('  --stdio   --check  '), [
        '--stdio',
        '--check',
      ]);
    });

    test('returns no arguments for an empty or blank line', () {
      expect(splitLspStdioArgs(''), isEmpty);
      expect(splitLspStdioArgs('  \t '), isEmpty);
    });

    test('keeps a double-quoted path containing spaces as one argument', () {
      expect(splitLspStdioArgs('--config "C:/my dir/pyrightconfig.json"'), [
        '--config',
        'C:/my dir/pyrightconfig.json',
      ]);
    });

    test('keeps a single-quoted argument together', () {
      expect(splitLspStdioArgs("'a b' c"), ['a b', 'c']);
    });

    test('joins a quoted run that follows literal text', () {
      expect(splitLspStdioArgs('--name=foo-"bar baz"'), ['--name=foo-bar baz']);
    });

    test('unescapes a quoted double quote', () {
      expect(splitLspStdioArgs(r'"a \"quoted\" word"'), ['a "quoted" word']);
    });

    test('keeps Windows path separators inside double quotes', () {
      // Only \", \\ and \$ are escapes inside double quotes; a backslash before
      // an ordinary character is part of the path.
      expect(
        splitLspStdioArgs(r'--config "C:\Users\me\pyrightconfig.json"'),
        ['--config', r'C:\Users\me\pyrightconfig.json'],
      );
    });

    test('unescapes a quoted dollar and a quoted backslash', () {
      expect(splitLspStdioArgs(r'"a \$b"'), [r'a $b']);
      expect(splitLspStdioArgs(r'"a \\ b"'), [r'a \ b']);
    });

    test('keeps a trailing backslash inside an unterminated quote', () {
      expect(splitLspStdioArgs('"C:\\dir\\'), ['C:\\dir\\']);
    });

    test('treats a backslash outside quotes as an escape', () {
      expect(splitLspStdioArgs(r'a\ b'), ['a b']);
    });

    test('keeps a trailing backslash as a literal backslash', () {
      expect(splitLspStdioArgs(r'path\'), [r'path\']);
    });

    test('does not throw on an unterminated quote', () {
      expect(splitLspStdioArgs('--config "unterminated dir'), [
        '--config',
        'unterminated dir',
      ]);
    });

    test('does not expand variables or globs', () {
      expect(splitLspStdioArgs(r'$HOME/*.py'), [r'$HOME/*.py']);
    });
  });
}
