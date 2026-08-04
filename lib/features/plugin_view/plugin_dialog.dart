import 'package:flutter/material.dart';

/// Keeps a plugin-declared dialog in the host navigator rather than inline in
/// the component layout.
class PluginDialogHost extends StatefulWidget {
  const PluginDialogHost({
    super.key,
    required this.open,
    required this.child,
    required this.onClosed,
    this.title,
  });

  final bool open;
  final String? title;
  final Widget child;
  final ValueChanged<Object?> onClosed;

  @override
  State<PluginDialogHost> createState() => PluginDialogHostState();
}

class PluginDialogHostState extends State<PluginDialogHost> {
  DialogRoute<Object?>? _route;
  bool _programmaticClose = false;
  bool _syncScheduled = false;

  bool get isOpen => _route != null;

  void show() {
    if (_route == null) _syncRoute(forceOpen: true);
  }

  void close([Object? result]) {
    final route = _route;
    if (route == null) return;
    _programmaticClose = true;
    route.navigator?.removeRoute(route, result);
  }

  @override
  void didUpdateWidget(covariant PluginDialogHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _route?.changedExternalState();
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _syncRoute();
    });
  }

  void _syncRoute({bool forceOpen = false}) {
    if ((widget.open || forceOpen) && _route == null) {
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = DialogRoute<Object?>(
        context: context,
        barrierDismissible: true,
        builder: (_) => AlertDialog(
          title: widget.title == null ? null : Text(widget.title!),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
            child: widget.child,
          ),
        ),
      );
      _route = route;
      navigator.push(route).then((result) {
        if (!mounted) return;
        final notify = !_programmaticClose;
        _programmaticClose = false;
        _route = null;
        if (notify) widget.onClosed(result);
      });
      return;
    }
    final route = _route;
    if (!widget.open && route != null) {
      _programmaticClose = true;
      route.navigator?.removeRoute(route);
    }
  }

  @override
  void dispose() {
    final route = _route;
    if (route != null) {
      _programmaticClose = true;
      route.navigator?.removeRoute(route);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleSync();
    return const SizedBox.shrink();
  }
}
