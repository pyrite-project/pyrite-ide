import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/terminal/terminal_search.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('findTerminalSearchMatches', () {
    test('finds every non-overlapping occurrence in buffer order', () {
      final matches = findTerminalSearchMatches([
        'foo bar foo',
        'nothing',
        'FOO',
      ], 'foo');

      expect(matches, [
        const TerminalSearchMatch(line: 0, start: 0, end: 3),
        const TerminalSearchMatch(line: 0, start: 8, end: 11),
        const TerminalSearchMatch(line: 2, start: 0, end: 3),
      ]);
    });

    test('is case insensitive by default and exact when asked', () {
      expect(findTerminalSearchMatches(['FOO'], 'foo'), hasLength(1));
      expect(
        findTerminalSearchMatches(['FOO'], 'foo', caseSensitive: true),
        isEmpty,
      );
    });

    test('does not consume a repeated query twice at the same offset', () {
      // `aa` in `aaa` is one match at 0 and a second one at 2, not 0 and 1.
      expect(findTerminalSearchMatches(['aaa'], 'aa'), [
        const TerminalSearchMatch(line: 0, start: 0, end: 2),
      ]);
    });

    test('returns nothing for an empty query', () {
      expect(findTerminalSearchMatches(['anything'], ''), isEmpty);
    });

    test('never spans two buffer lines', () {
      // A wrapped visual row is two lines to xterm; joining them would make the
      // scroll target ambiguous, so the match must be found only on the line
      // that contains it.
      final matches = findTerminalSearchMatches(['abc', 'def'], 'cde');

      expect(matches, isEmpty);
    });
  });

  group('TerminalSearchState', () {
    final lines = ['one two', 'two three', 'two'];

    test('counts matches and reports the first one', () {
      final state = const TerminalSearchState().withQuery(lines, 'two');

      expect(state.hasMatches, isTrue);
      expect(state.currentIndex, 0);
      expect(state.counterLabel, '第 1 / 共 3 个');
      expect(
        state.current,
        const TerminalSearchMatch(line: 0, start: 4, end: 7),
      );
    });

    test('cycle wraps in both directions', () {
      final state = const TerminalSearchState().withQuery(lines, 'two');

      final next = state.cycle(1).cycle(1).cycle(1);
      expect(next.currentIndex, 0);
      expect(state.cycle(-1).currentIndex, 2);
    });

    test('counter is blank when nothing matched', () {
      final state = const TerminalSearchState().withQuery(lines, 'absent');

      expect(state.hasMatches, isFalse);
      expect(state.counterLabel, isEmpty);
      expect(state.current, isNull);
    });

    test('cycle is a no-op without matches', () {
      final state = const TerminalSearchState().withQuery(lines, 'absent');

      expect(state.cycle(1), same(state));
    });

    test('refresh keeps the position when the same match still exists', () {
      final state = const TerminalSearchState()
          .withQuery(lines, 'two')
          .cycle(1);
      expect(state.current?.line, 1);

      // New output appends below, so the match itself is unchanged.
      final refreshed = state.refresh([...lines, 'four two']);

      expect(refreshed.current?.line, 1);
      expect(refreshed.matches, hasLength(4));
    });

    test(
      'refresh clamps when the current match scrolled out of the buffer',
      () {
        final state = const TerminalSearchState()
            .withQuery(lines, 'two')
            .cycle(1)
            .cycle(1);
        expect(state.current?.line, 2);

        // The scrollback trimmed the line the caret was on.
        final refreshed = state.refresh(['two a']);

        expect(refreshed.currentIndex, 0);
        expect(refreshed.current?.line, 0);
      },
    );

    test('refresh without a query returns itself', () {
      const state = TerminalSearchState();

      expect(state.refresh(lines), same(state));
    });

    test('withCaseSensitive re-runs the query', () {
      final state = const TerminalSearchState().withQuery(['Foo foo'], 'foo');
      expect(state.matches, hasLength(2));

      final exact = state.withCaseSensitive(['Foo foo'], true);

      expect(exact.matches, hasLength(1));
      expect(exact.current?.start, 4);
    });
  });

  group('terminalBufferLines', () {
    test('snapshots every line as cell text', () {
      final terminal = Terminal()
        ..resize(20, 3)
        ..write('hello\r\nworld');

      final lines = terminalBufferLines(terminal);

      expect(lines.first, startsWith('hello'));
      expect(lines[1], startsWith('world'));
      expect(lines, hasLength(terminal.buffer.lines.length));
    });
  });

  group('TerminalSearchHighlighter', () {
    test('creates one highlight per match and disposes them', () {
      final terminal = Terminal()
        ..resize(20, 4)
        ..write('ab ab');
      final controller = TerminalController();
      final highlighter = TerminalSearchHighlighter(
        terminal: terminal,
        controller: controller,
      );
      final state = const TerminalSearchState().withQuery(
        terminalBufferLines(terminal),
        'ab',
      );

      highlighter.apply(
        state,
        matchColor: const Color(0xFFFF0000),
        currentColor: const Color(0xFF00FF00),
      );

      expect(highlighter.highlightCount, state.matches.length);
      expect(controller.highlights, hasLength(state.matches.length));

      highlighter.dispose();
      expect(controller.highlights, isEmpty);
      expect(highlighter.highlightCount, 0);
    });

    test('re-applying replaces the previous set instead of leaking it', () {
      final terminal = Terminal()
        ..resize(20, 4)
        ..write('ab ab');
      final controller = TerminalController();
      final highlighter = TerminalSearchHighlighter(
        terminal: terminal,
        controller: controller,
      );
      final lines = terminalBufferLines(terminal);

      highlighter.apply(
        const TerminalSearchState().withQuery(lines, 'ab'),
        matchColor: const Color(0xFFFF0000),
        currentColor: const Color(0xFF00FF00),
      );
      final first = highlighter.highlightCount;
      highlighter.apply(
        const TerminalSearchState().withQuery(lines, 'a'),
        matchColor: const Color(0xFFFF0000),
        currentColor: const Color(0xFF00FF00),
      );

      expect(first, 2);
      expect(controller.highlights, hasLength(highlighter.highlightCount));
    });

    test('caps the number of painted highlights', () {
      final terminal = Terminal()..resize(40, 4);
      for (var i = 0; i < 10; i++) {
        terminal.write('a ');
      }
      final controller = TerminalController();
      final highlighter = TerminalSearchHighlighter(
        terminal: terminal,
        controller: controller,
        maxHighlights: 3,
      );

      highlighter.apply(
        const TerminalSearchState().withQuery(
          terminalBufferLines(terminal),
          'a',
        ),
        matchColor: const Color(0xFFFF0000),
        currentColor: const Color(0xFF00FF00),
      );

      expect(highlighter.highlightCount, 3);
    });

    test('applying an empty search clears the highlights', () {
      final terminal = Terminal()..resize(20, 4);
      final controller = TerminalController();
      final highlighter = TerminalSearchHighlighter(
        terminal: terminal,
        controller: controller,
      );

      highlighter.apply(
        const TerminalSearchState(),
        matchColor: const Color(0xFFFF0000),
        currentColor: const Color(0xFF00FF00),
      );

      expect(controller.highlights, isEmpty);
    });
  });
}
