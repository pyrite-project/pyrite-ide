import 'dart:math' as math;

/// Height of one line on the minimap at its tallest, in **device** pixels.
///
/// The whole document is compressed into the panel, so a long document's
/// stride falls below this cap — that is the fit-to-panel trade the minimap
/// makes, and VS Code's text mode makes it too when a file outgrows its map.
/// The cap only decides what a *short* document looks like: without it a
/// ten-line file would draw ten bars stretched over the full panel height,
/// none of them reading as a line of code. Three device pixels is the
/// block-mode height — these bars are solid rects, one per colored stretch,
/// with no glyph mask to separate them — and at three pixels a
/// single-character token still gets three pixels of area to be recognized
/// by.
const double minimapMaxLineDeviceHeight = 3;

/// Vertical logical pixels one document line occupies on the minimap.
///
/// The minimap never scrolls: the whole document is compressed into the
/// visible panel, so the stride is simply the panel height divided by the
/// line count — every line gets an equal share and the last line's bar ends
/// at the panel's bottom edge. The cap keeps a document shorter than the
/// panel from being stretched past [minimapMaxLineDeviceHeight].
///
/// [devicePixelRatio] only scales the cap, which is defined in device
/// pixels; the compression itself is ratio-independent, because it is a
/// ratio between two logical lengths.
double minimapLineStride({
  required double panelHeight,
  required int lineCount,
  required double devicePixelRatio,
}) {
  final cap = minimapMaxLineDeviceHeight / devicePixelRatio;
  if (lineCount <= 0 || panelHeight <= 0) return cap;
  return math.min(cap, panelHeight / lineCount);
}

/// The band, in panel pixels, that the viewport highlight occupies.
///
/// [first] and [count] are line indices as reported by the editor, and
/// [lineStride] is the very scale the bars are drawn with, so painting and
/// hit-testing can never drift apart: line [first] sits at `first *
/// lineStride` on the map, and the band starts exactly there.
///
/// The band is clamped into [panelHeight]: a viewport can be taller than the
/// panel — a short file in a tall window, wrapping that puts more lines on
/// screen than the map has room for, or a stale report that outruns the
/// document — and an unclamped band would paint past the bottom edge, which
/// is the one thing a "where am I" cue must never do.
({double top, double height}) minimapViewportBand({
  required int first,
  required int count,
  required double lineStride,
  required double panelHeight,
}) {
  final height = math.min(math.max(count * lineStride, 1.0), panelHeight);
  final top = math.min(
    math.max(first * lineStride, 0.0),
    math.max(0.0, panelHeight - height),
  );
  return (top: top, height: height);
}
