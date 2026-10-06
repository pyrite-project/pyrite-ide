import 'package:code_forge/code_forge/syntax_highlighter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/edit_core/minimap_highlight.dart';
import 'package:re_highlight/languages/python.dart';

/// A theme small enough to reason about: every scope the tests need and
/// nothing else, so a color in an assertion always came from where it was put.
Map<String, TextStyle> _theme() => <String, TextStyle>{
  'root': const TextStyle(color: Color(0xFFD4D4D4)),
  'keyword': const TextStyle(color: Color(0xFFC586C0)),
  'string': const TextStyle(color: Color(0xFFCE9178)),
  'comment': const TextStyle(color: Color(0xFF6A9955)),
  'number': const TextStyle(color: Color(0xFFB5CEA8)),
};

void main() {
  const plain = Color(0xFF9CDCFE);
  final theme = _theme();
  Color scope(String key) => theme[key]!.color!;

  group('minimapColorSpans', () {
    test('an unstyled line is one stretch of the plain color', () {
      expect(minimapColorSpans(null, 'hello', plainColor: plain), [
        MinimapColorSpan(0, 5, plain),
      ]);
    });

    test('an empty line has nothing to draw', () {
      expect(minimapColorSpans(null, '', plainColor: plain), isEmpty);
    });

    test('a styled parent covers every child, and equal runs merge', () {
      final spans = minimapColorSpans(
        TextSpan(
          style: TextStyle(color: scope('keyword')),
          children: [
            const TextSpan(text: 'def', style: TextStyle()),
            const TextSpan(text: ' f'),
          ],
        ),
        'def f',
        plainColor: plain,
      );

      // Both children resolve to the parent's color, so the line comes back as
      // one run — not a keyword run followed by a gap of plain text.
      expect(spans, [MinimapColorSpan(0, 5, scope('keyword'))]);
    });

    test('a run that stops short of the end is padded to the line', () {
      final spans = minimapColorSpans(
        TextSpan(
          text: 'ab',
          style: TextStyle(color: scope('number')),
        ),
        'abcdef',
        plainColor: plain,
      );

      expect(spans, [
        MinimapColorSpan(0, 2, scope('number')),
        MinimapColorSpan(2, 6, plain),
      ]);
    });

    test('merges neighbors that resolved to the same color', () {
      final spans = minimapColorSpans(
        TextSpan(
          children: [
            TextSpan(
              text: 're',
              style: TextStyle(color: scope('keyword')),
            ),
            TextSpan(
              text: 'turn',
              style: TextStyle(color: scope('keyword')),
            ),
            const TextSpan(text: ' x'),
          ],
        ),
        'return x',
        plainColor: plain,
      );

      expect(spans, [
        MinimapColorSpan(0, 6, scope('keyword')),
        MinimapColorSpan(6, 8, plain),
      ]);
    });

    test('a child inherits the nearest styled ancestor color', () {
      final spans = minimapColorSpans(
        TextSpan(
          children: [
            TextSpan(
              children: const [TextSpan(text: 'abc')],
              style: TextStyle(color: scope('string')),
            ),
          ],
        ),
        'abc',
        plainColor: plain,
      );

      expect(spans, [MinimapColorSpan(0, 3, scope('string'))]);
    });

    test('spans never overlap and never leave a hole', () {
      const line = 'def f(x):  # add two numbers';
      final spans = minimapColorSpans(
        TextSpan(
          text: 'def ',
          style: TextStyle(color: scope('root')),
          children: [
            TextSpan(
              text: 'def',
              style: TextStyle(color: scope('keyword')),
            ),
            const TextSpan(text: ' f('),
            TextSpan(
              text: '# add',
              style: TextStyle(color: scope('comment')),
            ),
            const TextSpan(text: ' two numbers'),
          ],
        ),
        line,
        plainColor: plain,
      );

      var position = 0;
      for (final span in spans) {
        expect(span.start, position, reason: 'a gap or overlap before $span');
        expect(span.end, greaterThan(span.start));
        position = span.end;
      }
      expect(position, line.length);
    });

    test('a run reaching back over its predecessor is trimmed, not stacked', () {
      // Malformed input — a span whose own text is re-covered by a later child
      // — still has to come back as one clean tiling, because every rect the
      // minimap draws is read off this list.
      final spans = minimapColorSpans(
        TextSpan(
          text: 'hi 42',
          style: TextStyle(color: scope('root')),
          children: [
            TextSpan(
              text: '42',
              style: TextStyle(color: scope('number')),
            ),
          ],
        ),
        'hi 42',
        plainColor: plain,
      );

      var position = 0;
      for (final span in spans) {
        expect(span.start, position, reason: 'a gap or overlap before $span');
        position = span.end;
      }
      expect(position, 'hi 42'.length);
    });
  });

  group('minimapColorSpans over a real grammar', () {
    late SyntaxHighlighter highlighter;

    setUp(() {
      highlighter = SyntaxHighlighter(language: langPython, editorTheme: theme)
        ..attachLineTextProvider((_) => '');
    });

    tearDown(() => highlighter.dispose());

    test('a python line comes back colored and fully covered', () {
      const line = 'def add(a, b):  # sum';
      final spans = minimapColorSpans(
        highlighter.getLineSpan(0, line),
        line,
        plainColor: const Color(0xFFFFFFFF),
      );

      var position = 0;
      for (final span in spans) {
        expect(span.start, position);
        position = span.end;
      }
      expect(position, line.length);
      // The keyword, the comment and the plain text between them are three
      // different colors; a minimap that flattened them into one would be no
      // better than the uncolored bar it replaces.
      expect(
        spans.map((span) => span.color).toSet().length,
        greaterThanOrEqualTo(3),
      );
    });

    test('an empty line yields no spans rather than an empty bar', () {
      expect(
        minimapColorSpans(
          highlighter.getLineSpan(0, ''),
          '',
          plainColor: const Color(0xFFFFFFFF),
        ),
        isEmpty,
      );
    });
  });

  group('withoutWhitespace', () {
    test('indentation is left as a gap', () {
      expect(
        withoutWhitespace([const MinimapColorSpan(0, 10, plain)], '    foo()'),
        [MinimapColorSpan(4, 9, plain)],
      );
    });

    test('a single space between words stays painted', () {
      expect(
        withoutWhitespace([const MinimapColorSpan(0, 7, plain)], 'def foo'),
        [MinimapColorSpan(0, 7, plain)],
      );
    });

    test('a run longer than two spaces opens a gap in the middle', () {
      expect(
        withoutWhitespace([const MinimapColorSpan(0, 12, plain)], 'a =    1'),
        [MinimapColorSpan(0, 3, plain), MinimapColorSpan(7, 8, plain)],
      );
    });

    test('a blank line has nothing left to draw', () {
      expect(
        withoutWhitespace([const MinimapColorSpan(0, 6, plain)], '      '),
        isEmpty,
      );
    });

    test('a span of only whitespace is dropped entirely', () {
      expect(
        withoutWhitespace([
          MinimapColorSpan(0, 3, scope('keyword')),
          MinimapColorSpan(3, 7, plain),
          MinimapColorSpan(7, 10, plain),
        ], 'def    foo'),
        [
          MinimapColorSpan(0, 3, scope('keyword')),
          MinimapColorSpan(7, 10, plain),
        ],
      );
    });

    test('a trailing single space stays painted, an inner run does not', () {
      // The threshold is about structure, not about tidiness: one space at the
      // end of a line is not indentation, and dropping it would shave a sliver
      // off every bar.
      expect(withoutWhitespace([const MinimapColorSpan(0, 4, plain)], 'def '), [
        MinimapColorSpan(0, 4, plain),
      ]);
    });

    test('tabs are gaps as well as spaces', () {
      expect(
        withoutWhitespace([const MinimapColorSpan(0, 5, plain)], '\t\tfoo'),
        [MinimapColorSpan(2, 5, plain)],
      );
    });

    test('a two-space indent is a gap but a one-space one is not', () {
      expect(
        withoutWhitespace([const MinimapColorSpan(0, 6, plain)], '  foo()'),
        [MinimapColorSpan(2, 6, plain)],
        reason: 'two spaces is the shortest run that counts as structure',
      );
      expect(
        withoutWhitespace([const MinimapColorSpan(0, 5, plain)], ' foo()'),
        [MinimapColorSpan(0, 5, plain)],
      );
    });

    test('the minRun threshold is adjustable', () {
      expect(
        withoutWhitespace(
          [const MinimapColorSpan(0, 5, plain)],
          ' foo()',
          minRun: 1,
        ),
        [MinimapColorSpan(1, 5, plain)],
      );
    });

    test('offsets survive, so callers still map the survivors correctly', () {
      final text = '    return x  # done';
      final kept = withoutWhitespace([
        const MinimapColorSpan(0, 19, plain),
      ], text);
      for (final span in kept) {
        expect(
          text.substring(span.start, span.end).trim(),
          isNotEmpty,
          reason:
              'a surviving span must cover at least one non-space character',
        );
        expect(text.substring(span.start, span.end), isNot(contains('  ')));
      }
    });

    test('an empty line has nothing to draw', () {
      expect(withoutWhitespace(const [], ''), isEmpty);
    });

    test('indented python keeps its colors and gains gaps', () {
      final highlighter = SyntaxHighlighter(
        language: langPython,
        editorTheme: theme,
      )..attachLineTextProvider((_) => '');
      const text = '    def foo(a, b):';
      final spans = withoutWhitespace(
        minimapColorSpans(
          highlighter.getLineSpan(0, text),
          text,
          plainColor: plain,
        ),
        text,
      );
      expect(
        spans.map((span) => span.color).toSet().length,
        greaterThanOrEqualTo(2),
        reason: 'the indent must not swallow the keyword color',
      );
      expect(spans.first.start, 4, reason: 'the leading indent is a gap');
      expect(
        spans.any((span) => span.end - span.start < 3),
        isFalse,
        reason: 'word-separating single spaces are kept, so no span is a dot',
      );
      highlighter.dispose();
    });
  });
}
