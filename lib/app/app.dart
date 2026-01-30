import 'package:flutter/material.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:dynamic_color/dynamic_color.dart';

class PyriteIDE extends StatelessWidget {
  const PyriteIDE({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: appName,
          theme: ThemeData(
            fontFamily: "HarmonyOS Sans SC",
            brightness: Brightness.light,
            colorScheme: lightDynamic,
          ),
          darkTheme: ThemeData(
            fontFamily: "HarmonyOS Sans SC",
            brightness: Brightness.dark,
            colorScheme: darkDynamic,
          ),
          routerConfig: routes,
          builder: (context, child) => ResponsiveBreakpoints.builder(
            child: Material(
              textStyle: TextStyle(fontFamily: "HarmonyOS Sans SC"),
              child: child!,
            ),
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
