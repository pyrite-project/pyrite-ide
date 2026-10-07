import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The root navigator, so [appContext] can hand out a context that can push
/// routes.
///
/// The app shell's `MaterialApp.router` builder context cannot do that: the
/// builder sits *above* the Navigator, so `Navigator.of` on it throws
/// "Navigator operation requested with a context that does not include a
/// Navigator". Attaching this key to the `GoRouter` in `routes.dart` gives us
/// the Navigator's own context instead, which does resolve a Navigator.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'appRootNavigator',
);

/// A context that non-widget code can show dialogs on.
///
/// Prefers the root Navigator and only falls back to the shell's builder
/// context, which is useless for navigation -- see [appNavigatorKey]. The
/// fallback still carries a Theme and a Directionality, so it is worth having
/// for the window between startup and the router's first frame.
BuildContext? get appContext => appNavigatorKey.currentContext ?? _appContext;

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
final StateProvider<String> editorThemeKey = StateProvider((ref) => "atom-one");
final StateProvider<Color?> themeColor = StateProvider((ref) => null);
final StateProvider<ThemeStyle> themeStyle = StateProvider(
  (ref) => ThemeStyle.standard,
);
final StateProvider<String?> activePluginThemeId = StateProvider((ref) => null);
final StateProvider<bool> welcomeCompletedProvider = StateProvider(
  (ref) => false,
);

final StateProvider<bool> alwaysOnTopProvider = StateProvider((ref) => false);
