import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

BuildContext? get appContext => _appContext;
BuildContext? _appContext;

void setAppContext(BuildContext context) {
  _appContext = context;
}

enum ThemeStyle {
  standard('标准', 'standard'),
  compact('紧凑', 'compact'),
  comfortable('舒适', 'comfortable');

  final String label;
  final String value;
  const ThemeStyle(this.label, this.value);

  static ThemeStyle fromValue(String? v) {
    return switch (v) {
      'compact' => ThemeStyle.compact,
      'comfortable' => ThemeStyle.comfortable,
      _ => ThemeStyle.standard,
    };
  }
}

late final ProviderContainer container;
final StateProvider<ThemeMode> themeMode = StateProvider(
  (ref) => ThemeMode.system,
);
final StateProvider<String> editorThemeKey = StateProvider(
  (ref) => "atom-one",
);
final StateProvider<Color?> themeColor = StateProvider((ref) => null);
final StateProvider<ThemeStyle> themeStyle = StateProvider(
  (ref) => ThemeStyle.standard,
);
final StateProvider<String?> activePluginThemeId = StateProvider(
  (ref) => null,
);
