import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/environment_provider.dart';

/// Host-wide environment state, shared by the query API and the broadcaster.
final environmentNotifierProvider = Provider<EnvironmentNotifier>((ref) {
  final notifier = EnvironmentNotifier();
  ref.onDispose(notifier.dispose);
  return notifier;
});
