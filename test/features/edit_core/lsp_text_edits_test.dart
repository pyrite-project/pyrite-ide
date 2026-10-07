import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/edit_core/lsp_text_edits.dart';

void main() {
  group('applyLspTextEdits', () {
    test('applies a single replacement', () {
      const text = 'hello world\nsecond line';
      final result = applyLspTextEdits(text, [
        {
          'range': {
            'start': {'line': 0, 'character': 6},
            'end': {'line': 0, 'character': 11},
          },
          'newText': 'there',
        },
      ]);
      expect(result, 'hello there\nsecond line');
    });

    test('applies multiple edits back-to-front regardless of input order', () {
      // Edits arrive unordered; applying in reverse start order must not
      // invalidate offsets of earlier positions.
      const text = 'aaa\nbbb\nccc';
      final result = applyLspTextEdits(text, [
        {
          'range': {
            'start': {'line': 2, 'character': 0},
            'end': {'line': 2, 'character': 3},
          },
          'newText': 'C',
        },
        {
          'range': {
            'start': {'line': 0, 'character': 0},
            'end': {'line': 0, 'character': 3},
          },
          'newText': 'A',
        },
        {
          'range': {
            'start': {'line': 1, 'character': 1},
            'end': {'line': 1, 'character': 2},
          },
          'newText': 'B',
        },
      ]);
      expect(result, 'A\nbBb\nC');
    });

    test('handles insertions where start equals end', () {
      const text = 'ab';
      final result = applyLspTextEdits(text, [
        {
          'range': {
            'start': {'line': 0, 'character': 1},
            'end': {'line': 0, 'character': 1},
          },
          'newText': 'X',
        },
      ]);
      expect(result, 'aXb');
    });

    test('supports CRLF documents without spilling across lines', () {
      const text = 'first\r\nsecond\r\n';
      final result = applyLspTextEdits(text, [
        {
          'range': {
            'start': {'line': 1, 'character': 6},
            'end': {'line': 1, 'character': 6},
          },
          'newText': '!',
        },
      ]);
      expect(result, 'first\r\nsecond!\r\n');
    });

    test('skips malformed and out-of-range edits instead of throwing', () {
      const text = 'keep me';
      final result = applyLspTextEdits(text, [
        'not-a-map',
        {
          'range': {
            'start': {'line': 99, 'character': 0},
            'end': {'line': 99, 'character': 1},
          },
          'newText': 'nope',
        },
        {
          'range': {
            'start': {'line': 0, 'character': 8},
            'end': {'line': 0, 'character': 9},
          },
          'newText': 'beyond-eol',
        },
        {
          'range': {
            'start': {'line': 0, 'character': 5},
            'end': {'line': 0, 'character': 3},
          },
          'newText': 'inverted',
        },
        {
          'range': {
            'start': {'line': 0, 'character': 5},
            'end': {'line': 0, 'character': 7},
          },
          'newText': null, // non-string newText falls back to ''
        },
      ]);
      expect(result, 'keep ');
    });
  });

  group('lspPositionToOffset', () {
    test('resolves positions inside the document', () {
      const text = 'abc\ndef';
      expect(lspPositionToOffset(text, {'line': 0, 'character': 2}), 2);
      expect(lspPositionToOffset(text, {'line': 1, 'character': 0}), 4);
    });

    test('rejects characters beyond the line content', () {
      const text = 'abc\ndef';
      expect(lspPositionToOffset(text, {'line': 0, 'character': 4}), isNull);
    });

    test('allows a character at the end of a CRLF line', () {
      const text = 'abc\r\ndef';
      // character == line length (excluding CR) points just before \r.
      expect(lspPositionToOffset(text, {'line': 0, 'character': 3}), 3);
      expect(lspPositionToOffset(text, {'line': 0, 'character': 4}), isNull);
    });

    test('rejects lines beyond the document and malformed input', () {
      const text = 'abc';
      expect(lspPositionToOffset(text, {'line': 1, 'character': 0}), isNull);
      expect(lspPositionToOffset(text, {'line': -1, 'character': 0}), isNull);
      expect(lspPositionToOffset(text, {'line': 0, 'character': -1}), isNull);
      expect(lspPositionToOffset(text, {'line': 'x'}), isNull);
      expect(lspPositionToOffset(text, null), isNull);
      expect(
        lspPositionToOffset(text, {'line': 0}),
        isNull,
      ); // missing character
    });
  });

  group('symbolAtOffset', () {
    test('expands to the full identifier around the offset', () {
      const text = 'def my_function(arg):';
      expect(symbolAtOffset(text, 5), 'my_function');
      expect(symbolAtOffset(text, 15), 'my_function');
    });

    test('stops at non-identifier characters', () {
      const text = 'value.attr';
      expect(symbolAtOffset(text, 7), 'attr');
      expect(symbolAtOffset(text, 3), 'value');
    });

    test('returns empty strings for empty text or boundaries', () {
      expect(symbolAtOffset('', 0), '');
      expect(symbolAtOffset('abc', 3), 'abc');
      expect(symbolAtOffset('()', 1), '');
    });

    test('clamps out-of-range offsets', () {
      const text = 'abc';
      expect(symbolAtOffset(text, 99), 'abc');
    });
  });
}
