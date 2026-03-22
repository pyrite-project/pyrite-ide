import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'manager.dart';

final periodicTaskManagerProvider = Provider<PeriodicTaskManager>((ref) {
  final manager = PeriodicTaskManager();
  ref.onDispose(manager.dispose);
  return manager;
});
