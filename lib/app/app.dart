import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/board_manager/utils.dart';
import 'package:pyrite_ide/features/macos_menu.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:dynamic_color/dynamic_color.dart';

class PyriteIDE extends ConsumerWidget {
  const PyriteIDE({super.key});

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
  }) {
    final scheme = _resolveColorScheme(
      dynamicScheme: dynamicScheme,
      seedColor: seedColor,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: "HarmonyOS Sans SC",
      brightness: brightness,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.inverseOnSurface),
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
        final app = MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: appName,
          themeMode: ref.watch(themeMode),
          theme: _buildTheme(
            dynamicScheme: lightDynamic,
            seedColor: seedColor,
            brightness: Brightness.light,
          ),
          darkTheme: _buildTheme(
            dynamicScheme: darkDynamic,
            seedColor: seedColor,
            brightness: Brightness.dark,
          ),
          routerConfig: routes,
          builder: (context, child) {
            // ref.read(lspClientProvider);
            return Material(
              child: ResponsiveBreakpoints.builder(
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
            );
          },
        );

        if (!Platform.isMacOS) return app;
        return MacOSMenu(app: app);
      },
    );
  }
}
