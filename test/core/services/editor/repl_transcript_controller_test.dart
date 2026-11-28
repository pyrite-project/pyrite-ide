import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/repl_transcript_controller.dart';

void main() {
  test('preserves normal CRLF output across chunks', () {
    final transcript = ReplTranscriptController();

    transcript.append('hello\r');
    transcript.append('\nworld');

    expect(transcript.text, 'hello\nworld');
  });

  test('removes ANSI control sequences from display text', () {
    final transcript = ReplTranscriptController();

    transcript.append('\x1b[32mready\x1b[0m');

    expect(transcript.text, 'ready');
  });

  test('handles backspace without affecting previous lines', () {
    final transcript = ReplTranscriptController();

    transcript.append('ab\bc\nnext');

    expect(transcript.text, 'ac\nnext');
  });

  test('renders a standalone carriage return immediately', () {
    final transcript = ReplTranscriptController();

    transcript.append('working\r');

    expect(transcript.text, '');
  });

  test('drops the oldest lines once the buffer exceeds maxLines', () {
    final transcript = ReplTranscriptController(maxLines: 4);

    transcript.append('a\nb\nc\nd\ne\nf\n');

    // The trailing newline leaves the live line empty, so the retained window
    // is the last four entries: d, e, f and the empty line still being typed.
    expect(transcript.lineCount, 4);
    expect(transcript.text, 'd\ne\nf\n');
    expect(transcript.droppedLines, 3);
  });

  test('keeps a single live line when the limit is one', () {
    final transcript = ReplTranscriptController(maxLines: 1);

    transcript.append('first\nsecond');

    expect(transcript.lineCount, 1);
    expect(transcript.text, 'second');
  });

  test('resets the dropped-line count on clear', () {
    final transcript = ReplTranscriptController(maxLines: 2);

    transcript.append('a\nb\nc\n');
    expect(transcript.droppedLines, greaterThan(0));

    transcript.clear();

    expect(transcript.droppedLines, 0);
    expect(transcript.isEmpty, isTrue);
  });
}
