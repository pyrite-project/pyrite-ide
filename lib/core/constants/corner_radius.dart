import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/services/app.dart';

/// Single source of truth for every corner radius in the app.
///
/// The app has one **outer** radius ([outer]) and one nesting distance ([gap])
/// per density tier. A rounded surface nested inside another rounded surface
/// uses [inner], which is defined as `outer - gap`. That keeps the two arcs
/// concentric, so nested content looks intentional, and it guarantees every
/// top-level surface within a tier shares the same corner radius.
///
/// Usage:
/// ```dart
/// // Standalone surface: panel, card, dialog, menu, popup, chip.
/// decoration: BoxDecoration(borderRadius: context.outerCorners);
///
/// // Surface nested tightly inside another rounded surface.
/// decoration: BoxDecoration(borderRadius: context.innerCorners);
/// ```
@immutable
class AppCornerRadii extends ThemeExtension<AppCornerRadii> {
  const AppCornerRadii({required this.outer, required this.gap});

  /// The default scale: a comfortably rounded 12 pixel corner with a 6 pixel
  /// nesting gap. Used by [ThemeStyle.standard] and [ThemeStyle.comfortable].
  ///
  /// Corner radius is part of the design language, not part of density, so a
  /// tier trims spacing, padding and typography rather than squaring off the
  /// corners.
  static const AppCornerRadii comfortable = AppCornerRadii(outer: 12, gap: 6);

  /// The `compact` tier trims the corner a little tighter than the other
  /// two: a dense layout reads as cramped when its surfaces are as round as a
  /// comfortable one, so the outer radius drops to 10. The nesting [gap]
  /// shrinks with it (6 -> 5) so `outer == gap + inner` still holds and the
  /// arcs stay concentric.
  ///
  /// All three tiers still share one shape language, and the tier still owns
  /// only spacing, padding and typography. The difference is deliberately
  /// small (2 pixels) so switching tiers never reads as a different app.
  static const AppCornerRadii compact = AppCornerRadii(outer: 10, gap: 5);

  /// Alias kept for call sites that read better as "the default".
  static const AppCornerRadii standard = comfortable;

  /// Fallback scale used when no [ThemeData] is available, so widgets built
  /// outside a themed subtree still resolve to a sane radius.
  static const AppCornerRadii fallback = comfortable;

  /// Corner radius of a top-level surface.
  final double outer;

  /// Distance between a nested rounded surface and the surface holding it.
  ///
  /// This is the padding that must separate the two layers for their corner
  /// arcs to line up, i.e. `outer == gap + inner`.
  final double gap;

  /// Corner radius of a surface nested inside another rounded surface.
  double get inner => math.max(0, outer - gap);

  /// [BorderRadius] for a top-level surface.
  BorderRadius get outerRadius => BorderRadius.circular(outer);

  /// [BorderRadius] for a nested surface.
  BorderRadius get innerRadius => BorderRadius.circular(inner);

  /// [BorderRadius] for a surface nested at exactly [gap] from its parent.
  ///
  /// Use this when the real inset is known at the call site, so the nested arc
  /// lines up with the parent arc: `outer == gap + inner`.
  BorderRadius nestedRadius(double gap) =>
      BorderRadius.circular(math.max(0, outer - gap));

  /// Returns the scale for the given [ThemeStyle] tier.
  ///
  /// [ThemeStyle.comfortable] and [ThemeStyle.standard] share [comfortable];
  /// [ThemeStyle.compact] uses [compact], which is one notch tighter because a
  /// dense layout looks crowded with the same generous corners.
  ///
  /// Either way the tier still controls only spacing, padding and typography,
  /// and the `outer == gap + inner` rule holds for every tier, so nested
  /// corners never drift from the surfaces that hold them.
  ///
  /// The [style] argument is accepted so call sites stay explicit about the
  /// tier they are rendering for.
  static AppCornerRadii forStyle(ThemeStyle style) =>
      style == ThemeStyle.compact ? compact : comfortable;

  @override
  AppCornerRadii copyWith({double? outer, double? gap}) {
    return AppCornerRadii(outer: outer ?? this.outer, gap: gap ?? this.gap);
  }

  @override
  AppCornerRadii lerp(covariant AppCornerRadii? other, double t) {
    if (other == null) return this;
    return AppCornerRadii(
      outer: lerpDouble(outer, other.outer, t)!,
      gap: lerpDouble(gap, other.gap, t)!,
    );
  }
}

/// Convenience accessors for the unified corner scale.
extension AppCornerRadiiX on BuildContext {
  /// The scale installed on the current [ThemeData].
  AppCornerRadii get corners =>
      Theme.of(this).extension<AppCornerRadii>() ?? AppCornerRadii.fallback;

  /// Radius for a top-level surface. All top-level surfaces share this value.
  BorderRadius get outerCorners => corners.outerRadius;

  /// Radius for a surface nested inside another rounded surface.
  BorderRadius get innerCorners => corners.innerRadius;

  /// Radius for a surface nested at exactly [gap] from its parent.
  BorderRadius nestedCorners(double gap) => corners.nestedRadius(gap);
}
