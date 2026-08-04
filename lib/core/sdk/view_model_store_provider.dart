import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';

/// Host-wide store of native plugin view models, shared across sessions.
///
/// Instance keys embed pluginId/sessionId, so a restarted session's snapshots
/// never collide with a previous session's; [ViewModelStore.clearSession] drops
/// a stopped session's instances.
final Provider<ViewModelStore> viewModelStoreProvider = Provider((ref) {
  final store = ViewModelStore();
  ref.onDispose(store.clear);
  return store;
});
