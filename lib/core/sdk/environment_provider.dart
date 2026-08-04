import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Responsive layout mode, derived from the host's breakpoints.
enum LayoutMode { mobile, tablet, desktop }

/// A snapshot of the runtime environment as plugins see it.
@immutable
class EnvironmentSnapshot {
  const EnvironmentSnapshot({
    required this.os,
    required this.isDesktopPlatform,
    required this.layoutMode,
    required this.width,
    required this.height,
    this.locale = 'en',
    this.themeMode = 'light',
  });

  final String os;
  final bool isDesktopPlatform;
  final LayoutMode layoutMode;
  final int width;
  final int height;
  final String locale;
  final String themeMode;

  Map<String, dynamic> toJson() => {
    'os': os,
    'isDesktopPlatform': isDesktopPlatform,
    'layoutMode': layoutMode.name,
    'width': width,
    'height': height,
    'locale': locale,
    'themeMode': themeMode,
  };

  EnvironmentSnapshot copyWith({
    LayoutMode? layoutMode,
    int? width,
    int? height,
    String? locale,
    String? themeMode,
  }) => EnvironmentSnapshot(
    os: os,
    isDesktopPlatform: isDesktopPlatform,
    layoutMode: layoutMode ?? this.layoutMode,
    width: width ?? this.width,
    height: height ?? this.height,
    locale: locale ?? this.locale,
    themeMode: themeMode ?? this.themeMode,
  );

  @override
  bool operator ==(Object other) =>
      other is EnvironmentSnapshot &&
      other.os == os &&
      other.isDesktopPlatform == isDesktopPlatform &&
      other.layoutMode == layoutMode &&
      other.width == width &&
      other.height == height &&
      other.locale == locale &&
      other.themeMode == themeMode;

  @override
  int get hashCode => Object.hash(
    os,
    isDesktopPlatform,
    layoutMode,
    width,
    height,
    locale,
    themeMode,
  );
}

/// Holds the current environment and notifies when it changes materially.
///
/// The widget layer feeds layout updates in via [update]; a query API reads
/// [snapshot] without needing a `BuildContext`, so a plugin can ask at any
/// point in its lifecycle — including before any view is mounted.
///
/// Resize fires per frame, so notifications are debounced and only sent when a
/// field a plugin would act on actually changed. Width/height alone do not
/// notify: a plugin choosing a compact layout cares about the mode, and waking
/// it on every pixel would be the saturation this guards against.
class EnvironmentNotifier extends ChangeNotifier {
  EnvironmentNotifier({
    Duration debounce = const Duration(milliseconds: 150),
    String? osOverride,
    bool? isDesktopOverride,
  }) : _debounce = debounce,
       _snapshot = EnvironmentSnapshot(
         os: osOverride ?? _detectOs(),
         isDesktopPlatform: isDesktopOverride ?? _detectDesktop(),
         layoutMode: LayoutMode.desktop,
         width: 0,
         height: 0,
       );

  final Duration _debounce;
  Timer? _timer;
  EnvironmentSnapshot _snapshot;

  /// The current environment. Always safe to read.
  EnvironmentSnapshot get snapshot => _snapshot;

  /// Records the latest observed environment.
  ///
  /// Notifies only when [LayoutMode], locale, or theme changed — the things a
  /// plugin would re-render for.
  void update({
    required LayoutMode layoutMode,
    required int width,
    required int height,
    String? locale,
    String? themeMode,
  }) {
    final previous = _snapshot;
    _snapshot = _snapshot.copyWith(
      layoutMode: layoutMode,
      width: width,
      height: height,
      locale: locale,
      themeMode: themeMode,
    );

    final material =
        previous.layoutMode != _snapshot.layoutMode ||
        previous.locale != _snapshot.locale ||
        previous.themeMode != _snapshot.themeMode;
    if (!material) return;

    _timer?.cancel();
    _timer = Timer(_debounce, notifyListeners);
  }

  static String _detectOs() {
    if (kIsWeb) return 'web';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  static bool _detectDesktop() =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
