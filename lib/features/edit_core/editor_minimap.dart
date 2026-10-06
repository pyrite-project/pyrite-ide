import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:code_forge/code_forge/controller.dart';
import 'package:code_forge/code_forge/syntax_highlighter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pyrite_ide/features/edit_core/minimap_geometry.dart';
import 'package:pyrite_ide/features/edit_core/minimap_highlight.dart';
import 'package:re_highlight/re_highlight.dart' show Mode;

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

/// Alpha of a bar segment outside the viewport and inside it.
///
/// The gap between the two is part of the viewport cue, so it has to read at
/// a glance — but the dim state also carries the colors of everything the
/// viewport is *not* showing, and a large document is almost all dim. An
/// alpha that made a small file's colors legible (where the viewport covers
/// the whole panel and every bar is bright) washed a long file out to
/// near-invisible: 95/255 was barely a third of the token color. The two
/// states stay far enough apart to mark the band — with [_bandFillAlpha]
/// underneath to hold the cue where no bars exist — while both keep the
/// theme's hues readable.
const int _dimSegmentAlpha = 150;
const int _brightSegmentAlpha = 240;

/// Alpha of the faint fill drawn under the viewport band.
///
/// The bright bars are the viewport cue wherever bars exist, but a blank
/// stretch — a blank line, or a document whose re-record is still debouncing
/// after an edit — has no bars to brighten, and the cue would vanish exactly
/// there. The fill marks the same line range the bright bars are clipped to,
/// so it cannot drift from them: both come from the editor's
/// first-visible-line report, the same line indices the bars are drawn from.
const int _bandFillAlpha = 30;

/// Left inset of every bar, so nothing touches the minimap's edge.
const double _barInset = 2;

/// Code minimap shown over the editor it wraps.
///
/// The whole document is compressed into the visible panel — the map itself
/// never scrolls, so every part of the file is always on it. That is the
/// fit-to-panel trade: position on the map *is* position in the file, and in
/// exchange a long document's bars get thin (see [minimapLineStride]).
///
/// The shell deliberately does **not** hand the editor a shared
/// [ScrollController]: [CodeForge] recreates its whole subtree whenever its
/// key changes (tab switch, theme change), and during such a remount the
/// outgoing — deactivated but not yet disposed — scroll position stays
/// attached while the incoming one attaches too, which trips ScrollController's
/// `_positions.length == 1` assertion the moment anything reads `.position`.
///
/// Instead the shell listens to vertical [ScrollNotification]s bubbling out of
/// the editor and re-reads the viewport's line range off the renderer when
/// they arrive — the range the viewport highlight is drawn from. The editor
/// keeps its own scroll controller and scrollbar exactly as without the
/// minimap.
///
/// Interaction model: the minimap is interactive (tap centers the clicked
/// region, dragging scrubs scrollbar-style) but its own look never changes on
/// hover. Hovering instead raises
/// [CodeForgeController.scrollbarForcedVisible], so the editor's **native**
/// scrollbar — original decoration, original behavior — appears in the strip
/// to the right of the map that the shell leaves uncovered for it.
///
/// The viewport is marked the way VS Code marks it with the slider hidden:
/// the bars of the lines currently on screen are painted brighter, over a
/// faint fill that keeps the range readable where no bars exist — blank
/// lines (see [_bandFillAlpha]). Both the bright clip and the fill come from
/// the editor's first-visible-line report, the same line indices the bars
/// are drawn from, so neither can drift from the other on a folded or
/// wrapped document.
///
/// Bars are colored by the file's own syntax theme: the shell builds a second
/// [SyntaxHighlighter] from the same grammar and theme map the editor itself
/// was given, and each bar is drawn as one small rect per colored stretch of
/// its line (see `minimapColorSpans`). That highlighter is private to the
/// minimap — the engine's is untouched and keeps its LSP semantic tokens,
/// which the minimap does not reflect.
///
/// Three details of that geometry keep the colors legible rather than merely
/// present, and each one mirrors VS Code:
///
/// * One **device** pixel per character, so adjacent token colors never share
///   a pixel. See [_referenceChars].
/// * Whole device pixels vertically, so a bar is never blended across two rows
///   by the rasterizer. See `_buildBars`.
/// * Whitespace is left unpainted, so indentation reads as structure. See
///   `withoutWhitespace`.
///
/// Because a colored bar is several rects instead of one, the bar layer is
/// recorded into two [ui.Picture]s — dim and bright — and rebuilt only when
/// the document, the geometry, or the theme changes; repainting is then two
/// `drawPicture` calls plus a clip, instead of walking every sampled line.
/// The document is always recorded whole — that is what makes the map
/// fit-to-panel and means no edit or scroll can ever outrun the recording —
/// with the rect count bounded by the same sampling that bounds any layer:
/// past [_maxBars] lines, consecutive lines share a bar.
///
/// Line bars assume one uniform height per line, so with wrapping on a bar is
/// an approximation: it stands for the whole line however many screen lines
/// that line wraps onto. That is the same trade VS Code makes, and the bars
/// still answer "roughly where am I" because they stay proportional to line
/// index. The viewport range itself is not a guess: it comes straight from
/// the editor ([CodeForgeController.firstVisibleLine] and
/// [CodeForgeController.visibleLineCount]), which the renderer computes from
/// the real per-line geometry, folds included.

class MinimapEditorShell extends StatefulWidget {
  const MinimapEditorShell({
    super.key,
    required this.controller,
    required this.enabled,
    required this.lineWrap,
    required this.foreground,
    required this.background,
    required this.editorTheme,
    required this.language,
    required this.baseTextStyle,
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

  /// The resolved editor theme and grammar the editor itself is running with.
  ///
  /// The minimap feeds these to a [SyntaxHighlighter] of its own so a bar can
  /// carry the same colors as the code it stands for. Only what colors the bars
  /// matters, so [baseTextStyle] is read for its font metrics and to resolve a
  /// span whose theme entry has no color of its own.
  final Map<String, TextStyle> editorTheme;
  final Mode language;
  final TextStyle baseTextStyle;

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
                viewportRange: _viewportRange,
                foreground: widget.foreground,
                background: widget.background,
                editorTheme: widget.editorTheme,
                language: widget.language,
                baseTextStyle: widget.baseTextStyle,
                estimatedLineHeight: widget.estimatedLineHeight,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One line of the bar layer: where it sits vertically, how tall it is, and
/// the colored runs it is drawn from.
class _MinimapBar {
  const _MinimapBar(this.top, this.height, this.segments);

  final double top;
  final double height;
  final List<_MinimapSegment> segments;
}

/// One colored stretch of a line, in minimap pixels.
class _MinimapSegment {
  const _MinimapSegment(this.left, this.right, this.color);

  final double left;
  final double right;
  final Color color;
}

class _MinimapView extends StatefulWidget {
  const _MinimapView({
    required this.controller,
    required this.viewportRange,
    required this.foreground,
    required this.background,
    required this.editorTheme,
    required this.language,
    required this.baseTextStyle,
    required this.estimatedLineHeight,
  });

  final CodeForgeController controller;

  /// The editor's visible line range, owned by the shell because the shell is
  /// what hears the scroll notifications.
  final ValueNotifier<({int first, int count})?> viewportRange;
  final Color foreground;
  final Color background;

  /// The theme and grammar the editor runs with, so a bar can carry the
  /// colors of the code it stands for.
  final Map<String, TextStyle> editorTheme;
  final Mode language;
  final TextStyle baseTextStyle;
  final double estimatedLineHeight;

  @override
  State<_MinimapView> createState() => _MinimapViewState();
}

class _MinimapViewState extends State<_MinimapView> {
  /// Longest line the minimap shows in full; longer lines cap at the column
  /// edge like VS Code's minimap, whose `maxColumn` defaults to 120.
  static const int _maxColumn = 120;

  /// Columns a full-width bar represents, derived from the width actually
  /// available rather than fixed.
  ///
  /// VS Code hands every character exactly one *device* pixel
  /// (`minimapCharWidth = minimapScale / pixelRatio`), so a colored stretch
  /// never lands on a fraction of a pixel no matter the display's density.
  /// Fitting a fixed 120 columns into a 76 pixel panel instead crams two and a
  /// half characters onto every pixel, and adjacent token colors blend into one
  /// another — the colors are there, but they cannot be told apart.
  static int _referenceChars(double devicePixelRatio) {
    return math.max(
      1,
      math.min(_maxColumn, (_usableWidth * devicePixelRatio).floor()),
    );
  }

  /// Width a bar can span, between the insets on both edges.
  static double get _usableWidth => kMinimapWidth - 2 * _barInset;

  /// Upper bound on painted bars; beyond this, lines are sampled in blocks so
  /// a generated data dump cannot turn every edit's re-record into thousands
  /// of rect draws.
  static const int _maxBars = 6000;

  static const Duration _recomputeDebounce = Duration(milliseconds: 150);

  /// How long the pre-highlight round trip may take before the recording
  /// lands without syntax colors.
  ///
  /// [SyntaxHighlighter.preHighlightLines] runs batches of 50+ lines on a
  /// `compute` isolate, and one wedged isolate would otherwise hold every
  /// later recompute hostage at the same await — the recordings would freeze
  /// at whatever was last recorded. Colors are decoration; the recording must
  /// always land. On timeout the highlighter is dropped (the next recompute
  /// builds a healthy one) and the bars are painted in the plain foreground
  /// until an edit retriggers the highlight.
  static const Duration _preHighlightTimeout = Duration(milliseconds: 8000);

  /// The bar layer recorded twice, once per viewport state.
  ///
  /// A colored bar is several rects rather than one, and they would otherwise
  /// be walked on every repaint that moves the highlight. Recording the layer
  /// once per state turns a scroll frame into two `drawPicture` calls and a
  /// clip. The layer's own geometry is then dropped: the recordings are
  /// everything the painter needs, and keeping the geometry of six thousand
  /// bars alive between edits would cost more than recording them does.
  ui.Picture? _dimPicture;
  ui.Picture? _brightPicture;

  /// Vertical logical pixels one document line occupies — see
  /// [minimapLineStride].
  double _lineStride = 1;

  /// The controller's [CodeForgeController.documentVersion] when the current
  /// recording was built.
  ///
  /// The controller notifies on more than text changes — a selection gesture
  /// ending does too — and a notification that leaves the stride and the text
  /// version untouched has nothing to re-record. Text edits always bump the
  /// version, so comparing it is what lets a no-op notification skip the
  /// several-thousand-rect rebuild it would otherwise start.
  int _recordedDocumentVersion = -1;

  Timer? _debounce;

  /// The minimap's own highlighter, plus a signature of what it was built
  /// from. The resolved editor theme arrives as a brand new map instance on
  /// every build, so comparing identity would report a change on every frame;
  /// the signature reports what actually matters, that a color moved.
  SyntaxHighlighter? _highlighter;
  String? _highlighterSignature;

  /// Bumped as each recompute starts, so one that lost the race — the user
  /// kept typing — drops its result instead of overwriting a newer layer with
  /// an older snapshot.
  int _generation = 0;

  /// Distance from the viewport highlight's top edge to the pointer while a
  /// drag is in progress — scrollbar-style relative dragging. Null when no
  /// drag is active.
  double? _dragGrabOffset;

  /// Height the minimap was last laid out at, watched so a resize refreshes
  /// the line stride derived from it.
  double? _laidOutHeight;

  /// Density the bar layer was built for. Bar geometry is quantized to whole
  /// device pixels, so a monitor change has to rebuild it — the alternative is
  /// a layer whose rects no longer land on pixel boundaries, which is exactly
  /// the softness the quantization exists to remove.
  double _devicePixelRatio = 1;

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
      // The highlighter reads line text through the old controller.
      _highlighterSignature = null;
      _recomputeBars();
      return;
    }
    if (_highlighterSignature != _computeHighlighterSignature()) {
      // A theme or a grammar change recolors every bar. Switching the editor
      // theme also remounts the editor, so its own controller would ask for a
      // recompute anyway, but a theme can also arrive without one.
      _scheduleRecompute();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleRecompute);
    _debounce?.cancel();
    _highlighter?.dispose();
    _dimPicture?.dispose();
    _brightPicture?.dispose();
    super.dispose();
  }

  void _scheduleRecompute() {
    _debounce?.cancel();
    _debounce = Timer(_recomputeDebounce, _recomputeBars);
  }

  /// Runs the recompute with a guard around everything, including the
  /// sampling that runs before the highlight await.
  ///
  /// The callers fire this from timers and post-frame callbacks and discard
  /// the returned future, so an exception here would vanish into the zone's
  /// unhandled-error handler and — worse — leave the recordings stale with
  /// nothing in the console to say why. A failed round logs and lands
  /// nothing; the next trigger retries.
  Future<void> _recomputeBars() async {
    try {
      await _recomputeBarsUnchecked();
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('minimap: recompute failed: $e\n$stack');
      }
    }
  }

  Future<void> _recomputeBarsUnchecked() async {
    if (!mounted) return;
    final controller = widget.controller;
    final lineCount = controller.lineCount;
    if (lineCount <= 0) {
      setState(_clearBars);
      return;
    }
    final lineStride = minimapLineStride(
      panelHeight: _minimapHeight(),
      lineCount: lineCount,
      devicePixelRatio: _devicePixelRatio,
    );
    final signature = _computeHighlighterSignature();

    // Nothing the layer is drawn from moved: the stride and the highlighter
    // are as recorded, and the text version is too — the controller also
    // notifies on changes, like a selection gesture ending, that leave every
    // bar identical. Recording several thousand bars costs real frames, so a
    // no-op notification stops here.
    if (_dimPicture != null &&
        _brightPicture != null &&
        lineStride == _lineStride &&
        signature == _highlighterSignature &&
        controller.documentVersion == _recordedDocumentVersion) {
      return;
    }

    final generation = ++_generation;
    final step = math.max(1, (lineCount / _maxBars).ceil());
    var highlighter = _resolveHighlighter();
    var highlightTimedOut = false;

    // One snapshot of every sampled line, taken up front. Highlighting below
    // is asynchronous, and reading the text again afterwards could pair a
    // span with a different line than the one it was computed for.
    final sampled = <int, String>{};
    for (var line = 0; line < lineCount; line += step) {
      sampled[line] = controller.getLineText(line);
    }

    try {
      // The whole document is handed to the highlighter, but only the sampled
      // lines carry text: the rest are blanks, which cost nothing to highlight
      // while still letting the grammar engine move the real work off the UI
      // thread. The multi-line tracker keeps reading the real text through the
      // provider attached in [_resolveHighlighter], so a triple-quoted string
      // or a block comment stays continuous across the gaps in the sampling.
      await highlighter
          .preHighlightLines(0, lineCount - 1, (line) {
            if (line % step != 0) return '';
            return sampled[line] ?? '';
          })
          .timeout(
            _preHighlightTimeout,
            onTimeout: () {
              // The isolate round trip wedged. The engine joins in-flight
              // requests at the same version, so waiting longer would chain
              // every later recompute to the same dead future — while the
              // recording, the only thing the map is drawn from, never lands.
              // Drop the highlighter (the next recompute builds a healthy one)
              // and let this round paint plain bars.
              if (kDebugMode) {
                debugPrint(
                  'minimap: pre-highlight timed out after '
                  '${_preHighlightTimeout.inMilliseconds} ms; '
                  'recording plain bars',
                );
              }
              _dropHighlighter();
              highlightTimedOut = true;
            },
          );
    } catch (_) {
      // Colors are decoration. If the grammar cannot run, the spans read below
      // come back unstyled and every bar falls back to the plain foreground —
      // the look the minimap had before it had colors.
    }
    if (!mounted || generation != _generation) return;

    // The picture is the whole document at panel scale: the stride
    // guarantees `lineCount * lineStride` fits the panel (see
    // [minimapLineStride]), so the painter draws it at the top of the panel
    // with no positioning of its own.
    final height = lineCount * lineStride;
    // The only difference between the colored and the plain layer is where
    // the stretches come from: the highlighter, or one plain run per line.
    // The plain form is the fallback for a round whose pre-highlight wedged:
    // the recording must land (the map's whole job is answering "where am
    // I"), and a per-line synchronous re-highlight on the UI thread is
    // exactly the risk the timeout exists to avoid — a line that loops the
    // tokenizer would hang the thread the same way it hung the isolate.
    // Colors return on the next edit, which re-runs the highlight against a
    // fresh highlighter.
    final spansFor = highlightTimedOut
        ? (int line, String text) => withoutWhitespace(
            minimapColorSpans(null, text, plainColor: widget.foreground),
            text,
          )
        : (int line, String text) => withoutWhitespace(
            minimapColorSpans(
              highlighter.getLineSpan(line, text),
              text,
              plainColor: widget.foreground,
            ),
            text,
          );
    final bars = _buildBars(sampled, step, lineStride, spansFor);
    final pictures = _recordBarLayer(bars, Size(kMinimapWidth, height));
    setState(() {
      _lineStride = lineStride;
      _recordedDocumentVersion = controller.documentVersion;
      _dimPicture?.dispose();
      _brightPicture?.dispose();
      _dimPicture = pictures.$1;
      _brightPicture = pictures.$2;
    });
  }

  void _clearBars() {
    _lineStride = 1;
    _recordedDocumentVersion = -1;
    _dimPicture?.dispose();
    _brightPicture?.dispose();
    _dimPicture = null;
    _brightPicture = null;
  }

  /// Discards the current highlighter so the next [_resolveHighlighter]
  /// builds a fresh one.
  ///
  /// Used when the pre-highlight round trip wedges: the instance's in-flight
  /// join state is what would chain later recomputes to the dead future, and
  /// a brand-new instance starts with none. Disposing mid-flight is safe —
  /// the engine's [SyntaxHighlighter.dispose] only clears its caches, and a
  /// late isolate result writing into them lands on an instance about to be
  /// dropped.
  void _dropHighlighter() {
    _highlighter?.dispose();
    _highlighter = null;
    _highlighterSignature = null;
  }

  /// The minimap's highlighter, kept across rebuilds whose grammar and theme
  /// colors are unchanged.
  SyntaxHighlighter _resolveHighlighter() {
    final signature = _computeHighlighterSignature();
    final existing = _highlighter;
    if (existing != null && signature == _highlighterSignature) return existing;
    existing?.dispose();
    // `languageId` is left unset exactly as the editor leaves it: the semantic
    // tokens that would use it come from the LSP server, and the minimap draws
    // grammar colors only. The multi-line tracker falls back to the grammar
    // name, which is what the editor's own lines resolve on.
    final created = SyntaxHighlighter(
      language: widget.language,
      editorTheme: widget.editorTheme,
      baseTextStyle: widget.baseTextStyle,
    );
    created.attachLineTextProvider(widget.controller.getLineText);
    _highlighter = created;
    _highlighterSignature = signature;
    return created;
  }

  /// What the highlighter's output depends on: the grammar, the colors its
  /// theme resolves scopes through, and the base style unstyled runs fall
  /// back to.
  String _computeHighlighterSignature() {
    final base = widget.baseTextStyle;
    final buffer = StringBuffer(
      '${widget.language.name};${base.fontSize};${base.fontFamily};${base.color}',
    );
    for (final entry in widget.editorTheme.entries) {
      final style = entry.value;
      buffer.write(';${entry.key}:${style.color}:${style.fontWeight}');
    }
    return buffer.toString();
  }

  /// Turns every sampled line into a bar: where it sits, how tall it is, and
  /// one segment per colored stretch [spansFor] resolved for it.
  ///
  /// Geometry is quantized to whole device pixels in both directions. A bar
  /// that straddles a pixel boundary is blended across two rows by the
  /// rasterizer, and blended is exactly what a syntax color must not be. On
  /// a document long enough to compress the stride below a device pixel (see
  /// [minimapLineStride]) several lines land on one row whatever the
  /// quantization does — the snapping keeps every shorter document crisp.
  ///
  /// Each bar's height runs from its own snapped top to the snapped top of
  /// the next sampled line — rather than being rounded on its own — which is
  /// what makes consecutive bars tile exactly: no seam of background between
  /// them, no overlap to blend two lines' colors into each other.
  List<_MinimapBar> _buildBars(
    Map<int, String> sampled,
    int step,
    double lineStride,
    List<MinimapColorSpan> Function(int line, String text) spansFor,
  ) {
    final dpr = _devicePixelRatio;
    final charWidth = _usableWidth / _referenceChars(dpr);
    final bars = <_MinimapBar>[];
    // `sampled` was filled in ascending line order, which is also what the
    // highlighter's multi-line state needs: it answers a line from the
    // construct the line above left open.
    for (final entry in sampled.entries) {
      final text = entry.value;
      if (text.isEmpty) continue;

      // Whole device pixels, from the snapped top of this bar to the snapped
      // top of the next sampled line. Bars are positioned from line 0, which
      // is also where the panel starts — the recording and the panel share
      // one coordinate system.
      final topDevice = _snapToDevicePixel(entry.key * lineStride, dpr);
      final bottomDevice = _snapToDevicePixel(
        (entry.key + step) * lineStride,
        dpr,
      );
      final height = math.max(bottomDevice - topDevice, 1 / dpr);

      final segments = <_MinimapSegment>[];
      for (final span in spansFor(entry.key, text)) {
        segments.add(
          _MinimapSegment(
            _barInset + span.start * charWidth,
            _barInset + math.min(_usableWidth, span.end * charWidth),
            span.color,
          ),
        );
      }
      if (segments.isEmpty) continue;
      bars.add(_MinimapBar(topDevice / dpr, height, segments));
    }
    return bars;
  }

  /// The nearest whole device pixel, in logical pixels.
  static double _snapToDevicePixel(double logical, double dpr) =>
      (logical * dpr).roundToDouble() / dpr;

  /// Records the bar layer twice, at the two alphas the viewport states use.
  ///
  /// No density compensation is applied, and there is deliberately nothing to
  /// compensate for: the rasterizer never sees a bar thinner than a device
  /// pixel, because a sub-pixel bar is quantized up to a whole one. Neighbouring
  /// bars then land on the same pixel row and composite toward each other,
  /// which is where a long document's coverage comes from — scaling alpha on
  /// top of that would push both viewport states to opaque and erase the only
  /// viewport cue the minimap has.
  (ui.Picture, ui.Picture) _recordBarLayer(List<_MinimapBar> bars, Size size) {
    return (
      _recordBars(bars, size, _dimSegmentAlpha),
      _recordBars(bars, size, _brightSegmentAlpha),
    );
  }

  ui.Picture _recordBars(List<_MinimapBar> bars, Size size, int alpha) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // One paint per color rather than one per segment: a line of keywords
    // would otherwise allocate a few thousand of them on every edit.
    final paints = <Color, Paint>{};
    for (final bar in bars) {
      // Bars are in line order, so the first one past the bottom edge ends the
      // document as far as this recording is concerned.
      if (bar.top > size.height) break;
      for (final segment in bar.segments) {
        final paint = paints.putIfAbsent(
          segment.color,
          () => Paint()..color = segment.color.withAlpha(alpha),
        );
        canvas.drawRect(
          Rect.fromLTRB(
            segment.left,
            bar.top,
            segment.right,
            bar.top + bar.height,
          ),
          paint,
        );
      }
    }
    return recorder.endRecording();
  }

  double _minimapHeight() {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : 400.0;
  }

  /// How many lines the viewport spans — used to center a tap and to know the
  /// last line the viewport can be pushed down to.
  int _viewportLineCount() {
    final range = widget.viewportRange.value;
    if (range != null) return math.max(1, range.count);
    // The fallback estimate divides the panel's own height: the map is
    // stretched over the editor's full height, so its height is the
    // viewport's to the same accuracy the estimate needs.
    if (_lineHeight <= 0) return 1;
    return math.max(1, (_minimapHeight() / _lineHeight).round());
  }

  /// Geometry of the painted viewport highlight, in panel pixels; null before
  /// the editor reports a viewport range or with an empty document.
  ({double top, double height})? _highlightGeometry() {
    final range = widget.viewportRange.value;
    if (range == null || _lineStride <= 0) return null;
    return minimapViewportBand(
      first: range.first,
      count: range.count,
      lineStride: _lineStride,
      panelHeight: _minimapHeight(),
    );
  }

  /// Scrollbar-style drag: the pointer keeps its grab point on the highlight,
  /// so the document moves exactly with the pointer. Drives the editor
  /// through [CodeForgeController.jumpToLine], which is instant and
  /// top-aligning — [CodeForgeController.scrollToLine] starts a 300 ms
  /// centered animation per call and lags behind the pointer.
  void _onDragStart(DragStartDetails details) {
    final y = details.localPosition.dy;
    final geometry = _highlightGeometry();
    _dragGrabOffset = geometry == null
        ? 0
        : (y >= geometry.top && y <= geometry.top + geometry.height)
        ? y - geometry.top
        // Pressed outside the highlight: center it on the pointer, then keep
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
    if (lineCount <= 0 || _lineStride <= 0) return;
    // The band's top edge tracks the pointer one to one: the band sits at
    // `first * stride` (see [minimapViewportBand]), so the viewport that puts
    // it at the pointer is the pointer's position read off in lines.
    final target = math.min(
      math.max(((y - grab) / _lineStride).round(), 0),
      math.max(0, lineCount - _viewportLineCount()),
    );
    try {
      widget.controller.jumpToLine(target);
    } on StateError {
      // The editor has not mounted its renderer yet (keyed remount in
      // progress); the next drag update will land once it is back.
    }
  }

  /// A tap jumps so the clicked document region sits in the middle of the
  /// viewport, VSCode-minimap style.
  void _jumpTo(double minimapY) {
    final lineCount = widget.controller.lineCount;
    if (lineCount <= 0 || _lineStride <= 0) return;
    // Half the visible lines, taken from the editor rather than from
    // `viewportPixels / lineHeight`: with wrapping on that division does not
    // yield a line count, so the tap would land a screenful off.
    final viewportLines = _viewportLineCount();
    // Clamped to the last line that can sit at the top of a viewport, so a
    // tap on the last line of the map scrolls to the end of the document
    // instead of parking that line at the top of the editor.
    final lastLine = math.max(0, lineCount - viewportLines);
    final line = math.min(
      math.max((minimapY / _lineStride).round(), 0),
      math.max(0, lineCount - 1),
    );
    final target = math.min(
      math.max((line - viewportLines / 2).round(), 0),
      lastLine,
    );
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
            builder: (context, constraints) {
              // The stride is derived from the minimap's laid-out height, so a
              // resize has to refresh it — a stale stride silently rescales
              // every bar and desynchronizes the drag from what is painted. The
              // recordings have to follow: a picture draws at the size it was
              // recorded at.
              if (constraints.maxHeight != _laidOutHeight) {
                _laidOutHeight = constraints.maxHeight;
                _scheduleRecompute();
              }
              final dpr = MediaQuery.devicePixelRatioOf(context);
              if (dpr != _devicePixelRatio) {
                _devicePixelRatio = dpr;
                _scheduleRecompute();
              }
              return CustomPaint(
                size: Size(kMinimapWidth, constraints.maxHeight),
                painter: _MinimapPainter(
                  viewportRange: widget.viewportRange,
                  lineStride: _lineStride,
                  background: widget.background,
                  foreground: widget.foreground,
                  dimPicture: _dimPicture,
                  brightPicture: _brightPicture,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.viewportRange,
    required this.lineStride,
    required this.background,
    required this.foreground,
    required this.dimPicture,
    required this.brightPicture,
  }) : super(repaint: viewportRange);

  /// `(first line, line count)` for the editor's current viewport, or null
  /// before the editor has been laid out. Fed from the renderer, which knows
  /// the real per-line heights; listened to, so the band tracks scrolling
  /// without a widget rebuild.
  final ValueNotifier<({int first, int count})?> viewportRange;
  final double lineStride;
  final Color background;
  final Color foreground;
  final ui.Picture? dimPicture;
  final ui.Picture? brightPicture;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = background.withAlpha(_overlayBackgroundAlpha),
    );

    final dim = dimPicture;
    final bright = brightPicture;
    if (dim == null || bright == null) return;

    // The recording is the whole document at panel scale, drawn from the top
    // of the panel — there is no map position to translate, because the map
    // never scrolls. The clip bounds a picture recorded before the most
    // recent shrink (re-records are debounced) to the panel.
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPicture(dim);
    canvas.restore();

    // The lines inside the viewport are drawn brighter — the same one-cue
    // marking VS Code shows while its slider is hidden.
    //
    // The range comes from the editor rather than from dividing the scroll
    // offset by the line height: with wrapping on, lines have different
    // heights and that division yields a position that is not a line number.
    // The renderer computes the real range from its own layout, folds
    // included.
    final viewport = viewportRange.value;
    if (viewport == null) return;

    final band = minimapViewportBand(
      first: viewport.first,
      count: viewport.count,
      lineStride: lineStride,
      panelHeight: size.height,
    );
    final bandRect = Rect.fromLTRB(
      0,
      band.top,
      size.width,
      band.top + band.height,
    );

    // The fill keeps the band readable where no bars exist to brighten.
    canvas.drawRect(
      bandRect,
      Paint()..color = foreground.withAlpha(_bandFillAlpha),
    );

    // Both states are recordings of the same layer, so the highlight costs a
    // clip and one `drawPicture` rather than a second walk over every bar.
    // Picture coordinates are panel coordinates — the recording starts at
    // line 0 and the panel shows line 0 at its top — so the band clips
    // directly, with no translation.
    canvas.save();
    canvas.clipRect(bandRect);
    canvas.drawPicture(bright);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MinimapPainter oldDelegate) {
    return oldDelegate.lineStride != lineStride ||
        oldDelegate.background != background ||
        oldDelegate.foreground != foreground ||
        !identical(oldDelegate.dimPicture, dimPicture) ||
        !identical(oldDelegate.brightPicture, brightPicture);
  }
}
