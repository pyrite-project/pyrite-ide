import 'dart:io';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/constants/theme_density.dart';
import 'package:pyrite_ide/core/sdk/environment_broadcaster.dart';
import 'package:pyrite_ide/core/sdk/models/plugin_theme.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/features/macos_menu.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:dynamic_color/dynamic_color.dart';

class PyriteIDE extends ConsumerWidget {
  const PyriteIDE({super.key});

  FlexSubThemesData _subThemes(ThemeStyle style) {
    switch (style) {
      case ThemeStyle.compact:
        return const FlexSubThemesData(
          defaultRadius: 2,
          inputDecoratorRadius: 2,
          cardRadius: 2,
          chipRadius: 2,
          textButtonRadius: 2,
          elevatedButtonRadius: 2,
          outlinedButtonRadius: 2,
          filledButtonRadius: 2,
          segmentedButtonRadius: 2,
          toggleButtonsRadius: 2,
          popupMenuRadius: 2,
          menuRadius: 2,
          menuBarRadius: 2,
          searchBarRadius: 2,
          searchViewRadius: 2,
          fabRadius: 16,
          useM2StyleDividerInM3: true,
          blendOnLevel: 20,
          blendOnColors: false,
          inputDecoratorBorderType: FlexInputBorderType.outline,
          cardBorderWidth: 1,
          cardElevation: 0,
        );
      case ThemeStyle.comfortable:
        return const FlexSubThemesData(
          defaultRadius: 4,
          inputDecoratorRadius: 4,
          cardRadius: 8,
          chipRadius: 6,
          blendOnLevel: 10,
          blendOnColors: true,
        );
      default: // standard
        return const FlexSubThemesData();
    }
  }

  ColorScheme _resolveColorScheme({
    required ColorScheme? dynamicScheme,
    required Color? seedColor,
    required Brightness brightness,
  }) {
    if (seedColor != null) {
      return ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
    }
    if (dynamicScheme != null) return dynamicScheme;
    return ColorScheme.fromSeed(
      seedColor: Colors.deepOrange,
      brightness: brightness,
    );
  }

  ThemeData _buildTheme({
    required ColorScheme? dynamicScheme,
    required Color? seedColor,
    required Brightness brightness,
    required ThemeStyle style,
    PluginThemeData? pluginTheme,
  }) {
    final tokens = ThemeDensityTokens.forStyle(style);
    ThemeData baseTheme;
    if (pluginTheme != null) {
      baseTheme = pluginTheme.toThemeData(brightness: brightness);
    } else {
      final scheme = _resolveColorScheme(
        dynamicScheme: dynamicScheme,
        seedColor: seedColor,
        brightness: brightness,
      );

      if (Platform.isAndroid) {
        SystemUiOverlayStyle systemUiOverlayStyle = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: scheme.surfaceContainer,
        );
        SystemChrome.setSystemUIOverlayStyle(systemUiOverlayStyle);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      baseTheme = FlexColorScheme(
        colorScheme: scheme,
        useMaterial3: true,
        fontFamily: "HarmonyOS Sans SC",
        visualDensity: tokens.visualDensity,
        subThemesData: _subThemes(style),
      ).toTheme.copyWith(
        scaffoldBackgroundColor: scheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          foregroundColor: scheme.onSurface,
        ),
        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: scheme.surfaceContainerLowest,
          indicatorColor: scheme.secondaryContainer,
          selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
          selectedLabelTextStyle: TextStyle(color: scheme.onSurface),
          unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
          unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: scheme.surfaceContainer,
          indicatorColor: scheme.secondaryContainer,
        ),
      );
    }

    return _applyDensityTokens(baseTheme, tokens);
  }

  /// Applies the desktop density/typography overlay on top of any base theme
  /// (built-in or plugin-provided) so the selected style tier always wins.
  ThemeData _applyDensityTokens(
    ThemeData theme,
    ThemeDensityTokens tokens,
  ) {
    return theme.copyWith(
      visualDensity: tokens.visualDensity,
      materialTapTargetSize: tokens.materialTapTargetSize,
      textTheme: scaleTextTheme(theme.textTheme, tokens.fontSizeDelta),
      appBarTheme: theme.appBarTheme.copyWith(
        toolbarHeight: tokens.toolbarHeight,
      ),
      iconButtonTheme: _overlayIconButtonTheme(
        theme.iconButtonTheme,
        tokens.iconButtonTheme,
      ),
      buttonTheme: theme.buttonTheme.copyWith(
        minWidth: tokens.buttonMinimumSize.width,
        height: tokens.buttonMinimumSize.height,
        materialTapTargetSize: tokens.materialTapTargetSize,
      ),
      navigationRailTheme: _overlayNavRailTheme(
        theme.navigationRailTheme,
        tokens.navIconSize,
        tokens.navRailWidth,
      ),
      navigationDrawerTheme: _overlayNavDrawerTheme(
        theme.navigationDrawerTheme,
        tokens.navIconSize,
        tokens.drawerTileHeight,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: tokens.buttonMinimumSize,
          visualDensity: tokens.visualDensity,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: tokens.buttonMinimumSize,
          visualDensity: tokens.visualDensity,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: tokens.buttonMinimumSize,
          visualDensity: tokens.visualDensity,
        ),
      ),
      inputDecorationTheme: tokens.fontSizeDelta > 0
          ? theme.inputDecorationTheme.copyWith(isDense: true)
          : theme.inputDecorationTheme,
    );
  }

  /// Merges the tier [tokens] onto the base theme's icon button theme so that
  /// plugin/base colors and shapes are preserved while the tier's size,
  /// padding and tap target win.
  IconButtonThemeData? _overlayIconButtonTheme(
    IconButtonThemeData? base,
    IconButtonThemeData tokens,
  ) {
    if (base == null || base.style == null) return tokens;
    final b = base.style!;
    final t = tokens.style!;
    return IconButtonThemeData(
      style: ButtonStyle(
        animationDuration: t.animationDuration ?? b.animationDuration,
        visualDensity: t.visualDensity ?? b.visualDensity,
        foregroundColor: t.foregroundColor ?? b.foregroundColor,
        backgroundColor: t.backgroundColor ?? b.backgroundColor,
        overlayColor: t.overlayColor ?? b.overlayColor,
        shadowColor: t.shadowColor ?? b.shadowColor,
        surfaceTintColor: t.surfaceTintColor ?? b.surfaceTintColor,
        elevation: t.elevation ?? b.elevation,
        padding: t.padding ?? b.padding,
        minimumSize: t.minimumSize ?? b.minimumSize,
        fixedSize: t.fixedSize ?? b.fixedSize,
        maximumSize: t.maximumSize ?? b.maximumSize,
        iconSize: t.iconSize ?? b.iconSize,
        iconColor: t.iconColor ?? b.iconColor,
        side: t.side ?? b.side,
        shape: t.shape ?? b.shape,
        mouseCursor: t.mouseCursor ?? b.mouseCursor,
        tapTargetSize: t.tapTargetSize ?? b.tapTargetSize,
        textStyle: t.textStyle ?? b.textStyle,
        enableFeedback: t.enableFeedback ?? b.enableFeedback,
        alignment: t.alignment ?? b.alignment,
        splashFactory: t.splashFactory ?? b.splashFactory,
      ),
    );
  }

  /// Overlays the tier's [navIconSize]/[navRailWidth] onto the base navigation
  /// rail theme while keeping its colors.
  NavigationRailThemeData? _overlayNavRailTheme(
    NavigationRailThemeData? base,
    double navIconSize,
    double navRailWidth,
  ) {
    if (base == null) {
      return NavigationRailThemeData(
        minWidth: navRailWidth,
        useIndicator: false,
        selectedIconTheme: IconThemeData(size: navIconSize),
        unselectedIconTheme: IconThemeData(size: navIconSize),
      );
    }
    return NavigationRailThemeData(
      backgroundColor: base.backgroundColor,
      elevation: base.elevation,
      selectedLabelTextStyle: base.selectedLabelTextStyle,
      unselectedLabelTextStyle: base.unselectedLabelTextStyle,
      selectedIconTheme: IconThemeData(
        size: navIconSize,
        color: base.selectedIconTheme?.color,
      ),
      unselectedIconTheme: IconThemeData(
        size: navIconSize,
        color: base.unselectedIconTheme?.color,
      ),
      groupAlignment: base.groupAlignment,
      minWidth: base.minWidth ?? navRailWidth,
      useIndicator: false,
      minExtendedWidth: base.minExtendedWidth,
      labelType: base.labelType,
      indicatorColor: base.indicatorColor,
      indicatorShape: base.indicatorShape,
    );
  }

  /// Overlays the tier's [navIconSize]/[drawerTileHeight] onto the navigation
  /// drawer theme while keeping its colors.
  NavigationDrawerThemeData? _overlayNavDrawerTheme(
    NavigationDrawerThemeData? base,
    double navIconSize,
    double drawerTileHeight,
  ) {
    if (base == null) {
      return NavigationDrawerThemeData(
        tileHeight: drawerTileHeight,
        iconTheme: WidgetStatePropertyAll<IconThemeData?>(
          IconThemeData(size: navIconSize),
        ),
      );
    }
    return base.copyWith(
      tileHeight: drawerTileHeight,
      iconTheme: WidgetStatePropertyAll<IconThemeData?>(
        IconThemeData(size: navIconSize),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(serialProvider.notifier).registerUpdateTask();

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final seedColor = ref.watch(themeColor);
        final style = ref.watch(themeStyle);
        final activePluginThemeIdValue = ref.watch(activePluginThemeId);
        final dataRegistry = ref.watch(dataRegistryProvider);

        // Resolve active plugin theme
        PluginThemeData? pluginTheme;
        if (activePluginThemeIdValue != null) {
          pluginTheme = dataRegistry.getThemeById(activePluginThemeIdValue);
        }

        // Determine effective theme mode (plugin may force it)
        ThemeMode effectiveThemeMode = ref.watch(themeMode);
        if (pluginTheme?.mode == 'dark') {
          effectiveThemeMode = ThemeMode.dark;
        } else if (pluginTheme?.mode == 'light') {
          effectiveThemeMode = ThemeMode.light;
        }

        final app = MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: appName,
          themeMode: effectiveThemeMode,
          theme: _buildTheme(
            dynamicScheme: lightDynamic,
            seedColor: seedColor,
            brightness: Brightness.light,
            style: style,
            pluginTheme: pluginTheme,
          ),
          darkTheme: _buildTheme(
            dynamicScheme: darkDynamic,
            seedColor: seedColor,
            brightness: Brightness.dark,
            style: style,
            pluginTheme: pluginTheme,
          ),
          routerConfig: routes,
          builder: (context, child) {
            setAppContext(context);
            return Material(
              child: Stack(
                children: [
                  ResponsiveBreakpoints.builder(
                    // Inside the responsive scope so it can read the
                    // breakpoints that define the plugin-facing layout mode.
                    child: EnvironmentBroadcaster(child: child!),
                    breakpoints: [
                      const Breakpoint(start: 0, end: 599, name: MOBILE),
                      const Breakpoint(start: 600, end: 839, name: TABLET),
                      const Breakpoint(
                        start: 840,
                        end: double.infinity,
                        name: DESKTOP,
                      ),
                    ],
                  ),
                  const IdeMessageHost(),
                ],
              ),
            );
          },
        );

        if (Platform.isMacOS || defaultTargetPlatform == TargetPlatform.macOS) {
          return MacOSMenu(app: app);
        }
        return app;
      },
    );
  }
}
