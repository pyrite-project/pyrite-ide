import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';

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
  standard(I18nKey.appThemeStandard, 'standard'),
  compact(I18nKey.appThemeCompact, 'compact'),
  comfortable(I18nKey.appThemeComfortable, 'comfortable');

  /// The key this style's display name lives under.
  final I18nKey labelKey;
  final String value;
  const ThemeStyle(this.labelKey, this.value);

  /// Fallback display name, for callers with no registry in reach.
  String get label => labelKey.fallback;

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
