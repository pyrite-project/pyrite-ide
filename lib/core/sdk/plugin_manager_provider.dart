import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PluginStatus { usable, installing, disusable, uninstall }

enum PluginPermission { ui }

class Plugin {
  const Plugin({
    required this.id,
    required this.name,
    this.status = PluginStatus.installing,
    this.permissions = const [],
  });
  final String id;
  final String name;
  final PluginStatus status;
  final List permissions;
}

class PluginManagerNotifier extends StateNotifier<Map<String, Plugin>> {
  final Ref ref;

  PluginManagerNotifier(this.ref) : super({});

  void register(Plugin plugin) {
    for (Plugin p in state.values) {
      if (p.id == plugin.id) return;
    }
    print("object");

    state = {...state, plugin.id: plugin};
  }

  void remove(Plugin plugin) {
    state = {...state}..remove(plugin.id);
  }
}

final StateNotifierProvider<PluginManagerNotifier, Map<String, Plugin>>
pluginManagerProvider = StateNotifierProvider(
  (ref) => PluginManagerNotifier(ref),
);
