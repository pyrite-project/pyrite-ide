import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/services/android_env_deployer/core.dart';
import 'package:pyrite_ide/core/services/android_env_deployer/main.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor.dart';
import 'package:pyrite_ide/core/services/file.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:pyrite_ide/features/macos_menu.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:dynamic_color/dynamic_color.dart';

class PyriteIDE extends ConsumerWidget {
  const PyriteIDE({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final app = MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: appName,
          themeMode: ref.watch(themeMode),
          theme: ThemeData(
            fontFamily: "HarmonyOS Sans SC",
            brightness: Brightness.light,
            colorScheme: (ref.watch(themeColor) == null)
                ? lightDynamic
                : ColorScheme.fromSeed(seedColor: ref.read(themeColor)!),
            appBarTheme: AppBarTheme(surfaceTintColor: Colors.transparent),
          ),
          darkTheme: ThemeData(
            fontFamily: "HarmonyOS Sans SC",
            brightness: Brightness.dark,
            colorScheme: (ref.watch(themeColor) == null)
                ? darkDynamic
                : ColorScheme.fromSeed(
                    seedColor: ref.read(themeColor)!,
                    brightness: Brightness.dark,
                  ),
            appBarTheme: AppBarTheme(surfaceTintColor: Colors.transparent),
          ),
          routerConfig: routes,
          builder: (context, child) {
            ref.read(lspClientProvider);
            return Material(
              child: ResponsiveBreakpoints.builder(
                child: child!,
                breakpoints: [
                  const Breakpoint(start: 0, end: 600, name: MOBILE),
                  const Breakpoint(start: 601, end: 1000, name: TABLET),
                  const Breakpoint(
                    start: 801,
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
