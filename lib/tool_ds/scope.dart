import 'package:flutter/material.dart';
import 'package:pyrite_ide/tool_ds/tokens.dart';

class ToolScope extends StatelessWidget {
  const ToolScope({
    super.key,
    required this.child,
    this.uiFontFamily,
    this.monoFontFamily,
  });

  final Widget child;
  final String? uiFontFamily;
  final String? monoFontFamily;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final tokens = brightness == Brightness.dark
        ? ToolTokens.dark(
            uiFontFamily: uiFontFamily,
            monoFontFamily: monoFontFamily,
          )
        : ToolTokens.light(
            uiFontFamily: uiFontFamily,
            monoFontFamily: monoFontFamily,
          );

    return ToolTheme(data: tokens, child: child);
  }
}

class ToolTheme extends InheritedWidget {
  const ToolTheme({super.key, required this.data, required super.child});

  final ToolTokens data;

  static ToolTokens of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<ToolTheme>();
    assert(theme != null, 'ToolTheme not found. Wrap subtree with ToolScope.');
    return theme!.data;
  }

  static ToolTokens maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ToolTheme>()?.data ??
        ToolTokens.light();
  }

  @override
  bool updateShouldNotify(ToolTheme oldWidget) => data != oldWidget.data;
}

extension ToolTokensBuildContextX on BuildContext {
  ToolTokens get tool => ToolTheme.of(this);
}
