import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/repl_traceback_frames.dart';

void main() {
  group('parseTracebackFrames', () {
    test('reads a file and line from a MicroPython traceback', () {
      const output =
          'Traceback (most recent call last):\n'
          '  File "main.py", line 12, in handler\n'
          'NameError: name \'x\' is not defined\n';
      expect(parseTracebackFrames(output), [(file: 'main.py', line: 12)]);
    });

    test('keeps the innermost frame first', () {
      const output =
          'Traceback (most recent call last):\n'
          '  File "main.py", line 3, in <module>\n'
          '  File "main.py", line 9, in handler\n'
          '  File "lib/sensor.py", line 4, in read\n'
          'ValueError: bad\n';
      expect(parseTracebackFrames(output).map((f) => f.line), [3, 9, 4]);
    });

    test('drops the stdin frame, which has no file to open', () {
      const output =
          'Traceback (most recent call last):\n'
          '  File "<stdin>", line 1, in <module>\n'
          '  File "main.py", line 5, in <module>\n'
          'NameError: x\n';
      expect(parseTracebackFrames(output), [(file: 'main.py', line: 5)]);
    });

    test('drops a <string> frame from an exec', () {
      const output =
          'Traceback (most recent call last):\n'
          '  File "<string>", line 2, in <module>\n'
          'NameError: x\n';
      expect(parseTracebackFrames(output), isEmpty);
    });

    test('finds nothing in ordinary output', () {
      expect(parseTracebackFrames('hello\nworld\n'), isEmpty);
      expect(parseTracebackFrames('File "readme.txt", line 3'), isEmpty);
    });

    test('handles a Windows path with backslashes', () {
      const output = '  File "C:\\Users\\dev\\main.py", line 7, in <module>\n';
      expect(parseTracebackFrames(output), [
        (file: r'C:\Users\dev\main.py', line: 7),
      ]);
    });

    test('ignores a frame with a non-numeric line', () {
      const output = '  File "main.py", line abc, in <module>\n';
      expect(parseTracebackFrames(output), isEmpty);
    });
  });

  group('tracebackFrameRanges', () {
    test('covers the whole File reference', () {
      const output =
          'Traceback (most recent call last):\n'
          '  File "main.py", line 12, in handler\n';
      final ranges = tracebackFrameRanges(output);
      expect(ranges, hasLength(1));
      expect(
        output.substring(ranges[0].start, ranges[0].end),
        'File "main.py", line 12',
      );
    });

    test('reports offsets that index back into the original text', () {
      const output = 'before\r\n  File "a.py", line 2\r\nafter\r\n';
      final range = tracebackFrameRanges(output).single;
      expect(output.substring(range.start, range.end), 'File "a.py", line 2');
      expect(range.frame, (file: 'a.py', line: 2));
    });

    test('does not reach back across a line boundary for File', () {
      // The word "File" appears earlier on its own line; the range must not
      // swallow it just because it is the closest preceding occurrence.
      const output = 'see File notes\r\n  File "a.py", line 1\r\n';
      final range = tracebackFrameRanges(output).single;
      expect(output.substring(range.start, range.end), 'File "a.py", line 1');
    });

    test('yields one range per frame, in order', () {
      const output = '  File "a.py", line 1\r\n  File "b.py", line 2\r\n';
      final ranges = tracebackFrameRanges(output);
      expect(ranges.map((r) => r.frame.file), ['a.py', 'b.py']);
      // Ranges must be non-overlapping and ascending for the span builder.
      for (var i = 1; i < ranges.length; i++) {
        expect(ranges[i].start, greaterThanOrEqualTo(ranges[i - 1].end));
      }
    });

    test('is empty for a stdin-only traceback', () {
      const output =
          'Traceback (most recent call last):\r\n  File "<stdin>", line 1\r\n';
      expect(tracebackFrameRanges(output), isEmpty);
    });
  });

  group('containsTraceback', () {
    test('recognises a traceback header', () {
      expect(containsTraceback('Traceback (most recent call last):'), isTrue);
    });

    test('does not fire on a bare File line', () {
      expect(containsTraceback('File "a.py", line 1'), isFalse);
    });
  });
}
