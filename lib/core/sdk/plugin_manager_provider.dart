import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
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
      if (plugin.status != PluginStatus.usable) continue;
      if (plugin.type == PluginType.data) {
        await ref.read(pluginRunManagerProvider.notifier).runOnce(plugin);
      } else if (plugin.autoStart) {
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

  Future<void> changeStatus(String id, PluginStatus status) async {
    if (state[id] != null) {
      if (status == PluginStatus.disabled) {
        unawaited(ref.read(pluginRunManagerProvider.notifier).stop(state[id]!));
        _disableContributions(id);
      } else if (status == PluginStatus.uninstalled) {
        unawaited(ref.read(pluginRunManagerProvider.notifier).stop(state[id]!));
        _removeContributions(id);
      }
      state = {...state, id: state[id]!.copyWith(status: status)};
      if (status == PluginStatus.usable && state[id]!.type == PluginType.data) {
        await ref.read(pluginRunManagerProvider.notifier).runOnce(state[id]!);
      }
      _onChanged?.call();
    }
  }

  void _disableContributions(String pluginId) {
    ref.read(dataContributionsProvider.notifier).state = [
      for (final record in ref.read(dataContributionsProvider))
        if (record.pluginId == pluginId)
          DataContributionRecord(
            pluginId: record.pluginId,
            pluginType: record.pluginType,
            kind: record.kind,
            contributionId: record.contributionId,
            payload: record.payload,
            enabled: false,
          )
        else
          record,
    ];
    ref.read(dataRegistryProvider).removePlugin(pluginId);
  }

  void _removeContributions(String pluginId) {
    ref.read(dataContributionsProvider.notifier).state = [
      for (final record in ref.read(dataContributionsProvider))
        if (record.pluginId != pluginId) record,
    ];
    ref.read(dataRegistryProvider).removePlugin(pluginId);
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
      unawaited(ref.read(pluginRunManagerProvider.notifier).stop(existingPlugin));
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

      await changeStatus(plugin.id, PluginStatus.usable);
      await _persistence.save(state.values.toList());

      final installed = state[plugin.id];
      if (installed != null &&
          installed.status == PluginStatus.usable &&
          installed.type != PluginType.data &&
          installed.autoStart) {
        await ref.read(pluginRunManagerProvider.notifier).start(installed);
      }
    } catch (e) {
      await changeStatus(plugin.id, PluginStatus.disabled);
      rethrow;
    }
  }

  Future<void> uninstall(String pluginId) async {
    final plugin = state[pluginId];
    if (plugin == null) return;

    unawaited(ref.read(pluginRunManagerProvider.notifier).stop(plugin));
    await changeStatus(pluginId, PluginStatus.uninstalled);

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
    unawaited(ref.read(pluginRunManagerProvider.notifier).stop(plugin));
  }
}

final StateNotifierProvider<PluginManagerNotifier, Map<String, Plugin>>
pluginManagerProvider = StateNotifierProvider(
  (ref) => PluginManagerNotifier(ref),
);
