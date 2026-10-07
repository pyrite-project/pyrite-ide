import 'dart:math' as math;

/// Height of one line on the minimap at its tallest, in **device** pixels.
///
/// This is VS Code's block-mode line height, and like VS Code it is *fixed*
/// rather than a share of the panel: the map gives every line the same amount
/// of room and scrolls a long document under the panel instead of squeezing
/// the whole file into it (see [minimapLayout]). The cap only decides what a
/// short document looks like — one shorter than the panel leaves empty space
/// below it, exactly as it does in VS Code. Three device pixels is the
/// block-mode height — these bars are solid rects, one per colored stretch,
/// with no glyph mask to separate them — and at three pixels a
/// single-character token still gets three pixels of area to be recognized
/// by.
const double minimapMaxLineDeviceHeight = 3;

/// Vertical logical pixels one document line occupies on the minimap.
///
/// Fixed, the way VS Code's proportional minimap fixes it: the map's scale is
/// a property of the display, not of the document. A ten-thousand-line file
/// and a two-hundred-line file are drawn at the same pitch; the long one
/// simply scrolls.
///
/// [devicePixelRatio] only scales the constant, which is defined in device
/// pixels.
double minimapLineStride({required double devicePixelRatio}) =>
    minimapMaxLineDeviceHeight / devicePixelRatio;

/// How many document lines the panel can show at [lineStride].
///
/// At least one: a panel too short for a single line bar still has to draw
/// that bar rather than divide by nothing.
int minimapLinesFitting({
  required double panelHeight,
  required double lineStride,
}) {
  if (lineStride <= 0) return 1;
  return math.max(1, (panelHeight / lineStride).floor());
}

/// Everything one minimap frame needs to draw itself.
///
/// Bundled because painting and hit-testing must not be able to disagree: both
/// take a layout for the same inputs rather than each deriving a window and a
/// band of their own.
typedef MinimapLayout = ({
  /// Document line sitting at the panel's top edge — zero unless the map
  /// is a window onto a longer document (see [scrolls]).
  int startLine,

  /// Logical pixels per line, as drawn.
  double lineStride,

  /// Whole lines the panel spans at [lineStride].
  int linesFitting,

  /// Top edge of the viewport band, in panel pixels.
  double bandTop,

  /// Height of the viewport band, in panel pixels. Never reaches past the
  /// panel's bottom edge.
  double bandHeight,

  /// Whether the map is a window onto a document taller than the panel,
  /// and therefore scrolls.
  bool scrolls,
});

/// Places the map's window and the viewport band for one frame.
///
/// This is a Dart restatement of VS Code's `MinimapLayout.create` and follows
/// it on the point that matters: VS Code's minimap is *proportional* by
/// default, which means the per-line stride is fixed and a document taller
/// than the panel is scrolled under it. (The alternative, VS Code's `fill`
/// mode, is what this minimap used to do unconditionally: compress every line
/// until the whole file fits. On a long file that drives the stride below a
/// device pixel and the map dissolves into a smear.)
///
/// So there are two shapes here, and the split is the same one VS Code makes:
///
/// * **Everything fits** (`lineCount <= linesFitting`). The map *is* the
///   document, [startLine] is zero and there is nothing to scroll. The band
///   lands where its first line sits, via [minimapViewportBand].
/// * **The document is taller** — the map is a window and the viewport band
///   becomes the slider, the one piece that knows where in the file the reader
///   is. VS Code gives that slider the full range `0..maxSliderTop` while the
///   viewport travels the full range `0..(lineCount - viewportLines)` lines,
///   which makes the mapping between the two the ratio it is called
///   `computedSliderRatio` there. The window then sits as far above the
///   viewport as the slider has travelled, which is what puts the band exactly
///   where the slider is.
///
/// The band's containment is the invariant this whole arrangement exists to
/// protect, and it falls out of the construction rather than being patched on:
/// the slider never travels past `panelHeight - sliderHeight`, the window puts
/// the band no higher than the slider (it rounds *down* to a whole line), and
/// the band's height is then shortened by whatever room is left. A stale or
/// folded viewport report — one naming lines the document no longer has — is
/// clamped first, so it cannot walk the band off the panel either.
MinimapLayout minimapLayout({
  required double panelHeight,
  required int lineCount,
  required double devicePixelRatio,
  required int first,
  required int count,
}) {
  final lineStride = minimapLineStride(devicePixelRatio: devicePixelRatio);
  final linesFitting = minimapLinesFitting(
    panelHeight: panelHeight,
    lineStride: lineStride,
  );
  if (lineCount <= 0 || panelHeight <= 0) {
    return (
      startLine: 0,
      lineStride: lineStride,
      linesFitting: linesFitting,
      bandTop: 0,
      bandHeight: 0,
      scrolls: false,
    );
  }

  // An empty viewport is still "somewhere": one line of band reads as "between
  // lines" rather than as a map that forgot where the reader is.
  final viewportLines = math.max(1, count);

  if (lineCount <= linesFitting) {
    final band = minimapViewportBand(
      first: first,
      count: viewportLines,
      lineStride: lineStride,
      panelHeight: panelHeight,
    );
    return (
      startLine: 0,
      lineStride: lineStride,
      linesFitting: linesFitting,
      bandTop: band.top,
      bandHeight: band.height,
      scrolls: false,
    );
  }

  // The slider. Its height is the viewport's share of the map, and its travel
  // is whatever the viewport does not already occupy.
  final sliderHeight = math.min(viewportLines * lineStride, panelHeight);
  final maxSliderTop = math.max(0.0, panelHeight - sliderHeight);

  // The viewport may only be scrolled so far as the last full screenful; a
  // report past that (a stale frame, a file that just shrank) is pulled back
  // before it becomes a slider position, which is what keeps `sliderTop` on
  // its rails rather than relying on the clamps downstream.
  final scrollableLines = math.max(1, lineCount - viewportLines);
  final scrolledFirst = math.min(math.max(first, 0), scrollableLines);

  // VS Code's computedSliderRatio, specialized: the slider's travel over the
  // viewport's travel.
  final sliderTop = (scrolledFirst / scrollableLines) * maxSliderTop;

  // The window trails the viewport by however many lines the slider has
  // travelled, so the band lands on the slider. Rounding *down* is what keeps
  // the band at or above the slider and never past the panel's bottom.
  final startLine = math.min(
    math.max(scrolledFirst - (sliderTop / lineStride).floor(), 0),
    math.max(0, lineCount - 1),
  );

  final bandTop = math.min(
    math.max((scrolledFirst - startLine) * lineStride, 0.0),
    maxSliderTop,
  );
  final bandHeight = math.min(
    viewportLines * lineStride,
    panelHeight - bandTop,
  );

  return (
    startLine: startLine,
    lineStride: lineStride,
    linesFitting: linesFitting,
    bandTop: bandTop,
    bandHeight: bandHeight,
    scrolls: true,
  );
}

/// The band, in panel pixels, that the viewport highlight occupies.
///
/// This is the *unscrolled* case — a document that fits — and the one the
/// scrolled case reduces to. [first] and [count] are line indices as reported
/// by the editor, and [lineStride] is the very scale the bars are drawn with,
/// so painting and hit-testing can never drift apart: line [first] sits at
/// `first * lineStride` on the map, and the band starts exactly there.
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

/// The panel-space top edge of the bar for [line], snapped to a whole device
/// pixel.
///
/// Measured from [windowStart], the document line at the top of the recording
/// rather than line 0 — that is what lets a recording be a window onto a
/// document taller than the panel.
///
/// The result is in **logical** pixels, like everything else the painter works
/// in. The device pixel ratio enters only through the snapping, never as a
/// scale factor on the result: a bar that straddles a pixel boundary gets
/// blended across two rows by the rasterizer, and blended is exactly what a
/// syntax color must not be.
double minimapBarEdge({
  required int line,
  required int windowStart,
  required double lineStride,
  required double devicePixelRatio,
}) {
  final logical = (line - windowStart) * lineStride;
  return (logical * devicePixelRatio).roundToDouble() / devicePixelRatio;
}

/// The document line drawn [y] pixels down the minimap panel.
///
/// [startLine] is the layout's window offset, which is what makes this work on
/// a scrolled map: the panel's top edge is not line 0. The result is clamped
/// into the document so a click near either end cannot name a line that does
/// not exist.
int minimapLineAt({
  required double y,
  required int startLine,
  required double lineStride,
  required int lineCount,
}) {
  if (lineStride <= 0 || lineCount <= 0) return 0;
  final line = startLine + (y / lineStride).round();
  return math.min(math.max(line, 0), lineCount - 1);
}
