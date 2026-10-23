/// Search over the xterm cell buffer, and the highlight bookkeeping that makes
/// a match visible.
///
/// The search deliberately reads `terminal.buffer` rather than the rendered
/// widget: the buffer is the program's actual output, while the widget's text
/// includes selection colours and scroll state. It also means the whole search
/// is a function over `List<String>`, so it can be unit-tested without pumping
/// a widget.
library;

import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

import 'terminal_link_parser.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';

/// One match, in cell-buffer coordinates.
class TerminalSearchMatch {
  const TerminalSearchMatch({
    required this.line,
    required this.start,
    required this.end,
  });

  /// Absolute line index in the buffer (scrollback included).
  final int line;

  /// Cell columns, [end] exclusive. The widget folds scrollback so a buffer
  /// line and the clickable row share one coordinate.
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is TerminalSearchMatch &&
      other.line == line &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(line, start, end);

  @override
  String toString() => 'TerminalSearchMatch($line:$start-$end)';
}

/// Every non-overlapping occurrence of [query] in [lines], in buffer order.
///
/// Matches never span lines. A wrapped visual row is two buffer lines to xterm,
/// and joining them would make the "go to match" scroll target ambiguous: the
/// two halves can be far apart in the buffer after a resize. Searching row by
/// row is what most terminals do and keeps one match map to one cell.
///
/// The scan walks cell columns, so the caller must pass
/// [terminalLineCellText] output (one character per cell) for the column
/// arithmetic to line up with a click.
List<TerminalSearchMatch> findTerminalSearchMatches(
  List<String> lines,
  String query, {
  bool caseSensitive = false,
}) {
  if (query.isEmpty) return const [];

  final needle = caseSensitive ? query : query.toLowerCase();
  final matches = <TerminalSearchMatch>[];

  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];
    if (line.isEmpty) continue;
    final haystack = caseSensitive ? line : line.toLowerCase();

    var offset = 0;
    while (true) {
      final index = haystack.indexOf(needle, offset);
      if (index < 0) break;
      matches.add(
        TerminalSearchMatch(
          line: lineIndex,
          start: index,
          end: index + needle.length,
        ),
      );
      // Advance by the needle length so a repeated query (`aaa` in `aaaa`)
      // produces two matches rather than overlapping ones.
      offset = index + needle.length;
      if (offset >= haystack.length) break;
    }
  }

  return matches;
}

/// The search bar's model: query, matches and the current match.
///
/// Treated as immutable so the widget can hand it to `setState` without
/// worrying about the highlight layer reading a half-updated list.
class TerminalSearchState {
  const TerminalSearchState({
    this.query = '',
    this.matches = const [],
    this.currentIndex = 0,
    this.caseSensitive = false,
  });

  final String query;
  final List<TerminalSearchMatch> matches;

  /// Index into [matches]; 0 when there is no match. Use [hasMatches] to tell
  /// "first of none" from "first of some".
  final int currentIndex;

  final bool caseSensitive;

  bool get isActive => query.isNotEmpty;

  bool get hasMatches => matches.isNotEmpty;

  TerminalSearchMatch? get current =>
      hasMatches ? matches[currentIndex.clamp(0, matches.length - 1)] : null;

  /// `第 3 / 共 17 个`, or an empty string when nothing matched. The UI shows
  /// the counter only when it has a number to show, so the "0 / 0" case never
  /// reaches the user.
  String get counterLabel => hasMatches
      ? I18nKey.terminalSearchCounter.fallback
            .replaceAll('{current}', '${currentIndex + 1}')
            .replaceAll('{total}', '${matches.length}')
      : '';

  /// Recomputes the matches for a new [query], keeping the caret at the first
  /// match. `currentIndex` resets because the old index refers to the old
  /// match list.
  TerminalSearchState withQuery(
    List<String> lines,
    String query, {
    bool caseSensitive = false,
  }) {
    final matches = findTerminalSearchMatches(
      lines,
      query,
      caseSensitive: caseSensitive,
    );
    return TerminalSearchState(
      query: query,
      matches: matches,
      currentIndex: 0,
      caseSensitive: caseSensitive,
    );
  }

  /// Re-runs the search over updated output, keeping the user's position when
  /// the same match still exists.
  ///
  /// Terminal output arrives while the bar is open; resetting to the first hit
  /// on every write would make a busy shell impossible to search. The old
  /// current match is used as the anchor, and when it disappeared the index is
  /// clamped instead.
  TerminalSearchState refresh(List<String> lines) {
    if (!isActive) return this;
    final previous = current;
    final matches = findTerminalSearchMatches(
      lines,
      query,
      caseSensitive: caseSensitive,
    );
    if (matches.isEmpty) {
      return TerminalSearchState(
        query: query,
        matches: matches,
        caseSensitive: caseSensitive,
      );
    }
    final retained = previous == null ? -1 : matches.indexOf(previous);
    return TerminalSearchState(
      query: query,
      matches: matches,
      currentIndex: retained >= 0
          ? retained
          : currentIndex.clamp(0, matches.length - 1),
      caseSensitive: caseSensitive,
    );
  }

  /// Moves the current match by [delta], wrapping around.
  ///
  /// Wrapping in both directions is what makes Enter/Shift+Enter a cycle; a
  /// search that stops dead at the last hit makes the user reverse direction to
  /// find it again.
  TerminalSearchState cycle(int delta) {
    if (!hasMatches) return this;
    final length = matches.length;
    final next = (currentIndex + delta) % length;
    return TerminalSearchState(
      query: query,
      matches: matches,
      currentIndex: next < 0 ? next + length : next,
      caseSensitive: caseSensitive,
    );
  }

  TerminalSearchState withCaseSensitive(List<String> lines, bool value) =>
      withQuery(lines, query, caseSensitive: value);
}

/// Reads every buffer line as cell text.
///
/// Snapshotting into a list is intentional: the match list stores line indexes
/// and must not be invalidated by a scrollback trim in the middle of a scan.
List<String> terminalBufferLines(Terminal terminal) {
  final lines = terminal.buffer.lines;
  return [
    for (var i = 0; i < lines.length; i++) terminalLineCellText(lines[i]),
  ];
}

/// Owns the [TerminalHighlight] objects for one search session.
///
/// xterm's highlights are caller-owned (`TerminalHighlight` is disposed by
/// whoever created it), so they cannot simply be dropped when a new search
/// runs: that would leak them into the render loop. This class is the single
/// place that creates and disposes them.
class TerminalSearchHighlighter {
  TerminalSearchHighlighter({
    required this.terminal,
    required this.controller,
    this.maxHighlights = 1000,
  });

  final Terminal terminal;
  final TerminalController controller;

  /// A cap on painted highlights, not on the match count: a 10k-line search for
  /// `e` would otherwise create tens of thousands of anchored objects every
  /// keystroke. The counter still reports the true total.
  final int maxHighlights;

  final _highlights = <TerminalHighlight>[];

  int get highlightCount => _highlights.length;

  /// Replaces the current highlight set with the matches in [state].
  ///
  /// [matchColor] is used for every hit and [currentColor] for the one the
  /// counter points at, so "3 / 17" always has a visible referent.
  void apply(
    TerminalSearchState state, {
    required Color matchColor,
    required Color currentColor,
  }) {
    dispose();
    if (!state.isActive || !state.hasMatches) return;

    final buffer = terminal.buffer;
    final current = state.current;
    final limit = state.matches.length < maxHighlights
        ? state.matches.length
        : maxHighlights;

    for (var i = 0; i < limit; i++) {
      final match = state.matches[i];
      if (match.line >= buffer.lines.length) continue;
      final line = buffer.lines[match.line];
      // Anchors clamp inside the line, so a match that ends past the current
      // width after a resize still paints something sensible.
      final p1 = line.createAnchor(match.start.clamp(0, line.length));
      final p2 = line.createAnchor(match.end.clamp(0, line.length));
      final isCurrent = current != null && match == current;
      _highlights.add(
        controller.highlight(
          p1: p1,
          p2: p2,
          color: isCurrent ? currentColor : matchColor,
        ),
      );
    }
  }

  void dispose() {
    for (final highlight in _highlights) {
      highlight.dispose();
    }
    _highlights.clear();
  }
}
