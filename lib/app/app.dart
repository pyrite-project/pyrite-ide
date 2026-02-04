import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:dynamic_color/dynamic_color.dart';

class PyriteIDE extends ConsumerWidget {
  const PyriteIDE({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(lspClientProvider);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: appName,
          theme: ThemeData(
            fontFamily: "HarmonyOS Sans SC",
            brightness: Brightness.light,
            colorScheme: lightDynamic,
            appBarTheme: AppBarTheme(surfaceTintColor: Colors.transparent),
          ),
          darkTheme: ThemeData(
            fontFamily: "HarmonyOS Sans SC",
            brightness: Brightness.dark,
            colorScheme: darkDynamic,
            appBarTheme: AppBarTheme(surfaceTintColor: Colors.transparent),
          ),
          routerConfig: routes,
          builder: (context, child) => ResponsiveBreakpoints.builder(
            child: Material(child: child!),
            breakpoints: [
              const Breakpoint(start: 0, end: 600, name: MOBILE),
              const Breakpoint(start: 601, end: 1000, name: TABLET),
              const Breakpoint(start: 801, end: double.infinity, name: DESKTOP),
            ],
          ),
        );
      },
    );
  }
}
