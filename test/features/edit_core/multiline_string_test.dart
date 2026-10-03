import 'package:code_forge/code_forge/multiline_string.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/python.dart';

/// Builds a tracker over a fixed document.
MultilineStringTracker _trackerOver(List<String> lines, String? languageId) {
  final spec = resolveMultilineStringSpec(
    languageId: languageId,
    modeName: null,
  )!;
  final tracker = MultilineStringTracker(spec);
  tracker.lineText = (index) =>
      index >= 0 && index < lines.length ? lines[index] : '';
  return tracker;
}

List<MultilineStringRange> _ranges(
  MultilineStringTracker tracker,
  List<String> lines,
  int line,
) => tracker.rangesForLine(line, (i) => lines[i]);

void main() {
  group('resolveMultilineStringSpec', () {
    test('maps the languages the editor opens files as', () {
      expect(resolveMultilineStringSpec(languageId: 'python'), isNotNull);
      expect(resolveMultilineStringSpec(modeName: 'Python'), isNotNull);
      expect(resolveMultilineStringSpec(modeName: 'C++'), isNotNull);
      expect(resolveMultilineStringSpec(modeName: 'JavaScript'), isNotNull);
    });

    test('leaves languages without a known multi-line construct alone', () {
      // A null spec must leave highlighting exactly as it was before, so an
      // unlisted language is never at risk of being repainted wrongly.
      expect(resolveMultilineStringSpec(languageId: 'json'), isNull);
      expect(resolveMultilineStringSpec(modeName: 'JSON'), isNull);
      expect(resolveMultilineStringSpec(), isNull);
    });
  });

  group('python docstrings', () {
    test('a body line is one stretch of string', () {
      // The reported case: a line in the middle of a docstring used to be
      // re-read as standalone code, so its words got code colours.
      const lines = [
        '"""',
        '`adafruit_framebuf`',
        '============',
        'CircuitPython pure-python framebuf module.',
        '"""',
      ];
      final tracker = _trackerOver(lines, 'python');

      for (var line = 1; line <= 3; line++) {
        final ranges = _ranges(tracker, lines, line);
        expect(ranges, hasLength(1), reason: 'line $line');
        expect(ranges.single.start, 0, reason: 'line $line');
        expect(
          ranges.single.end,
          lines[line].length,
          reason: 'line $line covers the whole line',
        );
        expect(ranges.single.scopeKey, 'string', reason: 'line $line');
      }
    });

    test('the opener line is string from the opener onward', () {
      const lines = ['x = """start', 'middle', 'end"""'];
      final tracker = _trackerOver(lines, 'python');

      final first = _ranges(tracker, lines, 0);
      expect(first, hasLength(1));
      expect(first.single.start, lines[0].indexOf('"""'));
      // The line ends inside the string, so the rest of it is string too.
      expect(first.single.end, lines[0].length);
    });

    test('the closer line is string up to and including the closer', () {
      const lines = ['"""start', 'middle', 'end"""'];
      final tracker = _trackerOver(lines, 'python');

      final last = _ranges(tracker, lines, 2);
      expect(last, hasLength(1));
      // The construct was opened on an earlier line, so the whole line
      // belongs to it, delimiters included.
      expect(last.single.start, 0);
      expect(last.single.end, lines[2].length);
    });

    test('text after a closer on the same line is code again', () {
      const lines = ['"""a""" + b', 'c'];
      final tracker = _trackerOver(lines, 'python');

      final first = _ranges(tracker, lines, 0);
      expect(first, hasLength(1));
      expect(first.single.start, 0);
      //  sits between the delimiters, so the string ends at index 7.
      expect(first.single.end, 7);
      // The construct closed on this line, so the line below is plain code.
      expect(_ranges(tracker, lines, 1), isEmpty);
    });

    test('a blank line inside a docstring is still string', () {
      const lines = ['"""', '', 'text', '"""'];
      final tracker = _trackerOver(lines, 'python');

      expect(_ranges(tracker, lines, 1), hasLength(1));
      expect(_ranges(tracker, lines, 1).single.end, 0);
    });

    test('an apostrophe in a body line does not open a string', () {
      const lines = ['"""', "don't stop", '"""'];
      final tracker = _trackerOver(lines, 'python');

      final ranges = _ranges(tracker, lines, 1);
      expect(ranges, hasLength(1));
      expect(ranges.single.end, lines[1].length);
    });

    test('a hash in a body line stays inside the string', () {
      const lines = ['"""', 'a # b', '"""'];
      final tracker = _trackerOver(lines, 'python');

      expect(_ranges(tracker, lines, 1).single.end, lines[1].length);
    });

    test('a prefixed opener takes its specifier with it', () {
      const lines = ['f"""a', 'b', 'c"""'];
      final tracker = _trackerOver(lines, 'python');

      expect(_ranges(tracker, lines, 0).single.start, 0);
    });

    test('single-quoted strings are left to the grammar', () {
      const lines = ['s = "one"', 't = 2'];
      final tracker = _trackerOver(lines, 'python');

      expect(_ranges(tracker, lines, 0), isEmpty);
    });

    test('an apostrophe outside a string does not swallow the line', () {
      const lines = ["x = 'it\\'s'", 'y = 1'];
      final tracker = _trackerOver(lines, 'python');

      expect(_ranges(tracker, lines, 0), isEmpty);
    });

    test('a comment marker before a delimiter is not a delimiter', () {
      const lines = ['# a """ marker', 'code = 1'];
      final tracker = _trackerOver(lines, 'python');

      expect(_ranges(tracker, lines, 0), isEmpty);
      expect(_ranges(tracker, lines, 1), isEmpty);
    });

    test('a delimiter inside a comment does not open a string', () {
      const lines = ['# see """ below', 'code = 1', 'x = 2'];
      final tracker = _trackerOver(lines, 'python');

      expect(_ranges(tracker, lines, 1), isEmpty);
      expect(_ranges(tracker, lines, 2), isEmpty);
    });

    test('code before a docstring on the same line stays code', () {
      const lines = ['def f(): """doc', 'return 1', 'still doc', '"""'];
      final tracker = _trackerOver(lines, 'python');

      final first = _ranges(tracker, lines, 0);
      expect(first, hasLength(1));
      expect(first.single.start, lines[0].indexOf('"""'));
      expect(
        _ranges(tracker, lines, 2).single.end,
        lines[2].length,
        reason: 'the body line is fully string',
      );
    });

    test('two docstrings on separate lines are tracked separately', () {
      const lines = ['"""a', 'b"""', '"""c', 'd"""'];
      final tracker = _trackerOver(lines, 'python');

      expect(_ranges(tracker, lines, 0).single.start, 0);
      expect(_ranges(tracker, lines, 1).single.end, lines[1].length);
      expect(_ranges(tracker, lines, 2).single.start, 0);
      expect(_ranges(tracker, lines, 3).single.end, lines[3].length);
    });

    test('an unterminated docstring runs to the end of the file', () {
      const lines = ['"""a', 'b', 'c'];
      final tracker = _trackerOver(lines, 'python');

      for (final line in [0, 1, 2]) {
        final ranges = _ranges(tracker, lines, line);
        expect(ranges, hasLength(1), reason: 'line $line');
        expect(ranges.single.end, lines[line].length, reason: 'line $line');
      }
    });

    test('single and double triple quotes do not close each other', () {
      const lines = ['"""a', "b'''c", 'd"""'];
      final tracker = _trackerOver(lines, 'python');

      // The `'''` inside a `"""` string is ordinary text, not a closer.
      expect(_ranges(tracker, lines, 1).single.end, lines[1].length);
      expect(_ranges(tracker, lines, 2).single.end, lines[2].length);
    });

    test('a trailing backslash does not hide the closing delimiter', () {
      const lines = ['"""a\\', 'b"""'];
      final tracker = _trackerOver(lines, 'python');

      // The backslash escapes the newline, not the following line's text.
      final last = _ranges(tracker, lines, 1);
      expect(last, hasLength(1));
      expect(last.single.end, lines[1].length);
    });
  });

  group('editing invalidates the state below it', () {
    test('a new opener is seen by the lines under it', () {
      var lines = ['text', 'more text'];
      final tracker = _trackerOver(lines, 'python');
      expect(_ranges(tracker, lines, 1), isEmpty);

      lines = ['"""', 'text', 'more text'];
      tracker.lineText = (i) => lines[i];
      tracker.invalidateFrom(0);

      expect(_ranges(tracker, lines, 2), hasLength(1));
    });

    test('a removed opener stops repainting the lines under it', () {
      var lines = ['"""', 'text', 'more text'];
      final tracker = _trackerOver(lines, 'python');
      expect(_ranges(tracker, lines, 2), hasLength(1));

      lines = ['text', 'more text', 'more text'];
      tracker.lineText = (i) => lines[i];
      tracker.invalidateFrom(0);

      expect(_ranges(tracker, lines, 1), isEmpty);
      expect(_ranges(tracker, lines, 2), isEmpty);
    });

    test('an edit above shifts the state of the lines under it', () {
      var lines = ['"""', 'text', 'more text'];
      final tracker = _trackerOver(lines, 'python');

      lines = ['pass', '"""', 'text', 'more text'];
      tracker.lineText = (i) => lines[i];
      tracker.invalidateFrom(0);

      expect(_ranges(tracker, lines, 3), hasLength(1));
    });

    test('asking for a line out of order still reports the same ranges', () {
      const lines = ['"""', 'a', 'b', 'c', 'd', '"""'];
      final tracker = _trackerOver(lines, 'python');

      final forward = _ranges(tracker, lines, 5);
      final backward = _ranges(tracker, lines, 3);

      expect(backward, hasLength(1));
      expect(backward.single.end, lines[3].length);
      expect(forward, isNotEmpty);
    });
  });

  group('other languages', () {
    test('a javascript template literal spans lines', () {
      const lines = ['const a = `line one', 'line two`;', 'const b = 1;'];
      final tracker = _trackerOver(lines, 'javascript');

      expect(_ranges(tracker, lines, 0).single.start, lines[0].indexOf('`'));
      expect(_ranges(tracker, lines, 1).single.end, lines[1].indexOf('`') + 1);
      expect(_ranges(tracker, lines, 2), isEmpty);
    });

    test('a c block comment spans lines', () {
      const lines = ['int a; /* note', 'still note */ int b;', 'int c;'];
      final tracker = _trackerOver(lines, 'c');

      final second = _ranges(tracker, lines, 1);
      expect(second, hasLength(1));
      expect(second.single.start, 0);
      expect(second.single.end, lines[1].indexOf('*/') + 2);
      expect(second.single.scopeKey, 'comment');
      expect(_ranges(tracker, lines, 2), isEmpty);
    });

    test('a backslash does not escape inside a c block comment', () {
      const lines = ['/* a \\', 'b */', 'int c;'];
      final tracker = _trackerOver(lines, 'c');

      // A C block comment ends at the first `*/`; the backslash is ordinary.
      expect(_ranges(tracker, lines, 1).single.end, lines[1].length);
      expect(_ranges(tracker, lines, 2), isEmpty);
    });

    test('a tracker with no line source reports nothing', () {
      final tracker = MultilineStringTracker(
        resolveMultilineStringSpec(languageId: 'python')!,
      );
      expect(tracker.rangesForLine(0, (_) => '"""'), isEmpty);
    });

    test('a line index below zero reports nothing', () {
      const lines = ['"""', 'text'];
      final tracker = _trackerOver(lines, 'python');
      expect(_ranges(tracker, lines, -1), isEmpty);
    });
  });

  group('slice rendering', () {
    test('a slice of an interior line is still string', () {
      const lines = ['"""', 'a very long body line', '"""'];
      final tracker = _trackerOver(lines, 'python');

      // The magnifier and selection previews render substrings of a line; the
      // slice has to be coloured as if the whole line were.
      final slice = _ranges(tracker, lines, 1);
      expect(slice, hasLength(1));

      final sliced = tracker.rangesForLine(1, (i) => lines[i], textOffset: 5);
      expect(sliced, hasLength(1));
      expect(sliced.single.start, 0);
      expect(sliced.single.end, lines[1].length - 5);
    });

    test('a slice past the end of a line reports nothing', () {
      const lines = ['"""', 'body', '"""'];
      final tracker = _trackerOver(lines, 'python');

      final sliced = tracker.rangesForLine(1, (i) => lines[i], textOffset: 99);
      expect(sliced, isEmpty);
    });
  });

  group('mode names the editor actually uses', () {
    test('python mode resolves without a language id', () {
      final spec = resolveMultilineStringSpec(
        languageId: null,
        modeName: langPython.name,
      );
      expect(spec, isNotNull);
    });

    test('c, c++ and javascript modes resolve without a language id', () {
      expect(resolveMultilineStringSpec(modeName: langC.name), isNotNull);
      expect(
        resolveMultilineStringSpec(modeName: langJavascript.name),
        isNotNull,
      );
    });
  });

  group('painting', () {
    // End-to-end check that the tracker reaches the rendered colours: the
    // reported bug is visible as code-coloured words inside a docstring.
    test('a docstring body line paints as one string run', () {
      const lines = ['"""', 'CircuitPython framebuf module', '"""'];

      final tracker = _trackerOver(lines, 'python');
      final ranges = _ranges(tracker, lines, 1);
      expect(ranges, hasLength(1));
      expect(ranges.single.scopeKey, 'string');

      // The theme entry the range names has to resolve, or the overlay would
      // paint with the base style instead of the string colour.
      const theme = <String, TextStyle>{
        'root': TextStyle(color: Color(0xFFCCCCCC)),
        'string': TextStyle(color: Color(0xFF6A9FB5)),
      };
      final resolved = theme[ranges.single.scopeKey];
      expect(resolved, isNotNull);
      expect(resolved!.color, isNot(theme['root']!.color));
    });
  });
}
