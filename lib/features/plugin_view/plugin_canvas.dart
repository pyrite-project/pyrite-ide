import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/sdk/plugin_perf_budget.dart';
import 'package:pyrite_ide/core/sdk/plugin_resources.dart';

/// Signature for a semantic Canvas event crossing back to the plugin.
typedef CanvasEventSink = void Function(Map<String, dynamic> payload);

/// High-performance interactive custom-draw surface for plugin views.
///
/// Two op layers are drawn base-first then overlay on top:
/// * **Base** = [ops] (persistent, mirrored in the ViewModel via snapshot/patch).
/// * **Overlay** = ops pushed through the invoke channel ([pushOps]/[setOps]).
///   The overlay is EPHEMERAL: it lives only in [PluginCanvasState] and is lost
///   on resync / visibility-restore (a fresh mount starts with an empty
///   overlay).
///
/// Interaction (hover highlight, pan/zoom, drag preview, rubber-band selection)
/// is entirely host-local; only the throttled semantic events (tap/drag/hover/
/// pointer) that the plugin subscribed to ever cross the process boundary.
class PluginCanvas extends StatefulWidget {
  const PluginCanvas({
    super.key,
    required this.componentId,
    this.width,
    this.height,
    this.ops = const [],
    this.interactive = false,
    this.viewport = const {},
    this.pluginRootPath,
    this.onTap,
    this.onDrag,
    this.onHover,
    this.onPointer,
  });

  final String componentId;
  final double? width;
  final double? height;

  /// Persistent base ops from `props.ops`.
  final List<Map<String, dynamic>> ops;
  final bool interactive;

  /// Initial viewport values; applied on mount and re-applied when it changes.
  final Map<String, dynamic> viewport;
  final String? pluginRootPath;

  /// Non-null only when the plugin subscribed to the matching event; a null
  /// callback produces zero cross-process traffic for that event.
  final CanvasEventSink? onTap;
  final CanvasEventSink? onDrag;
  final CanvasEventSink? onHover;
  final CanvasEventSink? onPointer;

  @override
  State<PluginCanvas> createState() => PluginCanvasState();
}

/// One element→bounds record for host-local hit testing, in content coords.
class _IndexEntry {
  const _IndexEntry(this.id, this.bounds);
  final String id;
  final Rect bounds;
}

/// Leading-edge + coalesced throttle: fires immediately, then at most once per
/// [window] with the latest coalesced payload.
class _Throttle {
  _Throttle(this.window);
  final Duration window;
  Timer? _timer;
  Map<String, dynamic>? _pending;

  void run(CanvasEventSink emit, Map<String, dynamic> payload) {
    if (_timer == null) {
      emit(payload);
      _timer = Timer(window, () {
        _timer = null;
        final pending = _pending;
        _pending = null;
        if (pending != null) run(emit, pending);
      });
    } else {
      _pending = payload;
    }
  }

  void dispose() {
    discardPending();
  }

  void flush(CanvasEventSink emit) {
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    _pending = null;
    if (pending != null) emit(pending);
  }

  void discardPending() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}

class PluginCanvasState extends State<PluginCanvas> {
  static const _defaultLayer = '';
  static const _tapSlop = 4.0;
  static const _tapMaxDuration = Duration(milliseconds: 300);

  /// Ephemeral overlay layers, in insertion order. Never mirrored in the
  /// ViewModel, so it is discarded on a fresh mount (resync/visibility-restore).
  final Map<String, List<Map<String, dynamic>>> _overlay = {};

  /// Decoded, host-cached images keyed by their `plugin-resource` token.
  final Map<String, ui.Image> _images = {};
  final Set<String> _requestedImages = {};

  final _hoverThrottle = _Throttle(PluginPerfBudget.selectionChangedThrottle);
  final _pointerThrottle = _Throttle(PluginPerfBudget.selectionChangedThrottle);
  final _dragThrottle = _Throttle(PluginPerfBudget.selectionChangedThrottle);

  // Host-owned viewport transform: view = scale * (content + offset).
  double _scale = 1;
  double _minScale = 0.1;
  double _maxScale = 10;
  Offset _offset = Offset.zero;
  bool _panEnabled = false;
  bool _zoomEnabled = false;

  // Element→bounds index (content coords), rebuilt when ops change.
  List<_IndexEntry> _index = const [];
  int _revision = 0;

  // Host-local interaction visuals (never cross the boundary).
  Rect? _hoverRect;
  Rect? _rubberBand;

  // Active pointer bookkeeping.
  int? _activePointer;
  Offset? _downLocal;
  Offset? _lastDragContent;
  DateTime? _downTime;
  bool _dragging = false;
  bool _movedPastSlop = false;

  @override
  void initState() {
    super.initState();
    _applyViewport(widget.viewport);
    _rebuildIndex();
    _requestImages();
  }

  @override
  void didUpdateWidget(covariant PluginCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A patch that changes the viewport resets the transform to the new values.
    if ((!identical(oldWidget.viewport, widget.viewport) &&
            !_mapEquals(oldWidget.viewport, widget.viewport)) ||
        oldWidget.interactive != widget.interactive) {
      _applyViewport(widget.viewport);
    }
    // A patch updating props.ops repaints the base but keeps the overlay.
    if (!identical(oldWidget.ops, widget.ops)) {
      _rebuildIndex();
      _requestImages();
      _revision++;
    }
    if (oldWidget.pluginRootPath != widget.pluginRootPath) {
      _requestedImages.clear();
      _requestImages();
    }
  }

  @override
  void dispose() {
    _hoverThrottle.dispose();
    _pointerThrottle.dispose();
    _dragThrottle.dispose();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }

  // -- Imperative API (invoke channel) --------------------------------------

  /// Appends [ops] to the ephemeral overlay (named [layer] or the default).
  void pushOps(List<Map<String, dynamic>> ops, {String? layer}) {
    final key = layer ?? _defaultLayer;
    (_overlay[key] ??= <Map<String, dynamic>>[]).addAll(ops);
    _afterOverlayChange();
  }

  /// Replaces the ephemeral overlay: one named [layer], or all layers.
  void setOps(List<Map<String, dynamic>> ops, {String? layer}) {
    if (layer == null) {
      _overlay.clear();
      _overlay[_defaultLayer] = List.of(ops);
    } else {
      _overlay[layer] = List.of(ops);
    }
    _afterOverlayChange();
  }

  /// Empties every ephemeral overlay layer; the base is untouched.
  void clear() {
    if (_overlay.isEmpty) return;
    _overlay.clear();
    _afterOverlayChange();
  }

  /// Empties one named ephemeral overlay layer.
  void clearLayer(String layer) {
    if (_overlay.remove(layer) != null) _afterOverlayChange();
  }

  /// Topmost element at content-space ([x], [y]) from the local index, or null.
  Map<String, dynamic>? hitTest(double x, double y) {
    final point = Offset(x, y);
    for (var i = _index.length - 1; i >= 0; i--) {
      final entry = _index[i];
      if (entry.bounds.contains(point)) {
        return {
          'elementId': entry.id,
          'bounds': {
            'x': entry.bounds.left,
            'y': entry.bounds.top,
            'width': entry.bounds.width,
            'height': entry.bounds.height,
          },
        };
      }
    }
    return null;
  }

  void _afterOverlayChange() {
    _rebuildIndex();
    _requestImages();
    if (mounted) setState(() => _revision++);
  }

  // -- Viewport --------------------------------------------------------------

  void _applyViewport(Map<String, dynamic> viewport) {
    double asDouble(Object? v, double fallback) {
      final value = v is num ? v.toDouble() : fallback;
      return value.isFinite ? value : fallback;
    }

    _minScale = asDouble(viewport['minScale'], 0.1);
    if (_minScale <= 0) _minScale = 0.1;
    _maxScale = asDouble(viewport['maxScale'], 10);
    if (_maxScale < _minScale) _maxScale = _minScale;
    _scale = asDouble(viewport['scale'], 1).clamp(_minScale, _maxScale);
    _offset = Offset(
      asDouble(viewport['offsetX'], 0),
      asDouble(viewport['offsetY'], 0),
    );
    _panEnabled = viewport['panEnabled'] is bool
        ? viewport['panEnabled'] as bool
        : widget.interactive;
    _zoomEnabled = viewport['zoomEnabled'] is bool
        ? viewport['zoomEnabled'] as bool
        : widget.interactive;
  }

  Offset _toContent(Offset local) =>
      Offset(local.dx / _scale - _offset.dx, local.dy / _scale - _offset.dy);

  // -- Index building --------------------------------------------------------

  List<Map<String, dynamic>> get _allOps => [
    ...widget.ops,
    for (final layer in _overlay.values) ...layer,
  ];

  void _rebuildIndex() {
    final entries = <_IndexEntry>[];
    _indexOps(_allOps, Matrix4.identity(), entries);
    _index = entries;
  }

  void _indexOps(
    List<Map<String, dynamic>> ops,
    Matrix4 matrix,
    List<_IndexEntry> out, {
    Rect? initialClip,
  }) {
    final stack = <(Matrix4, Rect?)>[];
    var current = matrix.clone();
    Rect? currentClip = initialClip;
    for (final op in ops) {
      switch (op['op']?.toString()) {
        case 'save':
        case 'saveLayer':
          stack.add((current.clone(), currentClip));
        case 'restore':
          if (stack.isNotEmpty) {
            final restored = stack.removeLast();
            current = restored.$1;
            currentClip = restored.$2;
          }
        case 'translate':
          current.translateByDouble(_d(op['dx']), _d(op['dy']), 0, 1);
        case 'scale':
          final sx = _d(op['sx'], 1);
          current.scaleByDouble(sx, op['sy'] is num ? _d(op['sy']) : sx, 1, 1);
        case 'rotate':
          current = current.clone()..multiply(_rotationMatrix(op));
        case 'matrix':
          current.multiply(_affineMatrix(op) ?? Matrix4.identity());
        case 'group':
          final nested = current.clone();
          final transform = _affineMatrix(op);
          if (transform != null) nested.multiply(transform);
          var nestedClip = currentClip;
          final clip = op['clip'];
          if (clip is Map) {
            final clipMap = clip.map((k, v) => MapEntry(k.toString(), v));
            final bounds = _clipBounds(clipMap);
            if (bounds != null) {
              final transformed = MatrixUtils.transformRect(nested, bounds);
              nestedClip = nestedClip?.intersect(transformed) ?? transformed;
            }
          }
          final inner = op['ops'];
          if (inner is List) {
            _indexOps(
              [
                for (final e in inner)
                  if (e is Map) e.map((k, v) => MapEntry(k.toString(), v)),
              ],
              nested,
              out,
              initialClip: nestedClip,
            );
          }
        case 'clip':
          final bounds = _clipBounds(op);
          if (bounds != null) {
            final transformed = MatrixUtils.transformRect(current, bounds);
            currentClip = currentClip?.intersect(transformed) ?? transformed;
          }
        default:
          final id = op['id']?.toString();
          if (id == null || id.isEmpty) continue;
          final local = _localBounds(op);
          if (local == null) continue;
          var bounds = MatrixUtils.transformRect(current, local);
          if (currentClip != null) bounds = bounds.intersect(currentClip);
          if (!bounds.isEmpty) out.add(_IndexEntry(id, bounds));
      }
    }
  }

  Rect? _clipBounds(Map<String, dynamic> op) =>
      switch (op['shape']?.toString()) {
        'rect' || 'rrect' => Rect.fromLTWH(
          _d(op['x']),
          _d(op['y']),
          _d(op['w']),
          _d(op['h']),
        ),
        'path' => _pathBounds(op['commands']),
        _ => null,
      };

  Rect? _localBounds(Map<String, dynamic> op) {
    switch (op['op']?.toString()) {
      case 'line':
        return Rect.fromPoints(
          Offset(_d(op['x1']), _d(op['y1'])),
          Offset(_d(op['x2']), _d(op['y2'])),
        );
      case 'rect':
      case 'oval':
      case 'arc':
        return Rect.fromLTWH(
          _d(op['x']),
          _d(op['y']),
          _d(op['w']),
          _d(op['h']),
        );
      case 'rrect':
        return Rect.fromLTWH(
          _d(op['x']),
          _d(op['y']),
          _d(op['w']),
          _d(op['h']),
        );
      case 'circle':
        return Rect.fromCircle(
          center: Offset(_d(op['cx']), _d(op['cy'])),
          radius: _d(op['r']),
        );
      case 'image':
        final image = _images[op['src']?.toString()];
        final intrinsicWidth = image?.width.toDouble() ?? 0;
        final intrinsicHeight = image?.height.toDouble() ?? 0;
        return Rect.fromLTWH(
          _d(op['x']),
          _d(op['y']),
          _d(op['width'], intrinsicWidth),
          _d(op['height'], intrinsicHeight),
        );
      case 'text':
        return _textBounds(op);
      case 'polyline':
      case 'polygon':
      case 'points':
        return _pointsBounds(op['points']);
      case 'path':
        return _pathBounds(op['commands']);
    }
    return null;
  }

  Rect? _pointsBounds(Object? raw) {
    if (raw is! List || raw.length < 2) return null;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i + 1 < raw.length; i += 2) {
      final x = _d(raw[i]);
      final y = _d(raw[i + 1]);
      minX = x < minX ? x : minX;
      minY = y < minY ? y : minY;
      maxX = x > maxX ? x : maxX;
      maxY = y > maxY ? y : maxY;
    }
    if (minX > maxX) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Rect? _pathBounds(Object? raw) {
    if (raw is! List) return null;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    void note(double x, double y) {
      minX = x < minX ? x : minX;
      minY = y < minY ? y : minY;
      maxX = x > maxX ? x : maxX;
      maxY = y > maxY ? y : maxY;
    }

    for (final command in raw) {
      if (command is! Map) continue;
      final c = command.map((k, v) => MapEntry(k.toString(), v));
      switch (c['c']?.toString()) {
        case 'moveTo':
        case 'lineTo':
          note(_d(c['x']), _d(c['y']));
        case 'quadTo':
          note(_d(c['x1']), _d(c['y1']));
          note(_d(c['x']), _d(c['y']));
        case 'cubicTo':
          note(_d(c['x1']), _d(c['y1']));
          note(_d(c['x2']), _d(c['y2']));
          note(_d(c['x']), _d(c['y']));
      }
    }
    if (minX > maxX) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Rect _textBounds(Map<String, dynamic> op) {
    final painter = _buildTextPainter(op, const ColorScheme.light());
    final maxWidth = op['maxWidth'] is num
        ? _d(op['maxWidth'])
        : double.infinity;
    painter.layout(maxWidth: maxWidth);
    final rect = Rect.fromLTWH(
      _d(op['x']),
      _d(op['y']),
      painter.width,
      painter.height,
    );
    painter.dispose();
    return rect;
  }

  // -- Image decode ----------------------------------------------------------

  void _requestImages() {
    final tokens = <String>{};
    void scan(List<Map<String, dynamic>> ops) {
      for (final op in ops) {
        if (op['op'] == 'image') {
          final src = op['src']?.toString();
          if (src != null) tokens.add(src);
        }
        final inner = op['ops'];
        if (inner is List) {
          scan([
            for (final e in inner)
              if (e is Map) e.map((k, v) => MapEntry(k.toString(), v)),
          ]);
        }
      }
    }

    scan(_allOps);
    for (final stale
        in _images.keys.where((token) => !tokens.contains(token)).toList()) {
      _images.remove(stale)?.dispose();
    }
    _requestedImages.removeWhere((token) => !tokens.contains(token));
    for (final token in tokens) {
      if (_requestedImages.add(token)) unawaited(_decodeImage(token));
    }
  }

  Future<void> _decodeImage(String token) async {
    final assetPath = pluginResourcePath(token);
    final root = widget.pluginRootPath;
    if (assetPath == null || root == null) return;
    final file = resolvePluginAssetFile(root, assetPath);
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      late final ui.FrameInfo frame;
      try {
        frame = await codec.getNextFrame();
      } finally {
        codec.dispose();
      }
      if (!mounted || !_requestedImages.contains(token)) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _images[token]?.dispose();
        _images[token] = frame.image;
        _rebuildIndex();
        _revision++;
      });
    } catch (_) {
      // Unresolved / undecodable images are skipped, never thrown.
    }
  }

  // -- Interaction -----------------------------------------------------------

  void _onPointerDown(PointerDownEvent event) {
    _activePointer = event.pointer;
    _downLocal = event.localPosition;
    _downTime = DateTime.now();
    _movedPastSlop = false;
    _dragging = false;
    final content = _toContent(event.localPosition);
    _lastDragContent = content;
    if (widget.onPointer != null) {
      widget.onPointer!({
        'phase': 'down',
        'pointerId': event.pointer,
        'x': content.dx,
        'y': content.dy,
        'buttons': event.buttons,
      });
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    final down = _downLocal;
    final content = _toContent(event.localPosition);
    if (down != null &&
        !_movedPastSlop &&
        (event.localPosition - down).distance > _tapSlop) {
      _movedPastSlop = true;
    }

    if (widget.onPointer != null) {
      _pointerThrottle.run(widget.onPointer!, {
        'phase': 'move',
        'pointerId': event.pointer,
        'x': content.dx,
        'y': content.dy,
        'buttons': event.buttons,
      });
    }

    // Middle/secondary button pans the viewport (host-local).
    final isPrimary = event.buttons & kPrimaryButton != 0;
    if (widget.interactive && _panEnabled && !isPrimary && _movedPastSlop) {
      setState(() {
        _offset += Offset(event.delta.dx / _scale, event.delta.dy / _scale);
        _revision++;
      });
      return;
    }

    // Primary-button drag reports the semantic drag and shows a host-local
    // rubber-band; the plugin computes any selection itself.
    if (isPrimary && _movedPastSlop) {
      if (!_dragging) {
        _dragging = true;
        _lastDragContent = _toContent(down ?? event.localPosition);
        _emitDrag('start', content, immediate: true);
      }
      _emitDrag('update', content);
      if (widget.interactive && down != null) {
        setState(() {
          _rubberBand = Rect.fromPoints(_toContent(down), content);
          _revision++;
        });
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    final content = _toContent(event.localPosition);
    final down = _downLocal;
    final downTime = _downTime;

    if (_dragging) {
      _emitDrag('end', content, immediate: true);
    } else if (!_movedPastSlop &&
        down != null &&
        downTime != null &&
        DateTime.now().difference(downTime) < _tapMaxDuration &&
        widget.onTap != null) {
      final hit = hitTest(content.dx, content.dy);
      widget.onTap!({
        'x': content.dx,
        'y': content.dy,
        if (hit != null) 'elementId': hit['elementId'],
      });
    }

    if (widget.onPointer != null) {
      widget.onPointer!({
        'phase': 'up',
        'pointerId': event.pointer,
        'x': content.dx,
        'y': content.dy,
        'buttons': event.buttons,
      });
    }

    _activePointer = null;
    _downLocal = null;
    _downTime = null;
    _dragging = false;
    if (_rubberBand != null) {
      setState(() {
        _rubberBand = null;
        _revision++;
      });
    }
  }

  void _emitDrag(String phase, Offset content, {bool immediate = false}) {
    final sink = widget.onDrag;
    if (sink == null) return;
    final previous = _lastDragContent ?? content;
    final payload = {
      'phase': phase,
      'x': content.dx,
      'y': content.dy,
      'dx': content.dx - previous.dx,
      'dy': content.dy - previous.dy,
    };
    _lastDragContent = content;
    // start/end are semantic and sent immediately; update is throttled.
    if (phase == 'start') _dragThrottle.discardPending();
    if (phase == 'end') _dragThrottle.flush(sink);
    if (immediate) {
      sink(payload);
    } else {
      _dragThrottle.run(sink, payload);
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!widget.interactive || !_zoomEnabled) return;
    final focal = event.localPosition;
    final contentFocal = _toContent(focal);
    final factor = event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
    final next = (_scale * factor).clamp(_minScale, _maxScale);
    if (next == _scale) return;
    setState(() {
      _offset = Offset(
        focal.dx / next - contentFocal.dx,
        focal.dy / next - contentFocal.dy,
      );
      _scale = next;
      _revision++;
    });
  }

  void _onHover(PointerHoverEvent event) {
    final content = _toContent(event.localPosition);
    // Host-local hover highlight.
    if (widget.interactive) {
      final hit = hitTest(content.dx, content.dy);
      final next = hit == null
          ? null
          : _index.lastWhere((e) => e.id == hit['elementId']).bounds;
      if (next != _hoverRect) {
        setState(() {
          _hoverRect = next;
          _revision++;
        });
      }
    }
    if (widget.onHover != null) {
      final hit = hitTest(content.dx, content.dy);
      _hoverThrottle.run(widget.onHover!, {
        'x': content.dx,
        'y': content.dy,
        if (hit != null) 'elementId': hit['elementId'],
      });
    }
  }

  void _onExit(PointerExitEvent event) {
    _hoverThrottle.discardPending();
    if (_hoverRect != null) {
      setState(() {
        _hoverRect = null;
        _revision++;
      });
    }
  }

  // -- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    double? validExtent(double? value) =>
        value != null && value.isFinite && value >= 0 ? value : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            validExtent(widget.width) ??
            (constraints.hasBoundedWidth ? constraints.maxWidth : 300.0);
        final height =
            validExtent(widget.height) ??
            (constraints.hasBoundedHeight ? constraints.maxHeight : 200.0);
        final canvas = RepaintBoundary(
          child: CustomPaint(
            size: Size(width, height),
            painter: _CanvasPainter(
              base: widget.ops,
              overlay: [for (final layer in _overlay.values) ...layer],
              scale: _scale,
              offset: _offset,
              scheme: scheme,
              images: _images,
              hoverRect: _hoverRect,
              rubberBand: _rubberBand,
              revision: _revision,
            ),
          ),
        );

        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerSignal: _onPointerSignal,
          child: MouseRegion(
            onHover: _onHover,
            onExit: _onExit,
            child: SizedBox(width: width, height: height, child: canvas),
          ),
        );
      },
    );
  }

  // -- Shared parsing helpers ------------------------------------------------

  static double _d(Object? value, [double fallback = 0]) =>
      value is num ? value.toDouble() : fallback;

  Matrix4 _rotationMatrix(Map<String, dynamic> op) {
    final radians = _d(op['radians']);
    final hasPivot = op['px'] is num || op['py'] is num;
    if (!hasPivot) return Matrix4.rotationZ(radians);
    final px = _d(op['px']);
    final py = _d(op['py']);
    return Matrix4.identity()
      ..translateByDouble(px, py, 0, 1)
      ..multiply(Matrix4.rotationZ(radians))
      ..translateByDouble(-px, -py, 0, 1);
  }

  Matrix4? _affineMatrix(Map<String, dynamic> op) {
    final affine = op['affine'];
    if (affine is List && affine.length == 6) {
      final a = _d(affine[0]);
      final b = _d(affine[1]);
      final c = _d(affine[2]);
      final d = _d(affine[3]);
      final e = _d(affine[4]);
      final f = _d(affine[5]);
      // x' = a*x + c*y + e ; y' = b*x + d*y + f
      return Matrix4.identity()
        ..setValues(a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1);
    }
    final m4 = op['m4'];
    if (m4 is List && m4.length == 16) {
      return Matrix4.fromList([for (final v in m4) _d(v)]);
    }
    // group.transform reuses the affine slot.
    final transform = op['transform'];
    if (transform is List && transform.length == 6) {
      return _affineMatrix({'affine': transform});
    }
    return null;
  }

  static TextPainter _buildTextPainter(
    Map<String, dynamic> op,
    ColorScheme scheme,
  ) {
    final weightValue = op['weight'];
    FontWeight? weight;
    if (weightValue is num) {
      final index = (weightValue.toInt() ~/ 100 - 1).clamp(0, 8);
      weight = FontWeight.values[index];
    } else if (weightValue == 'bold') {
      weight = FontWeight.bold;
    } else if (weightValue == 'normal') {
      weight = FontWeight.normal;
    }
    final align = switch (op['align']?.toString()) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    return TextPainter(
      text: TextSpan(
        text: op['text']?.toString() ?? '',
        style: TextStyle(
          fontSize: _d(op['size'], 14),
          fontFamily: op['family']?.toString(),
          fontWeight: weight,
          fontStyle: op['italic'] == true ? FontStyle.italic : FontStyle.normal,
          color:
              _CanvasPainter.parseColor(op['color']?.toString(), scheme) ??
              scheme.onSurface,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    );
  }

  static bool _mapEquals(Map a, Map b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// Interprets the Canvas v2 op list against a Flutter [Canvas].
///
/// Unknown ops, unparseable colors, and unresolved images are skipped (never
/// thrown). The op stack is auto-balanced at the end of the base list and again
/// at the end of the overlay list.
class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.base,
    required this.overlay,
    required this.scale,
    required this.offset,
    required this.scheme,
    required this.images,
    required this.hoverRect,
    required this.rubberBand,
    required this.revision,
  });

  final List<Map<String, dynamic>> base;
  final List<Map<String, dynamic>> overlay;
  final double scale;
  final Offset offset;
  final ColorScheme scheme;
  final Map<String, ui.Image> images;
  final Rect? hoverRect;
  final Rect? rubberBand;
  final int revision;

  static double _d(Object? value, [double fallback = 0]) =>
      value is num ? value.toDouble() : fallback;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Viewport transform: view = scale * (content + offset).
    canvas.scale(scale);
    canvas.translate(offset.dx, offset.dy);

    _paintList(canvas, base);
    _paintList(canvas, overlay);

    // Host-local visuals, drawn in content space above everything.
    final hover = hoverRect;
    if (hover != null) {
      canvas.drawRect(
        hover,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale
          ..color = scheme.primary.withValues(alpha: 0.9),
      );
    }
    final band = rubberBand;
    if (band != null) {
      canvas.drawRect(
        band,
        Paint()..color = scheme.primary.withValues(alpha: 0.12),
      );
      canvas.drawRect(
        band,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale
          ..color = scheme.primary,
      );
    }
    canvas.restore();
  }

  /// Draws [ops] and auto-restores any unbalanced save-scope at the end.
  void _paintList(Canvas canvas, List<Map<String, dynamic>> ops) {
    // Isolate each op list so an unscoped clip/transform cannot leak from the
    // persistent base into an overlay (or out of a nested group).
    canvas.save();
    var depth = 0;
    for (final op in ops) {
      if (op['op'] == 'restore' && depth == 0) continue;
      depth += _paintOp(canvas, op);
    }
    while (depth > 0) {
      canvas.restore();
      depth--;
    }
    canvas.restore();
  }

  /// Returns the net change in save-scope depth (+1 for save, -1 for restore).
  int _paintOp(Canvas canvas, Map<String, dynamic> op) {
    switch (op['op']?.toString()) {
      case 'line':
        canvas.drawLine(
          Offset(_d(op['x1']), _d(op['y1'])),
          Offset(_d(op['x2']), _d(op['y2'])),
          _paint(op['paint']),
        );
      case 'polyline':
        final points = _offsets(op['points']);
        if (points.length >= 2) {
          canvas.drawPoints(
            ui.PointMode.polygon,
            points,
            _paint(op['paint'], defaultStroke: true),
          );
        }
      case 'rect':
        canvas.drawRect(_rect(op), _paint(op['paint']));
      case 'rrect':
        canvas.drawRRect(_rrect(op), _paint(op['paint']));
      case 'circle':
        canvas.drawCircle(
          Offset(_d(op['cx']), _d(op['cy'])),
          _d(op['r']),
          _paint(op['paint']),
        );
      case 'oval':
        canvas.drawOval(_rect(op), _paint(op['paint']));
      case 'arc':
        canvas.drawArc(
          _rect(op),
          _d(op['startAngle']),
          _d(op['sweepAngle']),
          op['useCenter'] == true,
          _paint(op['paint']),
        );
      case 'points':
        final mode = switch (op['mode']?.toString()) {
          'lines' => ui.PointMode.lines,
          'polygon' => ui.PointMode.polygon,
          _ => ui.PointMode.points,
        };
        canvas.drawPoints(
          mode,
          _offsets(op['points']),
          _paint(op['paint'], defaultStroke: true),
        );
      case 'polygon':
        final path = Path()
          ..addPolygon(_offsets(op['points']), op['closed'] != false);
        canvas.drawPath(path, _paint(op['paint']));
      case 'path':
        canvas.drawPath(_path(op), _paint(op['paint']));
      case 'text':
        _drawText(canvas, op);
      case 'image':
        _drawImage(canvas, op);
      case 'clip':
        _clip(canvas, op);
      case 'save':
        canvas.save();
        return 1;
      case 'saveLayer':
        final bounds = op['bounds'];
        final rect = bounds is List && bounds.length == 4
            ? Rect.fromLTWH(
                _d(bounds[0]),
                _d(bounds[1]),
                _d(bounds[2]),
                _d(bounds[3]),
              )
            : null;
        canvas.saveLayer(
          rect,
          Paint()
            ..color = Colors.white.withValues(
              alpha: _d(op['opacity'], 1).clamp(0.0, 1.0),
            ),
        );
        return 1;
      case 'restore':
        canvas.restore();
        return -1;
      case 'group':
        _drawGroup(canvas, op);
      case 'translate':
        canvas.translate(_d(op['dx']), _d(op['dy']));
      case 'scale':
        final sx = _d(op['sx'], 1);
        canvas.scale(sx, op['sy'] is num ? _d(op['sy']) : sx);
      case 'rotate':
        final px = _d(op['px']);
        final py = _d(op['py']);
        if (op['px'] is num || op['py'] is num) {
          canvas.translate(px, py);
          canvas.rotate(_d(op['radians']));
          canvas.translate(-px, -py);
        } else {
          canvas.rotate(_d(op['radians']));
        }
      case 'matrix':
        final matrix = _matrix(op);
        if (matrix != null) canvas.transform(matrix.storage);
    }
    return 0;
  }

  void _drawGroup(Canvas canvas, Map<String, dynamic> op) {
    canvas.saveLayer(
      null,
      Paint()
        ..color = Colors.white.withValues(
          alpha: _d(op['opacity'], 1).clamp(0.0, 1.0),
        ),
    );
    final transform = op['transform'];
    if (transform is List && transform.length == 6) {
      final matrix = _matrix({'affine': transform});
      if (matrix != null) canvas.transform(matrix.storage);
    }
    final clip = op['clip'];
    if (clip is Map) {
      _clip(canvas, clip.map((k, v) => MapEntry(k.toString(), v)));
    }
    final inner = op['ops'];
    if (inner is List) {
      _paintList(canvas, [
        for (final e in inner)
          if (e is Map) e.map((k, v) => MapEntry(k.toString(), v)),
      ]);
    }
    canvas.restore();
  }

  void _clip(Canvas canvas, Map<String, dynamic> op) {
    final antiAlias = op['antiAlias'] != false;
    switch (op['shape']?.toString()) {
      case 'rect':
        canvas.clipRect(_rect(op), doAntiAlias: antiAlias);
      case 'rrect':
        canvas.clipRRect(_rrect(op), doAntiAlias: antiAlias);
      case 'path':
        canvas.clipPath(_path(op), doAntiAlias: antiAlias);
    }
  }

  void _drawText(Canvas canvas, Map<String, dynamic> op) {
    final painter = PluginCanvasState._buildTextPainter(op, scheme);
    final maxWidth = op['maxWidth'] is num
        ? _d(op['maxWidth'])
        : double.infinity;
    painter.layout(maxWidth: maxWidth);
    painter.paint(canvas, Offset(_d(op['x']), _d(op['y'])));
    painter.dispose();
  }

  void _drawImage(Canvas canvas, Map<String, dynamic> op) {
    final image = images[op['src']?.toString()];
    if (image == null) return; // Unresolved / not yet decoded: skip.
    final srcW = op['srcW'] is num ? _d(op['srcW']) : image.width.toDouble();
    final srcH = op['srcH'] is num ? _d(op['srcH']) : image.height.toDouble();
    final src = Rect.fromLTWH(_d(op['srcX']), _d(op['srcY']), srcW, srcH);
    final dstW = op['width'] is num ? _d(op['width']) : srcW;
    final dstH = op['height'] is num ? _d(op['height']) : srcH;
    final dst = Rect.fromLTWH(_d(op['x']), _d(op['y']), dstW, dstH);
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..color = Colors.white.withValues(alpha: _d(op['opacity'], 1)),
    );
  }

  // -- Geometry helpers ------------------------------------------------------

  Rect _rect(Map<String, dynamic> op) =>
      Rect.fromLTWH(_d(op['x']), _d(op['y']), _d(op['w']), _d(op['h']));

  RRect _rrect(Map<String, dynamic> op) {
    final rect = _rect(op);
    if (op['radius'] is num) {
      return RRect.fromRectAndRadius(rect, Radius.circular(_d(op['radius'])));
    }
    return RRect.fromRectAndCorners(
      rect,
      topLeft: Radius.elliptical(_d(op['rx']), _d(op['ry'])),
      topRight: Radius.elliptical(_d(op['rx']), _d(op['ry'])),
      bottomLeft: Radius.elliptical(_d(op['rx']), _d(op['ry'])),
      bottomRight: Radius.elliptical(_d(op['rx']), _d(op['ry'])),
    );
  }

  List<Offset> _offsets(Object? raw) {
    if (raw is! List) return const [];
    final points = <Offset>[];
    for (var i = 0; i + 1 < raw.length; i += 2) {
      points.add(Offset(_d(raw[i]), _d(raw[i + 1])));
    }
    return points;
  }

  Path _path(Map<String, dynamic> op) {
    final path = Path();
    if (op['fillRule'] == 'evenodd') path.fillType = PathFillType.evenOdd;
    final commands = op['commands'];
    if (commands is! List) return path;
    for (final command in commands) {
      if (command is! Map) continue;
      final c = command.map((k, v) => MapEntry(k.toString(), v));
      switch (c['c']?.toString()) {
        case 'moveTo':
          path.moveTo(_d(c['x']), _d(c['y']));
        case 'lineTo':
          path.lineTo(_d(c['x']), _d(c['y']));
        case 'quadTo':
          path.quadraticBezierTo(
            _d(c['x1']),
            _d(c['y1']),
            _d(c['x']),
            _d(c['y']),
          );
        case 'cubicTo':
          path.cubicTo(
            _d(c['x1']),
            _d(c['y1']),
            _d(c['x2']),
            _d(c['y2']),
            _d(c['x']),
            _d(c['y']),
          );
        case 'close':
          path.close();
      }
    }
    return path;
  }

  Matrix4? _matrix(Map<String, dynamic> op) {
    final affine = op['affine'];
    if (affine is List && affine.length == 6) {
      return Matrix4.identity()..setValues(
        _d(affine[0]),
        _d(affine[1]),
        0,
        0,
        _d(affine[2]),
        _d(affine[3]),
        0,
        0,
        0,
        0,
        1,
        0,
        _d(affine[4]),
        _d(affine[5]),
        0,
        1,
      );
    }
    final m4 = op['m4'];
    if (m4 is List && m4.length == 16) {
      return Matrix4.fromList([for (final v in m4) _d(v)]);
    }
    return null;
  }

  // -- Paint / color / gradient ----------------------------------------------

  Paint _paint(Object? raw, {bool defaultStroke = false}) {
    final paint = Paint()..isAntiAlias = true;
    if (raw is! Map) {
      paint
        ..color = scheme.onSurface
        ..style = defaultStroke ? PaintingStyle.stroke : PaintingStyle.fill;
      return paint;
    }
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    paint.style = switch (map['style']?.toString()) {
      'stroke' => PaintingStyle.stroke,
      'fill' => PaintingStyle.fill,
      _ => defaultStroke ? PaintingStyle.stroke : PaintingStyle.fill,
    };
    paint.strokeWidth = _d(map['strokeWidth'], 1);
    paint.strokeCap = switch (map['strokeCap']?.toString()) {
      'round' => StrokeCap.round,
      'square' => StrokeCap.square,
      _ => StrokeCap.butt,
    };
    paint.strokeJoin = switch (map['strokeJoin']?.toString()) {
      'round' => StrokeJoin.round,
      'bevel' => StrokeJoin.bevel,
      _ => StrokeJoin.miter,
    };
    if (map['antiAlias'] == false) paint.isAntiAlias = false;
    paint.blendMode = _blendMode(map['blendMode']?.toString());

    final opacity = _d(map['opacity'], 1).clamp(0.0, 1.0);
    final shader = _shader(map['shader']);
    if (shader != null) {
      paint.shader = shader;
      if (opacity < 1) paint.color = Colors.white.withValues(alpha: opacity);
    } else {
      final color =
          parseColor(map['color']?.toString(), scheme) ?? scheme.onSurface;
      paint.color = opacity < 1 ? color.withValues(alpha: opacity) : color;
    }
    return paint;
  }

  ui.Shader? _shader(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    final colors = <Color>[
      for (final token
          in (map['colors'] is List ? map['colors'] as List : const []))
        parseColor(token?.toString(), scheme) ?? scheme.onSurface,
    ];
    if (colors.length < 2) return null;
    final stops =
        map['stops'] is List && (map['stops'] as List).length == colors.length
        ? [for (final s in map['stops'] as List) _d(s)]
        : null;
    final tileMode = switch (map['tileMode']?.toString()) {
      'repeated' => TileMode.repeated,
      'mirror' => TileMode.mirror,
      'decal' => TileMode.decal,
      _ => TileMode.clamp,
    };
    switch (map['type']?.toString()) {
      case 'linear':
        final from = _offsets(map['from'] is List ? map['from'] : null);
        final to = _offsets(map['to'] is List ? map['to'] : null);
        if (from.isEmpty || to.isEmpty) return null;
        return ui.Gradient.linear(
          from.first,
          to.first,
          colors,
          stops,
          tileMode,
        );
      case 'radial':
        final center = _offsets(map['center'] is List ? map['center'] : null);
        if (center.isEmpty) return null;
        final focal = _offsets(map['focal'] is List ? map['focal'] : null);
        return ui.Gradient.radial(
          center.first,
          _d(map['radius']),
          colors,
          stops,
          tileMode,
          null,
          focal.isEmpty ? null : focal.first,
        );
    }
    return null;
  }

  BlendMode _blendMode(String? token) => switch (token) {
    'clear' => BlendMode.clear,
    'src' => BlendMode.src,
    'dst' => BlendMode.dst,
    'srcOver' => BlendMode.srcOver,
    'dstOver' => BlendMode.dstOver,
    'srcIn' => BlendMode.srcIn,
    'dstIn' => BlendMode.dstIn,
    'srcOut' => BlendMode.srcOut,
    'dstOut' => BlendMode.dstOut,
    'srcATop' => BlendMode.srcATop,
    'dstATop' => BlendMode.dstATop,
    'xor' => BlendMode.xor,
    'plus' => BlendMode.plus,
    'modulate' => BlendMode.modulate,
    'screen' => BlendMode.screen,
    'overlay' => BlendMode.overlay,
    'darken' => BlendMode.darken,
    'lighten' => BlendMode.lighten,
    'multiply' => BlendMode.multiply,
    _ => BlendMode.srcOver,
  };

  /// Parses a `#RRGGBB`/`#AARRGGBB` hex or `theme:<role>` token; returns null on
  /// an unparseable value so the caller falls back to `theme:onSurface`.
  static Color? parseColor(String? token, ColorScheme scheme) {
    if (token == null || token.isEmpty) return null;
    if (token.startsWith('#')) {
      final hex = token.substring(1);
      final value = int.tryParse(hex, radix: 16);
      if (value == null) return null;
      if (hex.length == 6) return Color(0xFF000000 | value);
      if (hex.length == 8) return Color(value);
      return null;
    }
    if (token.startsWith('theme:')) {
      return switch (token.substring(6)) {
        'primary' => scheme.primary,
        'onPrimary' => scheme.onPrimary,
        'secondary' => scheme.secondary,
        'onSecondary' => scheme.onSecondary,
        'surface' => scheme.surface,
        'onSurface' => scheme.onSurface,
        'onSurfaceVariant' => scheme.onSurfaceVariant,
        'surfaceContainerHighest' => scheme.surfaceContainerHighest,
        'outline' => scheme.outline,
        'error' => scheme.error,
        'onError' => scheme.onError,
        _ => scheme.onSurface,
      };
    }
    return null;
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
      old.revision != revision ||
      old.scale != scale ||
      old.offset != offset ||
      old.scheme != scheme ||
      !identical(old.base, base) ||
      !identical(old.overlay, overlay) ||
      old.hoverRect != hoverRect ||
      old.rubberBand != rubberBand;
}
