import 'package:code_forge/code_forge/syntax_highlighter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_highlight/languages/python.dart';

const Map<String, TextStyle> _theme = <String, TextStyle>{
  'root': TextStyle(color: Color(0xFFCCCCCC)),
  'string': TextStyle(color: Color(0xFF6A9FB5)),
  'comment': TextStyle(color: Color(0xFF5C6370)),
  'keyword': TextStyle(color: Color(0xFFC678DD)),
  'title': TextStyle(color: Color(0xFFE5C07B)),
};

SyntaxHighlighter _highlighterOver(List<String> lines) {
  final highlighter = SyntaxHighlighter(
    language: langPython,
    editorTheme: _theme,
    languageId: 'python',
  );
  highlighter.attachLineTextProvider((index) => lines[index]);
  return highlighter;
}

/// Flattens a span tree into `(text, colour)` pairs, so a test can ask which
/// colour a given stretch of a line was painted.
List<(String, Color?)> _flatten(TextSpan? span, [Color? inherited]) {
  if (span == null) return const [];
  final TextStyle? style = span.style;
  final Color? color = style?.color ?? inherited;
  final result = <(String, Color?)>[];

  if (span.text != null && span.text!.isNotEmpty) {
    result.add((span.text!, color));
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) {
      result.addAll(_flatten(child, color));
    }
  }
  return result;
}

/// The colour the text in `[needle]` was painted on a line, or `null` when the
/// line does not contain it.
Color? _colorOf(TextSpan? span, String needle) {
  final runs = _flatten(span);
  for (final run in runs) {
    if (run.$1.contains(needle)) return run.$2;
  }
  return null;
}

void main() {
  group('multi-line strings in the highlighter', () {
    // Regression: a line in the middle of a triple-quoted string was re-read as
    // standalone code, so words in a docstring picked up keyword and title
    // colours. The whole construct has to paint as one string instead.
    test('a docstring body line paints entirely as string', () {
      const lines = [
        '"""',
        'class CircuitPython firmware for the supported boards',
        '"""',
      ];
      final highlighter = _highlighterOver(lines);

      final span = highlighter.getLineSpan(1, lines[1]);

      expect(_colorOf(span, 'class'), _theme['string']!.color);
      expect(_colorOf(span, 'for'), _theme['string']!.color);
      expect(_colorOf(span, 'firmware'), _theme['string']!.color);
      expect(_colorOf(span, 'boards'), _theme['string']!.color);
    });

    test('the keywords in a docstring are not painted as code', () {
      const lines = ['"""', 'if else def class return', '"""'];
      final highlighter = _highlighterOver(lines);

      final span = highlighter.getLineSpan(1, lines[1]);

      for (final keyword in ['if', 'else', 'def', 'class', 'return']) {
        expect(
          _colorOf(span, keyword),
          _theme['string']!.color,
          reason: '`$keyword` sits inside a docstring',
        );
      }
      expect(
        _flatten(span).map((run) => run.$2).toSet(),
        isNot(contains(_theme['keyword']!.color)),
        reason: 'no stretch of a docstring body may carry a keyword colour',
      );
    });

    test('code outside the docstring keeps its own colours', () {
      const lines = ['"""', 'body', '"""', 'def f():', '    pass'];
      final highlighter = _highlighterOver(lines);

      expect(
        _colorOf(highlighter.getLineSpan(3, lines[3]), 'def'),
        _theme['keyword']!.color,
      );
      expect(
        _colorOf(highlighter.getLineSpan(4, lines[4]), 'pass'),
        _theme['keyword']!.color,
      );
    });

    test('the delimiters themselves are string coloured', () {
      const lines = ['"""', 'body', '"""'];
      final highlighter = _highlighterOver(lines);

      expect(
        _colorOf(highlighter.getLineSpan(0, lines[0]), '"""'),
        _theme['string']!.color,
      );
      expect(
        _colorOf(highlighter.getLineSpan(2, lines[2]), '"""'),
        _theme['string']!.color,
      );
    });

    test('a blank line inside a docstring is string coloured', () {
      const lines = ['"""', '', 'body', '"""'];
      final highlighter = _highlighterOver(lines);

      final span = highlighter.getLineSpan(1, '');
      expect(span == null || _flatten(span).isEmpty, isTrue);
    });

    test('a slice of a docstring body is string coloured', () {
      const lines = ['"""', 'a long body of words here', '"""'];
      final highlighter = _highlighterOver(lines);

      // The magnifier and selection previews render substrings, so the slice
      // has to be coloured from the whole line's ranges.
      const offset = 7;
      final slice = lines[1].substring(offset);
      final span = highlighter.getLineSpan(1, slice, textOffset: offset);

      expect(_colorOf(span, 'body'), _theme['string']!.color);
    });

    test('an edit that adds a delimiter repaints the lines under it', () {
      final lines = <String>['text', 'more text'];
      final highlighter = _highlighterOver(lines);

      expect(
        _colorOf(highlighter.getLineSpan(1, lines[1]), 'text'),
        isNot(_theme['string']!.color),
      );

      lines
        ..insert(0, '"""')
        ..add('"""');
      highlighter.invalidateLines({0});

      final span = highlighter.getLineSpan(2, lines[2]);
      expect(_colorOf(span, 'more'), _theme['string']!.color);
    });

    test('an edit that removes a delimiter stops repainting', () {
      final lines = <String>['"""', 'body', '"""'];
      final highlighter = _highlighterOver(lines);

      expect(
        _colorOf(highlighter.getLineSpan(1, lines[1]), 'body'),
        _theme['string']!.color,
      );

      lines
        ..removeAt(0)
        ..removeLast();
      highlighter.invalidateLines({0});

      final span = highlighter.getLineSpan(0, lines[0]);
      expect(_colorOf(span, 'body'), isNot(_theme['string']!.color));
    });

    test('an ordinary single-quoted string is untouched', () {
      const lines = ["s = 'class def'", 't = 2'];
      final highlighter = _highlighterOver(lines);

      final span = highlighter.getLineSpan(0, lines[0]);
      expect(
        _colorOf(span, 'class'),
        _theme['string']!.color,
        reason: 'the grammar already painted this as a string',
      );
    });

    test('a hash comment after a closed string stays a comment', () {
      const lines = ['x = 1  # class', 'y = 2'];
      final highlighter = _highlighterOver(lines);

      final span = highlighter.getLineSpan(0, lines[0]);
      expect(
        _colorOf(span, 'class'),
        _theme['comment']!.color,
        reason: 'a comment is not a multi-line construct',
      );
    });

    test('a line index below zero is harmless', () {
      const lines = ['"""', 'body', '"""'];
      final highlighter = _highlighterOver(lines);
      expect(highlighter.getLineSpan(-1, 'body'), isNotNull);
    });

    test('a language with no multi-line construct is left alone', () {
      final highlighter = SyntaxHighlighter(
        language: langPython,
        editorTheme: _theme,
        languageId: 'json',
      );
      // No provider is attached, so the tracker stays inert and the grammar
      // keeps painting every line on its own terms.
      expect(highlighter.getLineSpan(0, '"""'), isNotNull);
    });
  });
}
