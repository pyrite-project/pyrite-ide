import 'dart:math' as math;
import 'dart:ui';

/// The desktop window's last known geometry.
///
/// [bounds] are logical pixels in the same coordinate space the window manager
/// reports, and [maximized] records whether the window was maximized so the
/// next session can restore both the window and its restore-down size.
class WindowPlacement {
  const WindowPlacement({required this.bounds, this.maximized = false});

  /// Smallest window accepted by [clampToVisibleAreas]. Anything smaller is
  /// grown before being fitted to a display.
  static const Size defaultMinimumSize = Size(900, 600);

  /// Smallest window that is considered restorable when reading persisted
  /// geometry; smaller entries are treated as corrupt and dropped.
  static const double minimumWidth = 400;
  static const double minimumHeight = 300;

  final Rect bounds;
  final bool maximized;

  Map<String, dynamic> toJson() => {
    'x': bounds.left,
    'y': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
    'maximized': maximized,
  };

  /// Reads a persisted placement, or null when the entry is absent or invalid.
  ///
  /// Coordinates may arrive as any [num] because JSON has a single number type.
  /// Non-finite values and implausibly small sizes are rejected instead of
  /// producing a window the user could never see or resize.
  static WindowPlacement? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final x = _finiteDouble(json['x']);
    final y = _finiteDouble(json['y']);
    final width = _finiteDouble(json['width']);
    final height = _finiteDouble(json['height']);
    if (x == null || y == null || width == null || height == null) return null;
    if (width < minimumWidth || height < minimumHeight) return null;

    final maximized = json['maximized'];
    return WindowPlacement(
      bounds: Rect.fromLTWH(x, y, width, height),
      maximized: maximized is bool ? maximized : false,
    );
  }

  /// Fits this placement onto one of [workAreas].
  ///
  /// A display is represented by its work area (screen minus taskbars), in
  /// logical pixels. The window keeps its current position when it is
  /// sufficiently visible on a display and is centered on the primary (first)
  /// work area when it is not. With no displays to fit into the placement is
  /// returned unchanged.
  WindowPlacement clampToVisibleAreas(
    List<Rect> workAreas, {
    Size minimumSize = defaultMinimumSize,
  }) {
    final areas = [
      for (final area in workAreas)
        if (area.left.isFinite &&
            area.top.isFinite &&
            area.right.isFinite &&
            area.bottom.isFinite &&
            area.width > 0 &&
            area.height > 0)
          area,
    ];
    if (areas.isEmpty) return this;

    final width = math.max(bounds.width, minimumSize.width);
    final height = math.max(bounds.height, minimumSize.height);
    final sized = Rect.fromLTWH(bounds.left, bounds.top, width, height);

    Rect? bestArea;
    var bestIntersectionArea = 0.0;
    for (final area in areas) {
      final intersection = area.intersect(sized);
      final intersectionArea = intersection.width > 0 && intersection.height > 0
          ? intersection.width * intersection.height
          : 0.0;
      if (intersectionArea > bestIntersectionArea) {
        bestIntersectionArea = intersectionArea;
        bestArea = area;
      }
    }

    // Enough of the window is on a display to keep its position; only pull it
    // fully inside when its grab area is below a quarter of its surface.
    final windowArea = sized.width * sized.height;
    if (bestArea == null || bestIntersectionArea < windowArea * 0.25) {
      final primary = areas.first;
      final centered = Rect.fromCenter(
        center: primary.center,
        width: width,
        height: height,
      );
      return WindowPlacement(
        bounds: _clampInside(centered, primary),
        maximized: maximized,
      );
    }

    return WindowPlacement(
      bounds: _clampInside(sized, bestArea),
      maximized: maximized,
    );
  }

  static Rect _clampInside(Rect rect, Rect area) {
    final maxLeft = math.max(area.left, area.right - rect.width);
    final maxTop = math.max(area.top, area.bottom - rect.height);
    final left = rect.left.clamp(area.left, maxLeft).toDouble();
    final top = rect.top.clamp(area.top, maxTop).toDouble();
    return Rect.fromLTWH(left, top, rect.width, rect.height);
  }

  static double? _finiteDouble(Object? value) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }

  @override
  bool operator ==(Object other) =>
      other is WindowPlacement &&
      other.bounds == bounds &&
      other.maximized == maximized;

  @override
  int get hashCode => Object.hash(bounds, maximized);

  @override
  String toString() =>
      'WindowPlacement(bounds: $bounds, maximized: $maximized)';
}
