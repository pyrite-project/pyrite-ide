import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/environment_notifier_provider.dart';
import 'package:pyrite_ide/core/sdk/environment_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

/// Feeds host layout changes into the environment notifier and pushes
/// `ide.env.changed` to every running plugin.
///
/// Mounted inside the responsive scope so it can read the breakpoints; the
/// query API stays context-free by reading the notifier's cached snapshot.
class EnvironmentBroadcaster extends ConsumerStatefulWidget {
  const EnvironmentBroadcaster({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<EnvironmentBroadcaster> createState() =>
      _EnvironmentBroadcasterState();
}

class _EnvironmentBroadcasterState
    extends ConsumerState<EnvironmentBroadcaster> {
  EnvironmentNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(environmentNotifierProvider);
    notifier.addListener(_broadcast);
    _notifier = notifier;
  }

  @override
  void dispose() {
    _notifier?.removeListener(_broadcast);
    super.dispose();
  }

  /// Sends the current environment to every running plugin.
  ///
  /// Fire-and-forget: a plugin that is slow to read must not stall a resize.
  void _broadcast() {
    final snapshot = ref.read(environmentNotifierProvider).snapshot.toJson();
    for (final manager in ref.read(pluginRunManagerProvider).values) {
      manager.sendViewFrame(IdeCommands.envChanged, snapshot);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _report();
  }

  void _report() {
    final breakpoints = ResponsiveBreakpoints.of(context);
    final size = MediaQuery.sizeOf(context);
    ref
        .read(environmentNotifierProvider)
        .update(
          layoutMode: breakpoints.isMobile
              ? LayoutMode.mobile
              : breakpoints.isTablet
              ? LayoutMode.tablet
              : LayoutMode.desktop,
          width: size.width.round(),
          height: size.height.round(),
          locale: Localizations.maybeLocaleOf(context)?.toLanguageTag(),
          themeMode: Theme.of(context).brightness == Brightness.dark
              ? 'dark'
              : 'light',
        );
  }

  @override
  Widget build(BuildContext context) {
    // MediaQuery/Theme changes arrive via didChangeDependencies; reporting here
    // too covers rebuilds that don't change dependencies.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report();
    });
    return widget.child;
  }
}
