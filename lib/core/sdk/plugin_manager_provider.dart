import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/persistence/plugin_persistence.dart';

class PluginManagerNotifier extends StateNotifier<Map<String, Plugin>> {
  final Ref ref;
  final PluginPersistence _persistence;
  void Function()? _onChanged;

  PluginManagerNotifier(this.ref, {PluginPersistence? persistence})
    : _persistence = persistence ?? PluginPersistence(),
      super({});

  void setOnChanged(void Function()? callback) {
    _onChanged = callback;
  }

  void loadPersisted(List<PluginPersistedData> plugins) {
    final map = <String, Plugin>{};
    for (final p in plugins) {
      final plugin = p.toPlugin();
      map[plugin.id] = plugin;
    }
    state = map;
  }

  Future<void> autoStart() async {
    for (final plugin in state.values) {
      if (plugin.autoStart && plugin.status == PluginStatus.usable) {
        await ref.read(pluginRunManagerProvider.notifier).start(plugin);
      }
    }
  }

  void register(Plugin plugin) {
    state = {...state, plugin.id: plugin};
    _onChanged?.call();
  }

  void remove(Plugin plugin) {
    state = {...state}..remove(plugin.id);
    _onChanged?.call();
  }

  void changeStatus(String id, PluginStatus status) {
    if (state[id] != null) {
      if (status == PluginStatus.disabled ||
          status == PluginStatus.uninstalled) {
        ref.read(pluginRunManagerProvider.notifier).stop(state[id]!);
      }
      state = {...state, id: state[id]!.copyWith(status: status)};
      _onChanged?.call();
    }
  }

  void updatePermissions(String id, Map<String, List<String>> permissions) {
    if (state[id] != null) {
      state = {...state, id: state[id]!.copyWith(permissions: permissions)};
      _onChanged?.call();
    }
  }

  Future<void> install(Plugin plugin, String packagePath) async {
    final existingPlugin = state[plugin.id];
    if (existingPlugin != null) {
      ref.read(pluginRunManagerProvider.notifier).stop(existingPlugin);
    }

    final installingPlugin = plugin.copyWith(status: PluginStatus.installing);
    state = {...state, plugin.id: installingPlugin};

    try {
      final Directory root = await getApplicationSupportDirectory();
      final Directory target = await Directory(
        path.join(root.path, "plugin", plugin.id),
      ).create(recursive: true);

      final InputFileStream stream = InputFileStream(packagePath);
      final Archive archive = ZipDecoder().decodeStream(stream);

      await extractArchiveToDisk(archive, target.path);

      stream.close();

      final parsed = PluginTomlParser.parseFromDirectory(target);
      if (parsed != null && parsed.id.isNotEmpty) {
        final merged = installingPlugin.copyWith(
          name: parsed.name.isNotEmpty ? parsed.name : installingPlugin.name,
          version: parsed.version,
          author: parsed.author,
          description: parsed.description,
          type: PluginType.values.firstWhere(
            (e) => e.name == parsed.type,
            orElse: () => PluginType.ui,
          ),
          declaredPermissions: parsed.permissions,
          permissions: Map<String, List<String>>.from(parsed.permissions),
          platforms: parsed.platforms,
          autoStart: parsed.autoStart,
        );
        state = {...state, plugin.id: merged};
      }

      changeStatus(plugin.id, PluginStatus.usable);
      await _persistence.save(state.values.toList());

      // Auto-start after install if auto_start is set
      final installed = state[plugin.id];
      if (installed != null &&
          installed.autoStart &&
          installed.status == PluginStatus.usable) {
        await ref.read(pluginRunManagerProvider.notifier).start(installed);
      }
    } catch (e) {
      changeStatus(plugin.id, PluginStatus.disabled);
      rethrow;
    }
  }

  Future<void> uninstall(String pluginId) async {
    final plugin = state[pluginId];
    if (plugin == null) return;

    ref.read(pluginRunManagerProvider.notifier).stop(plugin);
    changeStatus(pluginId, PluginStatus.uninstalled);

    try {
      final root = await getApplicationSupportDirectory();
      final dir = Directory(path.join(root.path, "plugin", pluginId));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('PluginManager: Failed to delete plugin dir: $e');
    }

    state = {...state}..remove(pluginId);
    await _persistence.save(state.values.toList());
  }

  Future<void> persist() async {
    await _persistence.save(state.values.toList());
  }

  void restart(Plugin plugin) {
    ref.read(pluginRunManagerProvider.notifier).stop(plugin);
  }
}

final StateNotifierProvider<PluginManagerNotifier, Map<String, Plugin>>
pluginManagerProvider = StateNotifierProvider(
  (ref) => PluginManagerNotifier(ref),
);
