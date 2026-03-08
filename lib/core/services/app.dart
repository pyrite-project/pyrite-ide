import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_highlight/styles/atom-one-dark-reasonable.dart';

late final ProviderContainer container;
final StateProvider<ThemeMode> themeMode = StateProvider(
  (ref) => ThemeMode.system,
);
final StateProvider<Map<String, TextStyle>> editorThemeMode = StateProvider(
  (ref) => atomOneDarkReasonableTheme,
);
final StateProvider<Color?> themeColor = StateProvider((ref) => null);
