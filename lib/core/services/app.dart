import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

late final ProviderContainer container;
final StateProvider<ThemeMode> themeMode = StateProvider(
  (ref) => ThemeMode.system,
);
final StateProvider<Color?> themeColor = StateProvider((ref) => null);
