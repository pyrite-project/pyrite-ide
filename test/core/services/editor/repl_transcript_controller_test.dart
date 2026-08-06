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
}
