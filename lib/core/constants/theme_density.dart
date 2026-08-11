import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/services/app.dart';

/// Desktop-oriented density tokens for each [ThemeStyle] tier.
///
/// Style tiers form a gradient:
/// [ThemeStyle.compact] is the tightest, [ThemeStyle.standard] is moderately
/// tightened, and [ThemeStyle.comfortable] keeps the spacious Material layout.
class ThemeDensityTokens {
  const ThemeDensityTokens({
    required this.visualDensity,
    required this.materialTapTargetSize,
    required this.fontSizeDelta,
    required this.toolbarHeight,
    required this.buttonMinimumSize,
    required this.iconButtonTheme,
    required this.navIconSize,
    required this.statusBarHeight,
    required this.navRailWidth,
    required this.drawerTileHeight,
  });

  /// Density of Material widgets.
  final VisualDensity visualDensity;

  /// Touch target size. Compact tiers use [MaterialTapTargetSize.shrinkWrap]
  /// so buttons and icon taps do not reserve 48px of space.
  final MaterialTapTargetSize materialTapTargetSize;

  /// Number of logical pixels subtracted from every [TextTheme] font size.
  final double fontSizeDelta;

  /// Height of [AppBar]s used for editor/tool chrome.
  final double toolbarHeight;

  /// Minimum size applied to filled/outlined/text buttons.
  final Size buttonMinimumSize;

  /// Theme data for icon buttons (smaller icons and tighter padding).
  final IconButtonThemeData iconButtonTheme;

  /// Size of navigation rail / drawer icons.
  final double navIconSize;

  /// Height of the bottom status bar chrome.
  final double statusBarHeight;

  /// Width of the navigation rail (compact shrinks it).
  final double navRailWidth;

  /// Height of each navigation drawer destination row.
  final double drawerTileHeight;

  /// Size of header/toolbar icons, resolved from [iconButtonTheme] so it
  /// follows the selected tier (18 / 20 / 24 for the built-in styles).
  double get headerIconSize {
    final iconSize = iconButtonTheme.style?.iconSize;
    if (iconSize is WidgetStatePropertyAll<double>) return iconSize.value;
    return 18;
  }

  /// Returns the tokens for the given [style] tier.
  static ThemeDensityTokens forStyle(ThemeStyle style) {
    return switch (style) {
      ThemeStyle.compact => const ThemeDensityTokens(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        fontSizeDelta: 1,
        toolbarHeight: 38,
        buttonMinimumSize: Size(60, 40),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            iconSize: WidgetStatePropertyAll(18),
            minimumSize: WidgetStatePropertyAll(Size(32, 32)),
            padding: WidgetStatePropertyAll(EdgeInsets.symmetric(
              horizontal: 6,
            )),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        navIconSize: 20,
        statusBarHeight: 32,
        navRailWidth: 56,
        drawerTileHeight: 40,
      ),
      ThemeStyle.standard => const ThemeDensityTokens(
        visualDensity: VisualDensity.standard,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        fontSizeDelta: 0.5,
        toolbarHeight: 44,
        buttonMinimumSize: Size(64, 42),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            iconSize: WidgetStatePropertyAll(20),
            minimumSize: WidgetStatePropertyAll(Size(36, 36)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        navIconSize: 22,
        statusBarHeight: 38,
        navRailWidth: 64,
        drawerTileHeight: 48,
      ),
      ThemeStyle.comfortable => const ThemeDensityTokens(
        visualDensity: VisualDensity.comfortable,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        fontSizeDelta: 0,
        toolbarHeight: 56,
        buttonMinimumSize: Size(68, 44),
        iconButtonTheme: IconButtonThemeData(),
        navIconSize: 24,
        statusBarHeight: 44,
        navRailWidth: 72,
        drawerTileHeight: 56,
      ),
    };
  }
}

/// Returns a copy of [theme] with every font size reduced by [delta].
TextTheme scaleTextTheme(TextTheme theme, double delta) {
  if (delta == 0) return theme;
  TextStyle? shrink(TextStyle? style) {
    if (style == null || style.fontSize == null) return style;
    return style.copyWith(fontSize: style.fontSize! - delta);
  }

  return theme.copyWith(
    displayLarge: shrink(theme.displayLarge),
    displayMedium: shrink(theme.displayMedium),
    displaySmall: shrink(theme.displaySmall),
    headlineLarge: shrink(theme.headlineLarge),
    headlineMedium: shrink(theme.headlineMedium),
    headlineSmall: shrink(theme.headlineSmall),
    titleLarge: shrink(theme.titleLarge),
    titleMedium: shrink(theme.titleMedium),
    titleSmall: shrink(theme.titleSmall),
    bodyLarge: shrink(theme.bodyLarge),
    bodyMedium: shrink(theme.bodyMedium),
    bodySmall: shrink(theme.bodySmall),
    labelLarge: shrink(theme.labelLarge),
    labelMedium: shrink(theme.labelMedium),
    labelSmall: shrink(theme.labelSmall),
  );
}