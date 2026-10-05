import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/repl_snippet.dart';

void main() {
  group('expandLspSnippet', () {
    test('returns null when there is no placeholder', () {
      expect(expandLspSnippet('foo(a, b)'), isNull);
    });

    test('replaces a numbered placeholder with its default', () {
      final result = expandLspSnippet(r'foo(${1:a})');
      expect(result, isNotNull);
      expect(result!.text, 'foo(a)');
    });

    test('selects the first placeholder so typing overwrites it', () {
      final result = expandLspSnippet(r'foo(${1:a}, ${2:b})')!;
      expect(result.text, 'foo(a, b)');
      // The selection must cover exactly the first default, not the whole
      // inserted text, or the user retypes the call they were offered.
      expect(result.selectionStart, 4);
      expect(result.selectionEnd, 5);
      expect(
        result.text.substring(result.selectionStart, result.selectionEnd),
        'a',
      );
    });

    test('expands an empty placeholder to nothing', () {
      final result = expandLspSnippet(r'foo(${1:})')!;
      expect(result.text, 'foo()');
      expect(result.selectionStart, result.selectionEnd);
    });

    test('drops later placeholders but keeps the first selection', () {
      final result = expandLspSnippet(r'${1:name}${2:}=${3:value}')!;
      expect(result.text, 'name=value');
      expect(result.selectionStart, 0);
      expect(result.selectionEnd, 4);
    });

    test(r'handles the bare $name form', () {
      final result = expandLspSnippet(r'foo($1)')!;
      expect(result.text, 'foo()');
    });

    test(r'a bare $ with no name is literal text', () {
      // `$5` is a legal tabstop, so it does expand; what has to stay literal is
      // a `$` that names nothing.
      expect(expandLspSnippet(r'trailing $'), isNull);
      expect(expandLspSnippet(r'price: $ 5'), isNull);
    });

    test('literal text around a placeholder is preserved', () {
      // The `$5` here is a tabstop that expands to nothing, so the result is
      // still valid Python rather than a literal `$5` the board would reject.
      final result = expandLspSnippet(r'cost $5 = ${1:amount}')!;
      expect(result.text, 'cost  = amount');
    });

    test(r'$ escape inserts a literal dollar sign', () {
      final result = expandLspSnippet(r'price = \$${1:amount}')!;
      expect(result.text, r'price = $amount');
      expect(result.selectionStart, 9);
    });

    test('a default containing braces is matched to the outer close', () {
      final result = expandLspSnippet(r'foo(${1:{"a": 1}})')!;
      expect(result.text, 'foo({"a": 1})');
    });

    test('an escaped colon does not start the default', () {
      final result = expandLspSnippet(r'foo(${1:a\:b})')!;
      expect(result.text, r'foo(a\:b)');
    });

    test('an unbalanced brace stays literal rather than eating the rest', () {
      expect(expandLspSnippet(r'foo(${1:a'), isNull);
    });

    test('an empty snippet expands to an empty string', () {
      expect(expandLspSnippet(''), isNull);
    });

    test('the produced text contains no snippet syntax', () {
      final result = expandLspSnippet(r'set(${1:pin}, ${2:value})$0')!;
      expect(result.text, contains('set('));
      expect(result.text, isNot(contains(r'${')));
      expect(result.text, isNot(contains(r'$0')));
    });
  });
}
