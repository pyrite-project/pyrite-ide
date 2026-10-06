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
/// The map scales at a **fixed** per-line pitch and scrolls, the way VS Code's
/// `proportional` minimap does: a document taller than the panel is a window
/// onto the file that follows the viewport, rather than being squeezed until
/// all of it fits. The difference shows on any long file — compression drives
/// the stride below a device pixel and the map dissolves into a smear, where a
/// fixed pitch keeps every bar the same crisp three pixels as a short file's
/// and lets the map show one screenful of the file at full fidelity.
///
/// Two layouts follow from that, and which one is in force is decided in
/// [minimapLayout]: a document that fits is drawn whole, with the viewport
/// marked on it; one that does not becomes a window, and the viewport band
/// turns into the slider that decides where the window sits.
///
/// The window is what makes the band's containment the load-bearing
/// invariant — the map moves under the band, so a band placed without
/// reference to the window would slide off the panel or sit over the wrong
/// lines. [minimapLayout] derives the window and the band together from one
/// slider position, and the painter, the tap handler and the drag handler all
/// read that same layout, so none of them can drift from the others.
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
/// The viewport is marked the way VS Code marks it with the slider drawn as
/// the highlight rather than as a separate widget: the bars of the lines
/// currently on screen are painted brighter, over a faint fill that keeps the
/// range readable where no bars exist — blank lines (see [_bandFillAlpha]).
/// Both the bright clip and the fill come from the editor's first-visible-line
/// report, the same line indices the bars are drawn from, so neither can drift
/// from the other on a folded or wrapped document.
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
/// the document, the geometry, the window, or the theme changes; repainting is
/// then two `drawPicture` calls plus a clip, instead of walking every sampled
/// line. Since the map scrolls, the recording covers a **window** of lines
/// rather than the document: see `_recordWindow` for how wide that window is
/// and why scrolling does not force a re-record on every line moved.
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
  void initState() {
    super.initState();
    // The range below only ever gets read in response to a scroll, so without
    // this a file that has not been scrolled yet would carry no band at all —
    // and on a map that scrolls, a missing range also means a missing window,
    // which would leave the wrong lines on screen rather than merely an
    // unhighlighted correct one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshViewportRange();
    });
  }

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

  /// Document line drawn at the top of the recorded pictures, and how many
  /// lines they cover — see `_recordWindow`.
  ///
  /// The map scrolls, so the recordings cannot be the whole document: at a
  /// fixed stride a hundred-thousand-line file would be a picture a third of a
  /// million pixels tall. They cover a window instead, and the painter slides
  /// them by `(recordedStart - window start)` so the recorded lines land
  /// exactly where the layout says they go.
  int _recordedStart = 0;
  int _recordedLineCount = 0;

  /// Document line count as of the last recording that landed.
  ///
  /// Cached because [CodeForgeController.lineCount] reads through to the
  /// renderer's rope, which is not there until the editor mounts — asking
  /// before then throws on the null the bridge hands back. The map has to stay
  /// off that path: the count is needed while *building* and *painting*, where
  /// a throw is a crash rather than the logged no-op a failed recompute is.
  /// Only [_recomputeBarsUnchecked] reads it for real, inside its own guard,
  /// and it publishes the answer here, so every other reader — the painter,
  /// hit-testing, the coverage check — reads the cache and keeps showing the
  /// last known map until the editor can answer for itself.
  int _lineCount = 0;

  /// The controller's [CodeForgeController.documentVersion] when the current
  /// recording was built.
  ///
  /// The controller notifies on more than text changes — a selection gesture
  /// ending does too — and a notification that leaves the text version and the
  /// window untouched has nothing to re-record. Text edits always bump the
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

  /// Height the minimap was last laid out at, watched so a resize refreshes the
  /// window derived from it.
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
    widget.viewportRange.addListener(_onViewportChanged);
    // The layout depends on the laid-out minimap height, which does not exist
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
    widget.viewportRange.removeListener(_onViewportChanged);
    _debounce?.cancel();
    _highlighter?.dispose();
    _dimPicture?.dispose();
    _brightPicture?.dispose();
    super.dispose();
  }

  /// Re-records only when scrolling has carried the window out of what is
  /// already on the picture.
  ///
  /// Not every scroll moves the window, so this is deliberately not the
  /// debounced path: the recording is wide enough to stay valid across a whole
  /// screenful of scrolling, and the painter slides it to follow the window, so
  /// the only scroll that costs anything is the one that leaves it behind. By
  /// the time that happens the window has already drifted as far as the
  /// recording reaches, so waiting on a debounce here would only widen the gap
  /// the next recording has to close.
  void _onViewportChanged() {
    if (!mounted) return;
    if (_windowIsRecorded(_layout())) return;
    _debounce?.cancel();
    _recomputeBars();
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
    final layout = _layout(lineCount);
    final window = _recordWindow(layout, lineCount);
    final signature = _computeHighlighterSignature();

    // Nothing the layer is drawn from moved: the window and the highlighter
    // are as recorded, and the text version is too — the controller also
    // notifies on changes, like a selection gesture ending, that leave every
    // bar identical. Recording several thousand bars costs real frames, so a
    // no-op notification stops here.
    if (_dimPicture != null &&
        _brightPicture != null &&
        window.start == _recordedStart &&
        window.count == _recordedLineCount &&
        signature == _highlighterSignature &&
        controller.documentVersion == _recordedDocumentVersion) {
      return;
    }

    final generation = ++_generation;
    final end = window.start + window.count;
    // Sampling is a bound on any single recording, and a windowed map rarely
    // reaches it: a panel holds a few hundred lines at the fixed stride. It
    // stays as the backstop it is for a very short stride, say a very tall
    // window on a very dense display.
    final step = math.max(1, (window.count / _maxBars).ceil());
    var highlighter = _resolveHighlighter();
    var highlightTimedOut = false;

    // One snapshot of every sampled line, taken up front. Highlighting below
    // is asynchronous, and reading the text again afterwards could pair a
    // span with a different line than the one it was computed for.
    final sampled = <int, String>{};
    for (var line = window.start; line < end; line += step) {
      sampled[line] = controller.getLineText(line);
    }

    try {
      // Only the window is handed to the highlighter, and only the sampled
      // lines in it carry text: the rest are blanks, which cost nothing to
      // highlight while still letting the grammar engine move the real work
      // off the UI thread. The multi-line tracker keeps reading the real text
      // through the provider attached in [_resolveHighlighter], so a
      // triple-quoted string or a block comment stays continuous even where
      // the window starts in the middle of one.
      await highlighter
          .preHighlightLines(window.start, end - 1, (line) {
            if (line < window.start || line >= end) return '';
            if ((line - window.start) % step != 0) return '';
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

    // The picture covers the window, not the document: line [_recordedStart]
    // sits at its top, and the painter slides the whole thing down or up as
    // the window moves (see `_windowIsRecorded`).
    final height = window.count * layout.lineStride;
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
    final bars = _buildBars(sampled, window, step, layout.lineStride, spansFor);
    final pictures = _recordBarLayer(bars, Size(kMinimapWidth, height));
    setState(() {
      _lineCount = lineCount;
      _recordedStart = window.start;
      _recordedLineCount = window.count;
      _recordedDocumentVersion = controller.documentVersion;
      _dimPicture?.dispose();
      _brightPicture?.dispose();
      _dimPicture = pictures.$1;
      _brightPicture = pictures.$2;
    });
  }

  void _clearBars() {
    // The document reported no lines, so the cached count goes with the
    // recordings: everything that reads the cache has to agree with what is
    // actually on the picture.
    _lineCount = 0;
    _recordedStart = 0;
    _recordedLineCount = 0;
    _recordedDocumentVersion = -1;
    _dimPicture?.dispose();
    _brightPicture?.dispose();
    _dimPicture = null;
    _brightPicture = null;
  }

  /// The window's position and geometry for the viewport as it stands now.
  ///
  /// The painter derives the very same layout from the same [minimapLayout]
  /// call, which is the point: the map, the band and the hit-testing all read
  /// one function, so the line a tap names cannot disagree with the line the
  /// band is sitting on.
  ///
  /// The panel height comes from [_laidOutHeight] — the very value the
  /// painter's `size` is built from in [build] — and never from
  /// [context.findRenderObject]. Those are two sources for one number, and the
  /// recording window is sized by a share of it while the band is placed by
  /// another share of it: any disagreement between them scales the map and the
  /// highlight differently, which reads as the map scrolling at the wrong rate.
  ///
  /// [lineCount] defaults to the cached [_lineCount] rather than asking the
  /// controller, which throws before the editor mounts; only
  /// [_recomputeBarsUnchecked] has a safe moment to read the real one, and it
  /// passes it here directly.
  MinimapLayout _layout([int? lineCount]) {
    final range = widget.viewportRange.value;
    return minimapLayout(
      panelHeight: _panelHeight,
      lineCount: lineCount ?? _lineCount,
      devicePixelRatio: _devicePixelRatio,
      first: range?.first ?? 0,
      count: range?.count ?? 1,
    );
  }

  /// The panel's own height, shared with the painter.
  ///
  /// [_laidOutHeight] is written from the same `constraints.maxHeight` the
  /// painter is sized by, and is refreshed before the recompute that a resize
  /// triggers, so it is the one number both sides can agree on. Only the very
  /// first layout, before [build] has run once, has to guess.
  double get _panelHeight => _laidOutHeight ?? 400.0;

  /// The span of lines to record so the panel can always be filled from what
  /// is already on the picture.
  ///
  /// The window gets a screenful of slack on its trailing side and is snapped
  /// down to a multiple of that same screenful, which is what stops a scroll
  /// from asking for a new recording every single line: the recorded span
  /// stays valid for a whole panel's worth of movement, and only then does the
  /// window move to a new one. Snapping down rather than to the window's own
  /// position is what keeps the recorded span guaranteed to *cover* the window
  /// that asked for it.
  ({int start, int count}) _recordWindow(MinimapLayout layout, int lineCount) {
    final page = math.max(1, layout.linesFitting);
    final start = (layout.startLine ~/ page) * page;
    final end = math.min(lineCount, start + 2 * page);
    return (start: start, count: math.max(1, end - start));
  }

  /// Whether the current recordings still cover [layout]'s window.
  ///
  /// Past the end of the document there is nothing to record, so a window that
  /// runs off it counts as covered — otherwise the last screenful of a file
  /// would ask for a new recording on every line and get one, since a span
  /// ending at the last line can never reach a window that does the same.
  bool _windowIsRecorded(MinimapLayout layout) {
    if (_dimPicture == null || _brightPicture == null) return false;
    if (layout.startLine < _recordedStart) return false;
    final windowEnd = layout.startLine + layout.linesFitting;
    return windowEnd <= _recordedStart + _recordedLineCount ||
        windowEnd >= _lineCount;
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
  /// rasterizer, and blended is exactly what a syntax color must not be. The
  /// stride is fixed at whole device pixels (see [minimapLineStride]), so every
  /// bar lands on a pixel row of its own and the snapping is what keeps the
  /// edges crisp.
  ///
  /// Each bar's height runs from its own snapped top to the snapped top of
  /// the next sampled line — rather than being rounded on its own — which is
  /// what makes consecutive bars tile exactly: no seam of background between
  /// them, no overlap to blend two lines' colors into each other.
  List<_MinimapBar> _buildBars(
    Map<int, String> sampled,
    ({int start, int count}) window,
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
      // top of the next sampled line — both in logical pixels, which is what
      // everything downstream of here works in: the clip against the picture
      // height, the `drawRect` calls, the painter's slide.
      //
      // Bars are positioned from the window's first line rather than from line
      // 0, which is what lets the recording be a window: the picture's own top
      // edge is line [window.start], and the painter shifts the picture so that
      // lands on the panel's top edge.
      final top = minimapBarEdge(
        line: entry.key,
        windowStart: window.start,
        lineStride: lineStride,
        devicePixelRatio: dpr,
      );
      final bottom = minimapBarEdge(
        line: entry.key + step,
        windowStart: window.start,
        lineStride: lineStride,
        devicePixelRatio: dpr,
      );
      final height = math.max(bottom - top, 1 / dpr);

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
      bars.add(_MinimapBar(top, height, segments));
    }
    return bars;
  }

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
    // The fallback estimate divides the panel's own height: the map and the
    // viewport cover the same span of the editor, so the panel's height is the
    // viewport's to the same accuracy the estimate needs.
    if (_lineHeight <= 0) return 1;
    return math.max(1, (_minimapHeight() / _lineHeight).round());
  }

  /// Scrollbar-style drag: the pointer keeps its grab point on the highlight,
  /// so the document moves exactly with the pointer. Drives the editor
  /// through [CodeForgeController.jumpToLine], which is instant and
  /// top-aligning — [CodeForgeController.scrollToLine] starts a 300 ms
  /// centered animation per call and lags behind the pointer.
  void _onDragStart(DragStartDetails details) {
    final y = details.localPosition.dy;
    final layout = _layout();
    final bandTop = layout.bandTop;
    final bandBottom = bandTop + layout.bandHeight;
    _dragGrabOffset = (y >= bandTop && y <= bandBottom)
        // Pressed outside the highlight: center it on the pointer, then keep
        // dragging relative from there.
        ? (y - bandTop)
        : layout.bandHeight / 2;
    _applyDrag(y);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragGrabOffset ??= 0;
    _applyDrag(details.localPosition.dy);
  }

  void _applyDrag(double y) {
    final grab = _dragGrabOffset ?? 0;
    final lineCount = _lineCount;
    if (lineCount <= 0) return;
    final layout = _layout();
    if (layout.lineStride <= 0) return;
    // The band's top edge tracks the pointer one to one: the band sits where
    // its first line is drawn (see [minimapLayout]), so the viewport that puts
    // it at the pointer is the pointer's position read off in lines — measured
    // from the window's top, not from line 0, since the map may be scrolled.
    final first = minimapLineAt(
      y: y - grab,
      startLine: layout.startLine,
      lineStride: layout.lineStride,
      lineCount: lineCount,
    );
    final target = math.min(
      math.max(first, 0),
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
    final lineCount = _lineCount;
    if (lineCount <= 0) return;
    final layout = _layout();
    if (layout.lineStride <= 0) return;
    // Half the visible lines, taken from the editor rather than from
    // `viewportPixels / lineHeight`: with wrapping on that division does not
    // yield a line count, so the tap would land a screenful off.
    final viewportLines = _viewportLineCount();
    // Clamped to the last line that can sit at the top of a viewport, so a
    // tap on the last line of the map scrolls to the end of the document
    // instead of parking that line at the top of the editor.
    final lastLine = math.max(0, lineCount - viewportLines);
    final line = minimapLineAt(
      y: minimapY,
      startLine: layout.startLine,
      lineStride: layout.lineStride,
      lineCount: lineCount,
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
              // The window is derived from the laid-out height, so a resize has to
              // refresh the recordings: a picture draws at the size it was
              // recorded at, and the window's page — its slack, and how far
              // one re-record carries — is a share of the panel.
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
                  lineCount: _lineCount,
                  devicePixelRatio: _devicePixelRatio,
                  recordedStart: _recordedStart,
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
    required this.lineCount,
    required this.devicePixelRatio,
    required this.recordedStart,
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

  /// Document line count and display density, so the painter can derive the
  /// window and the band from the same [minimapLayout] the view's hit-testing
  /// uses. Deriving them here rather than being handed them is the point: a
  /// band drawn from a window somebody else computed is a band that can drift
  /// off the lines it is marking.
  final int lineCount;
  final double devicePixelRatio;

  /// Document line drawn at the top of the recorded pictures.
  final int recordedStart;
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

    final viewport = viewportRange.value;
    final layout = minimapLayout(
      panelHeight: size.height,
      lineCount: lineCount,
      devicePixelRatio: devicePixelRatio,
      first: viewport?.first ?? 0,
      count: viewport?.count ?? 1,
    );

    // The recording starts at [recordedStart], the window starts at
    // [layout.startLine], and the panel shows the window's first line at its
    // own top — so the picture is slid by the difference. Because the bars
    // inside it are placed from [recordedStart], that slide puts every
    // recorded line exactly where the layout says it goes, whether or not the
    // window has drifted since the recording.
    //
    // The clip bounds a picture recorded before the most recent shrink — and
    // one whose window the panel has already scrolled out of — to the panel.
    final shift = (recordedStart - layout.startLine) * layout.lineStride;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(0, shift);
    canvas.drawPicture(dim);
    canvas.restore();

    // Nothing to mark before the editor has reported where it is looking.
    if (viewport == null) return;

    // The lines inside the viewport are drawn brighter — the same one-cue
    // marking VS Code shows while its slider is drawn as the highlight.
    //
    // The range comes from the editor rather than from dividing the scroll
    // offset by the line height: with wrapping on, lines have different
    // heights and that division yields a position that is not a line number.
    // The renderer computes the real range from its own layout, folds
    // included.
    final bandRect = Rect.fromLTRB(
      0,
      layout.bandTop,
      size.width,
      layout.bandTop + layout.bandHeight,
    );

    // The fill keeps the band readable where no bars exist to brighten.
    canvas.drawRect(
      bandRect,
      Paint()..color = foreground.withAlpha(_bandFillAlpha),
    );

    // Both states are recordings of the same layer, so the highlight costs a
    // clip and one `drawPicture` rather than a second walk over every bar.
    // The clip is in panel coordinates and the slide happens under it, so the
    // band selects the bars of the lines it is marking however far the
    // recording trails the window.
    canvas.save();
    canvas.clipRect(bandRect);
    canvas.translate(0, shift);
    canvas.drawPicture(bright);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MinimapPainter oldDelegate) {
    return oldDelegate.lineCount != lineCount ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        oldDelegate.recordedStart != recordedStart ||
        oldDelegate.background != background ||
        oldDelegate.foreground != foreground ||
        !identical(oldDelegate.dimPicture, dimPicture) ||
        !identical(oldDelegate.brightPicture, brightPicture);
  }
}
