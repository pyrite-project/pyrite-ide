import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

class PluginThemeData {
  final String id;
  final String name;
  final String pluginId;
  final String? mode; // "dark" | "light" | null

  // Colors (light)
  final Color? colorPrimary;
  final Color? colorOnPrimary;
  final Color? colorPrimaryContainer;
  final Color? colorOnPrimaryContainer;
  final Color? colorSecondary;
  final Color? colorOnSecondary;
  final Color? colorSecondaryContainer;
  final Color? colorOnSecondaryContainer;
  final Color? colorTertiary;
  final Color? colorOnTertiary;
  final Color? colorTertiaryContainer;
  final Color? colorOnTertiaryContainer;
  final Color? colorError;
  final Color? colorOnError;
  final Color? colorErrorContainer;
  final Color? colorOnErrorContainer;
  final Color? colorSurface;
  final Color? colorOnSurface;
  final Color? colorSurfaceDim;
  final Color? colorSurfaceBright;
  final Color? colorSurfaceContainerLowest;
  final Color? colorSurfaceContainerLow;
  final Color? colorSurfaceContainer;
  final Color? colorSurfaceContainerHigh;
  final Color? colorSurfaceContainerHighest;
  final Color? colorOnSurfaceVariant;
  final Color? colorOutline;
  final Color? colorOutlineVariant;
  final Color? colorInverseSurface;
  final Color? colorOnInverseSurface;
  final Color? colorInversePrimary;
  final Color? colorScrim;
  final Color? colorShadow;

  // Colors (dark override)
  final Color? darkColorPrimary;
  final Color? darkColorOnPrimary;
  final Color? darkColorPrimaryContainer;
  final Color? darkColorOnPrimaryContainer;
  final Color? darkColorSecondary;
  final Color? darkColorOnSecondary;
  final Color? darkColorSecondaryContainer;
  final Color? darkColorOnSecondaryContainer;
  final Color? darkColorTertiary;
  final Color? darkColorOnTertiary;
  final Color? darkColorTertiaryContainer;
  final Color? darkColorOnTertiaryContainer;
  final Color? darkColorError;
  final Color? darkColorOnError;
  final Color? darkColorErrorContainer;
  final Color? darkColorOnErrorContainer;
  final Color? darkColorSurface;
  final Color? darkColorOnSurface;
  final Color? darkColorSurfaceDim;
  final Color? darkColorSurfaceBright;
  final Color? darkColorSurfaceContainerLowest;
  final Color? darkColorSurfaceContainerLow;
  final Color? darkColorSurfaceContainer;
  final Color? darkColorSurfaceContainerHigh;
  final Color? darkColorSurfaceContainerHighest;
  final Color? darkColorOnSurfaceVariant;
  final Color? darkColorOutline;
  final Color? darkColorOutlineVariant;
  final Color? darkColorInverseSurface;
  final Color? darkColorOnInverseSurface;
  final Color? darkColorInversePrimary;

  // Global
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final String? density;
  final bool? useMaterial3;

  // Sub-themes (FlexSubThemesData)
  final double? defaultRadius;
  final double? inputDecoratorRadius;
  final double? cardRadius;
  final double? chipRadius;
  final double? textButtonRadius;
  final double? elevatedButtonRadius;
  final double? outlinedButtonRadius;
  final double? filledButtonRadius;
  final double? segmentedButtonRadius;
  final double? toggleButtonsRadius;
  final double? popupMenuRadius;
  final double? menuRadius;
  final double? menuBarRadius;
  final double? searchBarRadius;
  final double? searchViewRadius;
  final double? fabRadius;
  final double? tooltipRadius;
  final double? bottomSheetRadius;
  final String? inputDecoratorBorderType;
  final bool? useM2StyleDividerInM3;
  final int? blendOnLevel;
  final bool? blendOnColors;
  final double? cardBorderWidth;
  final double? cardElevation;

  // AppBar
  final Color? appBarBackgroundColor;
  final Color? appBarForegroundColor;
  final Color? appBarSurfaceTintColor;
  final double? appBarElevation;
  final double? appBarScrolledUnderElevation;
  final bool? appBarCenterTitle;

  // NavigationRail
  final Color? navRailBackgroundColor;
  final Color? navRailIndicatorColor;
  final Color? navRailSelectedIconColor;
  final Color? navRailUnselectedIconColor;
  final Color? navRailSelectedLabelColor;
  final Color? navRailUnselectedLabelColor;

  // NavigationBar
  final Color? navBarBackgroundColor;
  final Color? navBarIndicatorColor;

  // Card
  final Color? cardColor;

  // Dialog
  final Color? dialogBackgroundColor;

  // Divider
  final Color? dividerColor;
  final double? dividerThickness;

  // ListTile
  final Color? listTileIconColor;
  final Color? listTileTextColor;
  final Color? listTileTileColor;
  final Color? listTileSelectedTileColor;
  final bool? listTileDense;

  // Scrollbar
  final Color? scrollbarThumbColor;
  final Color? scrollbarTrackColor;
  final double? scrollbarThickness;

  // Chip
  final Color? chipBackgroundColor;

  // BottomSheet
  final Color? bottomSheetBackgroundColor;

  // PopupMenu
  final Color? popupMenuBackgroundColor;

  PluginThemeData({
    required this.id,
    required this.name,
    required this.pluginId,
    this.mode,
    this.colorPrimary,
    this.colorOnPrimary,
    this.colorPrimaryContainer,
    this.colorOnPrimaryContainer,
    this.colorSecondary,
    this.colorOnSecondary,
    this.colorSecondaryContainer,
    this.colorOnSecondaryContainer,
    this.colorTertiary,
    this.colorOnTertiary,
    this.colorTertiaryContainer,
    this.colorOnTertiaryContainer,
    this.colorError,
    this.colorOnError,
    this.colorErrorContainer,
    this.colorOnErrorContainer,
    this.colorSurface,
    this.colorOnSurface,
    this.colorSurfaceDim,
    this.colorSurfaceBright,
    this.colorSurfaceContainerLowest,
    this.colorSurfaceContainerLow,
    this.colorSurfaceContainer,
    this.colorSurfaceContainerHigh,
    this.colorSurfaceContainerHighest,
    this.colorOnSurfaceVariant,
    this.colorOutline,
    this.colorOutlineVariant,
    this.colorInverseSurface,
    this.colorOnInverseSurface,
    this.colorInversePrimary,
    this.colorScrim,
    this.colorShadow,
    this.darkColorPrimary,
    this.darkColorOnPrimary,
    this.darkColorPrimaryContainer,
    this.darkColorOnPrimaryContainer,
    this.darkColorSecondary,
    this.darkColorOnSecondary,
    this.darkColorSecondaryContainer,
    this.darkColorOnSecondaryContainer,
    this.darkColorTertiary,
    this.darkColorOnTertiary,
    this.darkColorTertiaryContainer,
    this.darkColorOnTertiaryContainer,
    this.darkColorError,
    this.darkColorOnError,
    this.darkColorErrorContainer,
    this.darkColorOnErrorContainer,
    this.darkColorSurface,
    this.darkColorOnSurface,
    this.darkColorSurfaceDim,
    this.darkColorSurfaceBright,
    this.darkColorSurfaceContainerLowest,
    this.darkColorSurfaceContainerLow,
    this.darkColorSurfaceContainer,
    this.darkColorSurfaceContainerHigh,
    this.darkColorSurfaceContainerHighest,
    this.darkColorOnSurfaceVariant,
    this.darkColorOutline,
    this.darkColorOutlineVariant,
    this.darkColorInverseSurface,
    this.darkColorOnInverseSurface,
    this.darkColorInversePrimary,
    this.fontFamily,
    this.fontFamilyFallback,
    this.density,
    this.useMaterial3,
    this.defaultRadius,
    this.inputDecoratorRadius,
    this.cardRadius,
    this.chipRadius,
    this.textButtonRadius,
    this.elevatedButtonRadius,
    this.outlinedButtonRadius,
    this.filledButtonRadius,
    this.segmentedButtonRadius,
    this.toggleButtonsRadius,
    this.popupMenuRadius,
    this.menuRadius,
    this.menuBarRadius,
    this.searchBarRadius,
    this.searchViewRadius,
    this.fabRadius,
    this.tooltipRadius,
    this.bottomSheetRadius,
    this.inputDecoratorBorderType,
    this.useM2StyleDividerInM3,
    this.blendOnLevel,
    this.blendOnColors,
    this.cardBorderWidth,
    this.cardElevation,
    this.appBarBackgroundColor,
    this.appBarForegroundColor,
    this.appBarSurfaceTintColor,
    this.appBarElevation,
    this.appBarScrolledUnderElevation,
    this.appBarCenterTitle,
    this.navRailBackgroundColor,
    this.navRailIndicatorColor,
    this.navRailSelectedIconColor,
    this.navRailUnselectedIconColor,
    this.navRailSelectedLabelColor,
    this.navRailUnselectedLabelColor,
    this.navBarBackgroundColor,
    this.navBarIndicatorColor,
    this.cardColor,
    this.dialogBackgroundColor,
    this.dividerColor,
    this.dividerThickness,
    this.listTileIconColor,
    this.listTileTextColor,
    this.listTileTileColor,
    this.listTileSelectedTileColor,
    this.listTileDense,
    this.scrollbarThumbColor,
    this.scrollbarTrackColor,
    this.scrollbarThickness,
    this.chipBackgroundColor,
    this.bottomSheetBackgroundColor,
    this.popupMenuBackgroundColor,
  });

  // ── Parsing ──

  static Color? _parseColor(dynamic value) {
    if (value == null) return null;
    final s = value.toString().replaceFirst('#', '');
    if (s.length == 6) {
      return Color(int.parse('FF$s', radix: 16));
    } else if (s.length == 8) {
      return Color(int.parse(s, radix: 16));
    }
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is String) {
      if (value.toLowerCase() == 'true') return true;
      if (value.toLowerCase() == 'false') return false;
    }
    return null;
  }

  static List<String>? _parseStringList(dynamic value) {
    if (value == null) return null;
    if (value is List) return value.map((e) => e.toString()).toList();
    return null;
  }

  factory PluginThemeData.fromMap(
    String id,
    String name,
    String pluginId,
    Map<String, dynamic> data,
  ) {
    return PluginThemeData(
      id: id,
      name: name,
      pluginId: pluginId,
      mode: data['mode']?.toString(),
      // Light colors
      colorPrimary: _parseColor(data['color.primary']),
      colorOnPrimary: _parseColor(data['color.onPrimary']),
      colorPrimaryContainer: _parseColor(data['color.primaryContainer']),
      colorOnPrimaryContainer: _parseColor(data['color.onPrimaryContainer']),
      colorSecondary: _parseColor(data['color.secondary']),
      colorOnSecondary: _parseColor(data['color.onSecondary']),
      colorSecondaryContainer: _parseColor(data['color.secondaryContainer']),
      colorOnSecondaryContainer:
          _parseColor(data['color.onSecondaryContainer']),
      colorTertiary: _parseColor(data['color.tertiary']),
      colorOnTertiary: _parseColor(data['color.onTertiary']),
      colorTertiaryContainer: _parseColor(data['color.tertiaryContainer']),
      colorOnTertiaryContainer: _parseColor(data['color.onTertiaryContainer']),
      colorError: _parseColor(data['color.error']),
      colorOnError: _parseColor(data['color.onError']),
      colorErrorContainer: _parseColor(data['color.errorContainer']),
      colorOnErrorContainer: _parseColor(data['color.onErrorContainer']),
      colorSurface: _parseColor(data['color.surface']),
      colorOnSurface: _parseColor(data['color.onSurface']),
      colorSurfaceDim: _parseColor(data['color.surfaceDim']),
      colorSurfaceBright: _parseColor(data['color.surfaceBright']),
      colorSurfaceContainerLowest:
          _parseColor(data['color.surfaceContainerLowest']),
      colorSurfaceContainerLow:
          _parseColor(data['color.surfaceContainerLow']),
      colorSurfaceContainer: _parseColor(data['color.surfaceContainer']),
      colorSurfaceContainerHigh:
          _parseColor(data['color.surfaceContainerHigh']),
      colorSurfaceContainerHighest:
          _parseColor(data['color.surfaceContainerHighest']),
      colorOnSurfaceVariant: _parseColor(data['color.onSurfaceVariant']),
      colorOutline: _parseColor(data['color.outline']),
      colorOutlineVariant: _parseColor(data['color.outlineVariant']),
      colorInverseSurface: _parseColor(data['color.inverseSurface']),
      colorOnInverseSurface: _parseColor(data['color.onInverseSurface']),
      colorInversePrimary: _parseColor(data['color.inversePrimary']),
      colorScrim: _parseColor(data['color.scrim']),
      colorShadow: _parseColor(data['color.shadow']),
      // Dark colors
      darkColorPrimary: _parseColor(data['dark.color.primary']),
      darkColorOnPrimary: _parseColor(data['dark.color.onPrimary']),
      darkColorPrimaryContainer:
          _parseColor(data['dark.color.primaryContainer']),
      darkColorOnPrimaryContainer:
          _parseColor(data['dark.color.onPrimaryContainer']),
      darkColorSecondary: _parseColor(data['dark.color.secondary']),
      darkColorOnSecondary: _parseColor(data['dark.color.onSecondary']),
      darkColorSecondaryContainer:
          _parseColor(data['dark.color.secondaryContainer']),
      darkColorOnSecondaryContainer:
          _parseColor(data['dark.color.onSecondaryContainer']),
      darkColorTertiary: _parseColor(data['dark.color.tertiary']),
      darkColorOnTertiary: _parseColor(data['dark.color.onTertiary']),
      darkColorTertiaryContainer:
          _parseColor(data['dark.color.tertiaryContainer']),
      darkColorOnTertiaryContainer:
          _parseColor(data['dark.color.onTertiaryContainer']),
      darkColorError: _parseColor(data['dark.color.error']),
      darkColorOnError: _parseColor(data['dark.color.onError']),
      darkColorErrorContainer:
          _parseColor(data['dark.color.errorContainer']),
      darkColorOnErrorContainer:
          _parseColor(data['dark.color.onErrorContainer']),
      darkColorSurface: _parseColor(data['dark.color.surface']),
      darkColorOnSurface: _parseColor(data['dark.color.onSurface']),
      darkColorSurfaceDim: _parseColor(data['dark.color.surfaceDim']),
      darkColorSurfaceBright: _parseColor(data['dark.color.surfaceBright']),
      darkColorSurfaceContainerLowest:
          _parseColor(data['dark.color.surfaceContainerLowest']),
      darkColorSurfaceContainerLow:
          _parseColor(data['dark.color.surfaceContainerLow']),
      darkColorSurfaceContainer:
          _parseColor(data['dark.color.surfaceContainer']),
      darkColorSurfaceContainerHigh:
          _parseColor(data['dark.color.surfaceContainerHigh']),
      darkColorSurfaceContainerHighest:
          _parseColor(data['dark.color.surfaceContainerHighest']),
      darkColorOnSurfaceVariant:
          _parseColor(data['dark.color.onSurfaceVariant']),
      darkColorOutline: _parseColor(data['dark.color.outline']),
      darkColorOutlineVariant:
          _parseColor(data['dark.color.outlineVariant']),
      darkColorInverseSurface:
          _parseColor(data['dark.color.inverseSurface']),
      darkColorOnInverseSurface:
          _parseColor(data['dark.color.onInverseSurface']),
      darkColorInversePrimary:
          _parseColor(data['dark.color.inversePrimary']),
      // Global
      fontFamily: data['global.fontFamily']?.toString(),
      fontFamilyFallback: _parseStringList(data['global.fontFamilyFallback']),
      density: data['global.density']?.toString(),
      useMaterial3: _parseBool(data['global.useMaterial3']),
      // Sub-themes
      defaultRadius: _parseDouble(data['sub.defaultRadius']),
      inputDecoratorRadius: _parseDouble(data['sub.inputDecoratorRadius']),
      cardRadius: _parseDouble(data['sub.cardRadius']),
      chipRadius: _parseDouble(data['sub.chipRadius']),
      textButtonRadius: _parseDouble(data['sub.textButtonRadius']),
      elevatedButtonRadius: _parseDouble(data['sub.elevatedButtonRadius']),
      outlinedButtonRadius: _parseDouble(data['sub.outlinedButtonRadius']),
      filledButtonRadius: _parseDouble(data['sub.filledButtonRadius']),
      segmentedButtonRadius:
          _parseDouble(data['sub.segmentedButtonRadius']),
      toggleButtonsRadius: _parseDouble(data['sub.toggleButtonsRadius']),
      popupMenuRadius: _parseDouble(data['sub.popupMenuRadius']),
      menuRadius: _parseDouble(data['sub.menuRadius']),
      menuBarRadius: _parseDouble(data['sub.menuBarRadius']),
      searchBarRadius: _parseDouble(data['sub.searchBarRadius']),
      searchViewRadius: _parseDouble(data['sub.searchViewRadius']),
      fabRadius: _parseDouble(data['sub.fabRadius']),
      tooltipRadius: _parseDouble(data['sub.tooltipRadius']),
      bottomSheetRadius: _parseDouble(data['sub.bottomSheetRadius']),
      inputDecoratorBorderType: data['sub.inputDecoratorBorderType']?.toString(),
      useM2StyleDividerInM3:
          _parseBool(data['sub.useM2StyleDividerInM3']),
      blendOnLevel: _parseInt(data['sub.blendOnLevel']),
      blendOnColors: _parseBool(data['sub.blendOnColors']),
      cardBorderWidth: _parseDouble(data['sub.cardBorderWidth']),
      cardElevation: _parseDouble(data['sub.cardElevation']),
      // AppBar
      appBarBackgroundColor: _parseColor(data['appBar.backgroundColor']),
      appBarForegroundColor: _parseColor(data['appBar.foregroundColor']),
      appBarSurfaceTintColor: _parseColor(data['appBar.surfaceTintColor']),
      appBarElevation: _parseDouble(data['appBar.elevation']),
      appBarScrolledUnderElevation:
          _parseDouble(data['appBar.scrolledUnderElevation']),
      appBarCenterTitle: _parseBool(data['appBar.centerTitle']),
      // NavigationRail
      navRailBackgroundColor: _parseColor(data['navRail.backgroundColor']),
      navRailIndicatorColor: _parseColor(data['navRail.indicatorColor']),
      navRailSelectedIconColor:
          _parseColor(data['navRail.selectedIconColor']),
      navRailUnselectedIconColor:
          _parseColor(data['navRail.unselectedIconColor']),
      navRailSelectedLabelColor:
          _parseColor(data['navRail.selectedLabelColor']),
      navRailUnselectedLabelColor:
          _parseColor(data['navRail.unselectedLabelColor']),
      // NavigationBar
      navBarBackgroundColor: _parseColor(data['navBar.backgroundColor']),
      navBarIndicatorColor: _parseColor(data['navBar.indicatorColor']),
      // Card
      cardColor: _parseColor(data['card.color']),
      // Dialog
      dialogBackgroundColor: _parseColor(data['dialog.backgroundColor']),
      // Divider
      dividerColor: _parseColor(data['divider.color']),
      dividerThickness: _parseDouble(data['divider.thickness']),
      // ListTile
      listTileIconColor: _parseColor(data['listTile.iconColor']),
      listTileTextColor: _parseColor(data['listTile.textColor']),
      listTileTileColor: _parseColor(data['listTile.tileColor']),
      listTileSelectedTileColor:
          _parseColor(data['listTile.selectedTileColor']),
      listTileDense: _parseBool(data['listTile.dense']),
      // Scrollbar
      scrollbarThumbColor: _parseColor(data['scrollbar.thumbColor']),
      scrollbarTrackColor: _parseColor(data['scrollbar.trackColor']),
      scrollbarThickness: _parseDouble(data['scrollbar.thickness']),
      // Chip
      chipBackgroundColor: _parseColor(data['chip.backgroundColor']),
      // BottomSheet
      bottomSheetBackgroundColor:
          _parseColor(data['bottomSheet.backgroundColor']),
      // PopupMenu
      popupMenuBackgroundColor:
          _parseColor(data['popupMenu.backgroundColor']),
    );
  }

  // ── Color resolution ──

  Color _c(Color? light, Color? dark, Brightness brightness, Color fallback) {
    if (brightness == Brightness.dark) {
      return dark ?? light ?? fallback;
    }
    return light ?? fallback;
  }

  ColorScheme toColorScheme({required Brightness brightness}) {
    // Generate a base scheme from primary if available, else use defaults
    final baseSeed = _c(colorPrimary, darkColorPrimary, brightness, Colors.teal);
    final base = ColorScheme.fromSeed(seedColor: baseSeed, brightness: brightness);

    return ColorScheme(
      brightness: brightness,
      primary: _c(colorPrimary, darkColorPrimary, brightness, base.primary),
      onPrimary: _c(colorOnPrimary, darkColorOnPrimary, brightness, base.onPrimary),
      primaryContainer: _c(colorPrimaryContainer, darkColorPrimaryContainer, brightness, base.primaryContainer),
      onPrimaryContainer: _c(colorOnPrimaryContainer, darkColorOnPrimaryContainer, brightness, base.onPrimaryContainer),
      secondary: _c(colorSecondary, darkColorSecondary, brightness, base.secondary),
      onSecondary: _c(colorOnSecondary, darkColorOnSecondary, brightness, base.onSecondary),
      secondaryContainer: _c(colorSecondaryContainer, darkColorSecondaryContainer, brightness, base.secondaryContainer),
      onSecondaryContainer: _c(colorOnSecondaryContainer, darkColorOnSecondaryContainer, brightness, base.onSecondaryContainer),
      tertiary: _c(colorTertiary, darkColorTertiary, brightness, base.tertiary),
      onTertiary: _c(colorOnTertiary, darkColorOnTertiary, brightness, base.onTertiary),
      tertiaryContainer: _c(colorTertiaryContainer, darkColorTertiaryContainer, brightness, base.tertiaryContainer),
      onTertiaryContainer: _c(colorOnTertiaryContainer, darkColorOnTertiaryContainer, brightness, base.onTertiaryContainer),
      error: _c(colorError, darkColorError, brightness, base.error),
      onError: _c(colorOnError, darkColorOnError, brightness, base.onError),
      errorContainer: _c(colorErrorContainer, darkColorErrorContainer, brightness, base.errorContainer),
      onErrorContainer: _c(colorOnErrorContainer, darkColorOnErrorContainer, brightness, base.onErrorContainer),
      surface: _c(colorSurface, darkColorSurface, brightness, base.surface),
      onSurface: _c(colorOnSurface, darkColorOnSurface, brightness, base.onSurface),
      surfaceDim: _c(colorSurfaceDim, darkColorSurfaceDim, brightness, base.surfaceDim),
      surfaceBright: _c(colorSurfaceBright, darkColorSurfaceBright, brightness, base.surfaceBright),
      surfaceContainerLowest: _c(colorSurfaceContainerLowest, darkColorSurfaceContainerLowest, brightness, base.surfaceContainerLowest),
      surfaceContainerLow: _c(colorSurfaceContainerLow, darkColorSurfaceContainerLow, brightness, base.surfaceContainerLow),
      surfaceContainer: _c(colorSurfaceContainer, darkColorSurfaceContainer, brightness, base.surfaceContainer),
      surfaceContainerHigh: _c(colorSurfaceContainerHigh, darkColorSurfaceContainerHigh, brightness, base.surfaceContainerHigh),
      surfaceContainerHighest: _c(colorSurfaceContainerHighest, darkColorSurfaceContainerHighest, brightness, base.surfaceContainerHighest),
      onSurfaceVariant: _c(colorOnSurfaceVariant, darkColorOnSurfaceVariant, brightness, base.onSurfaceVariant),
      outline: _c(colorOutline, darkColorOutline, brightness, base.outline),
      outlineVariant: _c(colorOutlineVariant, darkColorOutlineVariant, brightness, base.outlineVariant),
      inverseSurface: _c(colorInverseSurface, darkColorInverseSurface, brightness, base.inverseSurface),
      onInverseSurface: _c(colorOnInverseSurface, darkColorOnInverseSurface, brightness, base.onInverseSurface),
      inversePrimary: _c(colorInversePrimary, darkColorInversePrimary, brightness, base.inversePrimary),
      scrim: _c(colorScrim, null, brightness, base.scrim),
      shadow: _c(colorShadow, null, brightness, base.shadow),
    );
  }

  FlexSubThemesData toSubThemes() {
    return FlexSubThemesData(
      defaultRadius: defaultRadius,
      inputDecoratorRadius: inputDecoratorRadius,
      cardRadius: cardRadius,
      chipRadius: chipRadius,
      textButtonRadius: textButtonRadius,
      elevatedButtonRadius: elevatedButtonRadius,
      outlinedButtonRadius: outlinedButtonRadius,
      filledButtonRadius: filledButtonRadius,
      segmentedButtonRadius: segmentedButtonRadius,
      toggleButtonsRadius: toggleButtonsRadius,
      popupMenuRadius: popupMenuRadius,
      menuRadius: menuRadius,
      menuBarRadius: menuBarRadius,
      searchBarRadius: searchBarRadius,
      searchViewRadius: searchViewRadius,
      fabRadius: fabRadius,
      tooltipRadius: tooltipRadius,
      bottomSheetRadius: bottomSheetRadius,
      inputDecoratorBorderType: inputDecoratorBorderType == 'underline'
          ? FlexInputBorderType.underline
          : FlexInputBorderType.outline,
      useM2StyleDividerInM3: useM2StyleDividerInM3 ?? false,
      blendOnLevel: blendOnLevel ?? 10,
      blendOnColors: blendOnColors ?? true,
      cardBorderWidth: cardBorderWidth,
      cardElevation: cardElevation,
    );
  }

  ThemeData toThemeData({required Brightness brightness}) {
    final scheme = toColorScheme(brightness: brightness);
    final subThemes = toSubThemes();
    final effectiveFontFamily = fontFamily ?? 'HarmonyOS Sans SC';

    return FlexColorScheme(
      colorScheme: scheme,
      useMaterial3: useMaterial3 ?? true,
      fontFamily: effectiveFontFamily,
      fontFamilyFallback: fontFamilyFallback,
      visualDensity: density == 'compact'
          ? VisualDensity.compact
          : VisualDensity.standard,
      subThemesData: subThemes,
    ).toTheme.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBackgroundColor ?? scheme.surface,
        surfaceTintColor: appBarSurfaceTintColor ?? Colors.transparent,
        foregroundColor: appBarForegroundColor ?? scheme.onSurface,
        elevation: appBarElevation ?? 0,
        scrolledUnderElevation: appBarScrolledUnderElevation ?? 0,
        centerTitle: appBarCenterTitle,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: navRailBackgroundColor ?? scheme.surfaceContainerLowest,
        indicatorColor: navRailIndicatorColor ?? scheme.secondaryContainer,
        selectedIconTheme: IconThemeData(
          color: navRailSelectedIconColor ?? scheme.onSecondaryContainer,
        ),
        selectedLabelTextStyle: TextStyle(
          color: navRailSelectedLabelColor ?? scheme.onSurface,
        ),
        unselectedIconTheme: IconThemeData(
          color: navRailUnselectedIconColor ?? scheme.onSurfaceVariant,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: navRailUnselectedLabelColor ?? scheme.onSurfaceVariant,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navBarBackgroundColor ?? scheme.surfaceContainer,
        indicatorColor: navBarIndicatorColor ?? scheme.secondaryContainer,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dialogBackgroundColor,
      ),
      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: dividerThickness,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: listTileIconColor,
        textColor: listTileTextColor,
        tileColor: listTileTileColor,
        selectedTileColor: listTileSelectedTileColor,
        dense: listTileDense,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(scrollbarThumbColor),
        trackColor: WidgetStatePropertyAll(scrollbarTrackColor),
        thickness: scrollbarThickness != null
            ? WidgetStatePropertyAll(scrollbarThickness)
            : null,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: chipBackgroundColor,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bottomSheetBackgroundColor,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: popupMenuBackgroundColor,
      ),
    );
  }
}
