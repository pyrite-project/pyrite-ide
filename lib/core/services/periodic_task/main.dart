import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'provider.dart';

class PeriodicTaskLifecycleObserver extends ConsumerStatefulWidget {
  final Widget child;
  const PeriodicTaskLifecycleObserver({super.key, required this.child});

  @override
  ConsumerState<PeriodicTaskLifecycleObserver> createState() =>
      _PeriodicTaskLifecycleObserverState();
}

class _PeriodicTaskLifecycleObserverState
    extends ConsumerState<PeriodicTaskLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final manager = ref.read(periodicTaskManagerProvider);
    if (state == AppLifecycleState.resumed) {
      manager.resume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      manager.pause();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
