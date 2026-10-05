import 'dart:async';
import 'dart:math' as math;

import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter/material.dart';

/// Width of the minimap column.
const double kMinimapWidth = 76;

/// Width kept clear at the editor's right edge so the editor's own scrollbar
/// stays uncovered (default [ScrollbarDecoration] thickness is 8). Hovering
/// the minimap reveals that scrollbar there through
/// [CodeForgeController.scrollbarForcedVisible].
const double _scrollbarStripReserve = 12;

/// Backdrop opacity (alpha, 0-255) of the floating minimap; the name follows
/// [Color.withAlpha]. Higher values make the overlay **more opaque**: at 0
/// the backdrop disappears entirely, at 255 it would fully cover the code
/// underneath. The minimap floats over the editor's right edge, so pick a
/// value well below full opacity to let that code ghost through.
const int _overlayBackgroundAlpha = 200;

/// Proportional code minimap shown over the editor it wraps.
///
/// The shell deliberately does **not** hand the editor a shared
/// [ScrollController]: [CodeForge] recreates its whole subtree whenever its
/// key changes (tab switch, theme change), and during such a remount the
/// outgoing — deactivated but not yet disposed — scroll position stays
/// attached while the incoming one attaches too, which trips ScrollController's
/// `_positions.length == 1` assertion the moment anything reads `.position`.
///
/// Instead the shell listens to vertical [ScrollNotification]s bubbling out of
/// the editor for the viewport indicator, and jumps through
/// [CodeForgeController.jumpToLine] (instant, top-aligning) — the editor keeps
/// its own scroll controller and scrollbar exactly as without the minimap.
///
/// Interaction model: the minimap is interactive (tap centers the clicked
/// region, dragging scrubs scrollbar-style) but its own look never changes on
/// hover. Hovering instead raises
/// [CodeForgeController.scrollbarForcedVisible], so the editor's **native**
/// scrollbar — original decoration, original behavior — appears in the strip
/// to the right of the map that the shell leaves uncovered for it.
///
/// Line bars assume one uniform height per line, so with wrapping on a bar is
/// an approximation: it stands for the whole line however many screen lines
/// that line wraps onto. That is the same trade VS Code makes, and the bars
/// still answer "roughly where am I" because they stay proportional to line
/// index. What wrapping used to break was the *viewport* mapping, which
/// divided the scroll offset by the line height to recover a line number —
///
/// that division is wrong whenever lines have different heights, so the
/// viewport indicator drifted away from the bars it was supposed to mark. The
/// minimap instead reads the viewport range straight from the editor
/// ([CodeForgeController.firstVisibleLine] and
/// [CodeForgeController.visibleLineCount]), which the renderer computes from
/// the real per-line geometry. So wrapping now costs bar accuracy and buys a
/// minimap that stays visible and stays aligned, instead of one that vanishes.
class MinimapEditorShell extends StatefulWidget {
  const MinimapEditorShell({
    super.key,
    required this.controller,
    required this.enabled,
    required this.lineWrap,
    required this.foreground,
    required this.background,
    required this.estimatedLineHeight,
    required this.child,
  });

  final CodeForgeController controller;
  final bool enabled;

  /// Whether the editor is wrapping. Kept because the bar heights are built
  /// for an unwrapped document, and a wrapped line may want a slightly
  /// different bar weight.
  final bool lineWrap;
  final Color foreground;
  final Color background;

  /// Fallback line height used until the renderer publishes the real one
  /// through [CodeForgeController.editorLineHeight].
  final double estimatedLineHeight;

  /// The editor subtree. Notifications bubbling out of it feed the minimap,
  /// so the child must not swallow [ScrollNotification]s.
  final Widget child;

  /// Below this editor width the minimap would crowd the code.
  static const double _minWidthForMinimap = 560;

  @override
  State<MinimapEditorShell> createState() => _MinimapEditorShellState();
}

class _MinimapEditorShellState extends State<MinimapEditorShell> {
  /// Latest vertical scroll metrics seen above the shell:
  /// `(pixels, viewportDimension, maxScrollExtent)`, null before the first
  /// scroll. Drives the minimap's viewport indicator without sharing any
  /// scroll controller with the editor.
  final ValueNotifier<(double, double, double)?> _scrollMetrics = ValueNotifier(
    null,
  );

  /// The editor's visible line range, republished to the painter so the "in
  /// view" highlight tracks scrolling without rebuilding the minimap.
  ///
  /// Owned here rather than in [_MinimapView] because the shell is the thing
  /// that hears the scroll notifications: the view is not built at all on a
  /// narrow window, so it cannot be the thing that keeps them current.
  final ValueNotifier<({int first, int count})?> _viewportRange = ValueNotifier(
    null,
  );

  @override
  void dispose() {
    _scrollMetrics.dispose();
    _viewportRange.dispose();
    super.dispose();
  }

  /// Reads the viewport's line range off the editor.
  ///
  /// Deferred by one frame because a [ScrollNotification] is dispatched around
  /// the position change, not after the layout that the range is derived from;
  /// reading synchronously here would report the line range of the previous
  /// scroll. Writing only on change keeps a scroll that stays inside one
  /// screenful of lines from repainting at all.
  void _refreshViewportRange() {
    final first = widget.controller.firstVisibleLine;
    final count = widget.controller.visibleLineCount;
    if (first == null || count == null) {
      if (_viewportRange.value != null) _viewportRange.value = null;
      return;
    }
    final current = _viewportRange.value;
    if (current != null && current.first == first && current.count == count) {
      return;
    }
    _viewportRange.value = (first: first, count: count);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showMinimap =
            widget.enabled &&
            constraints.maxWidth >= MinimapEditorShell._minWidthForMinimap;
        final editor = NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis == Axis.vertical) {
              _scrollMetrics.value = (
                notification.metrics.pixels,
                notification.metrics.viewportDimension,
                notification.metrics.maxScrollExtent,
              );
              // The listener stays alive across a toggle of `enabled` and of
              // the width threshold, so the range must be refreshed whether or
              // not the minimap is being painted this frame.
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _refreshViewportRange(),
              );
            }
            return false;
          },
          child: widget.child,
        );
        if (!showMinimap) return editor;
        // The minimap overlays the editor's right edge but leaves the
        // scrollbar strip uncovered, so the native scrollbar can appear there
        // (forced visible while the pointer hovers the map) in its own style.
        return Stack(
          textDirection: TextDirection.ltr,
          children: [
            Positioned.fill(child: editor),
            Positioned(
              top: 0,
              right: _scrollbarStripReserve,
              bottom: 0,
              width: kMinimapWidth,
              child: _MinimapView(
                controller: widget.controller,
                scrollMetrics: _scrollMetrics,
                viewportRange: _viewportRange,
                foreground: widget.foreground,
                background: widget.background,
                estimatedLineHeight: widget.estimatedLineHeight,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MinimapView extends StatefulWidget {
  const _MinimapView({
    required this.controller,
    required this.scrollMetrics,
    required this.viewportRange,
    required this.foreground,
    required this.background,
    required this.estimatedLineHeight,
  });

  final CodeForgeController controller;

  /// Latest vertical scroll metrics seen above the shell:
  /// `(pixels, viewportDimension, maxScrollExtent)`, null before the first
  /// scroll.
  final ValueNotifier<(double, double, double)?> scrollMetrics;

  /// The editor's visible line range, owned by the shell because the shell is
  /// what hears the scroll notifications.
  final ValueNotifier<({int first, int count})?> viewportRange;
  final Color foreground;
  final Color background;
  final double estimatedLineHeight;

  @override
  State<_MinimapView> createState() => _MinimapViewState();
}

class _MinimapViewState extends State<_MinimapView> {
  /// Character count a full-width bar represents; longer lines cap at the
  /// column edge like VS Code's minimap.
  static const double _referenceChars = 120;

  /// Upper bound on painted bars; beyond this, lines are sampled in blocks so
  /// a generated data dump cannot turn every scroll tick into thousands of
  /// rect draws.
  static const int _maxBars = 6000;

  static const Duration _recomputeDebounce = Duration(milliseconds: 150);

  /// One width per sampled line block; block i covers lines
  /// `[i * step, (i + 1) * step)`.
  List<double> _barWidths = const [];
  int _step = 1;
  double _lineStride = 1;
  Timer? _debounce;

  /// Distance from the viewport indicator's top edge to the pointer while a
  /// drag is in progress — scrollbar-style relative dragging. Null when no
  /// drag is active.
  double? _dragGrabOffset;

  double get _lineHeight =>
      widget.controller.editorLineHeight ?? widget.estimatedLineHeight;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleRecompute);
    // The stride depends on the laid-out minimap height, which does not exist
    // yet during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeBars());
  }

  @override
  void didUpdateWidget(_MinimapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleRecompute);
      widget.controller.addListener(_scheduleRecompute);
      _recomputeBars();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleRecompute);
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleRecompute() {
    _debounce?.cancel();
    _debounce = Timer(_recomputeDebounce, _recomputeBars);
  }

  void _recomputeBars() {
    if (!mounted) return;
    final lineCount = widget.controller.lineCount;
    if (lineCount <= 0) {
      setState(() {
        _barWidths = const [];
        _step = 1;
        _lineStride = 1;
      });
      return;
    }
    _step = math.max(1, (lineCount / _maxBars).ceil());
    final blocks = (lineCount / _step).ceil();
    final charWidth = kMinimapWidth / _referenceChars;
    final widths = List<double>.filled(blocks, 0);
    for (var block = 0; block < blocks; block++) {
      final line = block * _step;
      widths[block] = math.min(
        kMinimapWidth,
        widget.controller.getLineText(line).length * charWidth,
      );
    }
    setState(() {
      _barWidths = widths;
      // Vertical pixels per line that fit the whole document into the visible
      // minimap area, clamped so short documents still read as bars.
      _lineStride = _resolveLineStride(lineCount);
    });
  }

  double _resolveLineStride(int lineCount) {
    final box = context.findRenderObject();
    final height = box is RenderBox && box.hasSize ? box.size.height : 400.0;
    return math.min(3.0, math.max(0.5, height / lineCount));
  }

  /// Viewport indicator geometry in minimap pixels, from the latest scroll
  /// metrics; null before the first scroll or with an empty document.
  ({double top, double height})? _indicatorGeometry() {
    final metrics = widget.scrollMetrics.value;
    if (metrics == null) return null;
    final lineCount = widget.controller.lineCount;
    if (lineCount <= 0) return null;
    final total = metrics.$3 + metrics.$2;
    if (total <= 0) return null;
    final mapped = _mappedHeight(lineCount);
    return (
      top: (metrics.$1 / total) * mapped,
      height: math.max((metrics.$2 / total) * mapped, 8.0),
    );
  }

  /// Height the document actually occupies on the minimap: the stride makes
  /// long documents overflow the widget, in which case painting and jump
  /// mapping both clip to the widget height so they stay consistent.
  double _mappedHeight(int lineCount) {
    final box = context.findRenderObject();
    final height = box is RenderBox && box.hasSize ? box.size.height : 400.0;
    return math.min(lineCount * _lineStride, height);
  }

  /// Scrollbar-style drag: the pointer keeps its grab point on the indicator,
  /// so the document moves exactly with the pointer. Drives the editor
  /// through [CodeForgeController.jumpToLine], which is instant and
  /// top-aligning — [CodeForgeController.scrollToLine] starts a 300 ms
  /// centered animation per call and lags behind the pointer.
  void _onDragStart(DragStartDetails details) {
    final y = details.localPosition.dy;
    final geometry = _indicatorGeometry();
    _dragGrabOffset = geometry == null
        ? 0
        : (y >= geometry.top && y <= geometry.top + geometry.height)
        ? y - geometry.top
        // Pressed outside the thumb: center it on the pointer, then keep
        // dragging relative from there.
        : geometry.height / 2;
    _applyDrag(y);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragGrabOffset ??= 0;
    _applyDrag(details.localPosition.dy);
  }

  void _applyDrag(double y) {
    final grab = _dragGrabOffset ?? 0;
    final lineCount = widget.controller.lineCount;
    if (lineCount <= 0) return;
    final mapped = _mappedHeight(lineCount);
    if (mapped <= 0) return;
    final desiredTop = (y - grab).clamp(0.0, mapped);
    final targetLine = ((desiredTop / mapped) * lineCount).round().clamp(
      0,
      lineCount - 1,
    );
    try {
      widget.controller.jumpToLine(targetLine);
    } on StateError {
      // The editor has not mounted its renderer yet (keyed remount in
      // progress); the next drag update will land once it is back.
    }
  }

  /// A tap jumps so the clicked document region sits in the middle of the
  /// viewport, VSCode-minimap style.
  void _jumpTo(double minimapY) {
    final lineCount = widget.controller.lineCount;
    if (lineCount <= 0) return;
    final mapped = _mappedHeight(lineCount);
    if (mapped <= 0) return;
    final metrics = widget.scrollMetrics.value;
    // Half the visible lines, taken from the editor rather than from
    // `viewportPixels / lineHeight`: with wrapping on that division does not
    // yield a line count, so the tap would land a screenful off.
    final range = widget.viewportRange.value;
    final viewportLines =
        range?.count ??
        (metrics == null || _lineHeight <= 0
            ? 0
            : (metrics.$2 / _lineHeight).round());
    final target = ((minimapY / mapped) * lineCount - viewportLines / 2)
        .round()
        .clamp(0, lineCount - 1);
    try {
      widget.controller.jumpToLine(target);
    } on StateError {
      // The editor has not mounted its renderer yet (keyed remount in
      // progress); the next tap will land once it is back.
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => _jumpTo(details.localPosition.dy),
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: (_) => _dragGrabOffset = null,
      onVerticalDragCancel: () => _dragGrabOffset = null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => widget.controller.scrollbarForcedVisible.value = true,
        onExit: (_) => widget.controller.scrollbarForcedVisible.value = false,
        child: SizedBox(
          width: kMinimapWidth,
          child: LayoutBuilder(
            builder: (context, constraints) => CustomPaint(
              size: Size(kMinimapWidth, constraints.maxHeight),
              painter: _MinimapPainter(
                scrollMetrics: widget.scrollMetrics,
                viewportRange: widget.viewportRange,
                barWidths: _barWidths,
                step: _step,
                lineStride: _lineStride,
                foreground: widget.foreground,
                background: widget.background,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.scrollMetrics,
    required this.viewportRange,
    required this.barWidths,
    required this.step,
    required this.lineStride,
    required this.foreground,
    required this.background,
  }) : super(repaint: Listenable.merge([scrollMetrics, viewportRange]));

  final ValueNotifier<(double, double, double)?> scrollMetrics;

  /// `(first line, line count)` for the editor's current viewport, or null
  /// before the editor has been laid out. Fed from the renderer, which knows
  /// the real per-line heights.
  final ValueNotifier<({int first, int count})?> viewportRange;
  final List<double> barWidths;
  final int step;
  final double lineStride;
  final Color foreground;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = background.withAlpha(_overlayBackgroundAlpha),
    );

    final lineCount = barWidths.length * step;
    if (lineCount == 0) return;
    final contentHeight = lineCount * lineStride;

    // Lines inside the viewport are drawn brighter so the minimap doubles as
    // a "where am I" cue even before the viewport indicator is read.
    //
    // The range comes from the editor rather than from dividing the scroll
    // offset by the line height: with wrapping on, lines have different
    // heights and that division yields a position that is not a line number,
    // which slid the highlight off the bars as soon as a long line was on
    // screen. The renderer computes the real range from its own layout.
    final metrics = scrollMetrics.value;
    final viewport = viewportRange.value;
    final hasViewportRange = viewport != null;

    final dimPaint = Paint()..color = foreground.withAlpha(55);
    final brightPaint = Paint()..color = foreground.withAlpha(140);
    final barHeight = math.max(0.8, step * lineStride);
    for (var block = 0; block < barWidths.length; block++) {
      final lineWidth = barWidths[block];
      if (lineWidth <= 0) continue;
      final top = block * step * lineStride;
      if (top > size.height) break;
      final inView =
          hasViewportRange &&
          block * step + step > viewport.first &&
          block * step < viewport.first + viewport.count;
      canvas.drawRect(
        Rect.fromLTWH(2, top, lineWidth, barHeight),
        inView ? brightPaint : dimPaint,
      );
    }

    if (metrics == null) return;
    final total = metrics.$3 + metrics.$2;
    if (total <= 0) return;
    // The indicator maps scroll metrics proportionally, so it stays aligned
    // with the document even when folded regions shrink the real content.
    final mappedHeight = math.min(contentHeight, size.height);
    final indicatorTop = (metrics.$1 / total) * mappedHeight;
    final indicatorHeight = math.max((metrics.$2 / total) * mappedHeight, 8.0);
    final indicatorRect = Rect.fromLTWH(
      0,
      indicatorTop,
      size.width,
      indicatorHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(indicatorRect, const Radius.circular(2)),
      Paint()..color = foreground.withAlpha(22),
    );
    final edgePaint = Paint()
      ..color = foreground.withAlpha(70)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, indicatorTop),
      Offset(size.width, indicatorTop),
      edgePaint,
    );
    canvas.drawLine(
      Offset(0, indicatorRect.bottom),
      Offset(size.width, indicatorRect.bottom),
      edgePaint,
    );
  }

  @override
  bool shouldRepaint(_MinimapPainter oldDelegate) {
    return oldDelegate.barWidths != barWidths ||
        oldDelegate.step != step ||
        oldDelegate.lineStride != lineStride ||
        oldDelegate.foreground != foreground ||
        oldDelegate.background != background;
  }
}
