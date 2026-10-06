import 'package:flutter/material.dart';

/// A colored stretch of one sampled line, addressed by UTF-16 character offsets
/// into that line.
///
/// The minimap turns these into rects: [start] and [end] become horizontal
/// pixel edges through the minimap's characters-per-pixel ratio, and [color] is
/// the theme color the syntax highlighter resolved for that run.
class MinimapColorSpan {
  const MinimapColorSpan(this.start, this.end, this.color);

  final int start;
  final int end;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is MinimapColorSpan &&
      other.start == start &&
      other.end == end &&
      other.color == color;

  @override
  int get hashCode => Object.hash(start, end, color);

  @override
  String toString() => 'MinimapColorSpan($start, $end, $color)';
}

/// Flattens the span tree a [SyntaxHighlighter] produced for one line into the
/// colored stretches a minimap bar is drawn from.
///
/// The result tiles `[0, lineText.length)` exactly — no gaps, no overlaps — so
/// a line always yields a bar as wide as the text it holds. Two things make
/// that true: stretches the grammar left without a style of their own fall back
/// to [plainColor], and so does whatever tail the grammar's spans stopped short
/// of. Without that fill a line whose tokens do not reach its end would draw a
/// bar that is shorter than the line is long, which reads as a shorter line.
///
/// Adjacent stretches that resolved to the same color are merged, because the
/// grammar emits one span per token and a bare line of identifiers would
/// otherwise cost a rect per word.
///
/// [span] is read in document order and its children inherit the color of the
/// nearest styled ancestor, matching how [TextPainter] resolves the same tree.
/// Lines with no span at all — an empty line, or a grammar that failed on that
/// line — come back as a single [plainColor] stretch, so the minimap degrades
/// to the flat look it had before it had colors.
List<MinimapColorSpan> minimapColorSpans(
  TextSpan? span,
  String lineText, {
  required Color plainColor,
}) {
  if (lineText.isEmpty) return const [];

  final raw = <MinimapColorSpan>[];
  if (span != null) _collectSpans(span, null, 0, raw);

  final merged = <MinimapColorSpan>[];
  var position = 0;

  void add(int start, int end, Color color) {
    if (end <= start) return;
    final last = merged.isEmpty ? null : merged.last;
    if (last != null && last.end == start && last.color == color) {
      merged[merged.length - 1] = MinimapColorSpan(last.start, end, color);
    } else {
      merged.add(MinimapColorSpan(start, end, color));
    }
  }

  for (final run in raw) {
    // Each run starts where the last one ended, not where the grammar said it
    // did: a span tree that overlaps itself would otherwise hand back
    // overlapping stretches, and every rect on the minimap is read off this
    // list.
    final start = run.start.clamp(position, lineText.length);
    final end = run.end.clamp(start, lineText.length);
    if (start > position) add(position, start, plainColor);
    add(start, end, run.color);
    if (end > position) position = end;
  }
  if (position < lineText.length) add(position, lineText.length, plainColor);

  return merged;
}

/// Drops the whitespace out of a flattened line, so the minimap paints code
/// and leaves the gaps between it alone.
///
/// This is what makes a minimap read as indented structure instead of a smear.
/// VS Code's renderer never draws a space or a tab at all — it advances `dx`
/// and moves on — so indentation shows as background and the eye reads blocks
/// of code rather than stripes of color. Painting a segment straight through
/// its spaces throws exactly that away.
///
/// Only runs of [minRun] or more whitespace become gaps. A single space
/// between two tokens is a word boundary, not structure, and at this scale
/// dropping every one of them turns `def foo(a, b):` into a dotted line: less
/// readable than the solid bar it replaced. Indentation and alignment are the
/// runs long enough to be worth showing.
///
/// Offsets are preserved — a gap is the absence of a span, not a span of
/// nothing — so the caller still maps the survivors through the same
/// characters-per-pixel ratio.
List<MinimapColorSpan> withoutWhitespace(
  List<MinimapColorSpan> spans,
  String lineText, {
  int minRun = 2,
}) {
  if (lineText.isEmpty) return const [];

  final out = <MinimapColorSpan>[];
  for (final span in spans) {
    final start = span.start.clamp(0, lineText.length);
    final end = span.end.clamp(start, lineText.length);
    var runStart = start;
    var i = start;
    while (i < end) {
      if (!_isMinimapSpace(lineText.codeUnitAt(i))) {
        i++;
        continue;
      }
      var gapEnd = i;
      while (gapEnd < end && _isMinimapSpace(lineText.codeUnitAt(gapEnd))) {
        gapEnd++;
      }
      // Too short to be indentation: the gap is closed again and the run keeps
      // going, so the two sides of it merge into one span below.
      if (gapEnd - i >= minRun) {
        if (i > runStart) {
          out.add(MinimapColorSpan(runStart, i, span.color));
        }
        i = gapEnd;
        runStart = i;
      } else {
        i = gapEnd;
      }
    }
    if (end > runStart) {
      out.add(MinimapColorSpan(runStart, end, span.color));
    }
  }
  return out;
}

/// Whether [unit] is horizontal whitespace a minimap bar should skip: a space
/// or a tab. Newlines cannot appear — every line is highlighted on its own.
bool _isMinimapSpace(int unit) => unit == 0x20 || unit == 0x09;

/// Walks [span] depth first, recording every styled run of text with its offset
/// from the start of the line. [inherited] is the color of the nearest styled
/// ancestor, which a child without its own color resolves to.
void _collectSpans(
  TextSpan span,
  Color? inherited,
  int offset,
  List<MinimapColorSpan> out,
) {
  final color = span.style?.color ?? inherited;
  var childOffset = offset;
  final text = span.text;
  if (text != null && text.isNotEmpty) {
    if (color != null) {
      out.add(MinimapColorSpan(offset, offset + text.length, color));
    }
    // Children are laid out after this span's own text, so that is where the
    // next one starts.
    childOffset = offset + text.length;
  }
  final children = span.children;
  if (children == null) return;
  for (final child in children) {
    // Siblings follow one another, so each one starts where the previous one
    // ended — without this every child of a span would report the same offset.
    if (child is TextSpan) {
      _collectSpans(child, color, childOffset, out);
      childOffset += child.text?.length ?? 0;
    }
  }
}
