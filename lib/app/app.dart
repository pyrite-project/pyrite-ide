import 'dart:io';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/sdk/models/plugin_theme.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';
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
    return ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness);
  }

  ThemeData _buildTheme({
    required ColorScheme? dynamicScheme,
    required Color? seedColor,
    required Brightness brightness,
    required ThemeStyle style,
    PluginThemeData? pluginTheme,
  }) {
    if (pluginTheme != null) {
      return pluginTheme.toThemeData(brightness: brightness);
    }

    final scheme = _resolveColorScheme(
      dynamicScheme: dynamicScheme,
      seedColor: seedColor,
      brightness: brightness,
    );
    return FlexColorScheme(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: "HarmonyOS Sans SC",
      visualDensity: style == ThemeStyle.compact
          ? VisualDensity.compact
          : VisualDensity.standard,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(getUsbSerialProvider().notifier).registerUpdateTask();
    ref.read(pluginRunManagerProvider.notifier).setupRouterListener();

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
                    child: child!,
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
