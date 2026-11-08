import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:pyrite_ide/core/sdk/plugin_install_link.dart';

/// Turns everything the operating system hands the IDE (launch arguments,
/// `pyride://` links, double-clicked `.pyrix` files) into install intents.
///
/// Nothing is installed here: an intent only opens the confirmation tab.
class PluginInstallIntake {
  PluginInstallIntake({
    required this.onIntent,
    Future<String?> Function()? initialLink,
    Stream<String>? linkStream,
  }) : _initialLink = initialLink ?? (() => AppLinks().getInitialLinkString()),
       _linkStream = linkStream ?? AppLinks().stringLinkStream;

  final void Function(PluginInstallIntent intent) onIntent;
  // Raw strings, not Uri: parsing a Windows path such as C:\Users\me\a b.pyrix
  // as a Uri makes "c" the scheme and leaves the path percent-encoded.
  final Future<String?> Function() _initialLink;
  final Stream<String> _linkStream;
  StreamSubscription<String>? _subscription;

  /// Handles what the IDE was launched with, then keeps listening for links
  /// that arrive while it runs. Call once the UI can show a tab.
  Future<void> start(List<String> launchArguments) async {
    for (final argument in launchArguments) {
      _accept(argument);
    }
    try {
      final initial = await _initialLink();
      if (initial != null) _accept(initial);
    } on Object catch (error) {
      // Platforms without link support simply have no initial link.
      debugPrint('PluginInstallIntake: no initial link: $error');
    }
    _subscription ??= _linkStream.listen(
      _accept,
      onError: (Object error) =>
          debugPrint('PluginInstallIntake: link stream error: $error'),
    );
  }

  Future<void> dispose() async => _subscription?.cancel();

  void _accept(String raw) {
    final intent = parsePluginInstallTarget(raw);
    if (intent != null) onIntent(intent);
  }
}
