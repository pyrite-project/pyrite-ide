import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_highlight/styles/atom-one-dark-reasonable.dart';

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
final StateProvider<Map<String, TextStyle>> editorThemeMode = StateProvider(
  (ref) => atomOneDarkReasonableTheme,
);
final StateProvider<Color?> themeColor = StateProvider((ref) => null);
final StateProvider<ThemeStyle> themeStyle = StateProvider(
  (ref) => ThemeStyle.standard,
);
