import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';

class PluginManagerNotifier extends StateNotifier<Map<String, Plugin>> {
  final Ref ref;

  PluginManagerNotifier(this.ref) : super({});

  void register(Plugin plugin) {
    if (state.containsKey(plugin.id)) return;
    state = {...state, plugin.id: plugin};
  }

  void remove(Plugin plugin) {
    state = {...state}..remove(plugin.id);
  }

  void changeStatus(String id, PluginStatus status) {
    if (state[id] != null) {
      state = {...state, id: state[id]!.copyWith(status: status)};
    }
  }

  Future<void> install(Plugin plugin, String packagePath) async {
    register(plugin);

    try {
      final Directory root = await getApplicationSupportDirectory();
      final Directory target = await Directory(
        path.join(root.path, "plugin", plugin.id),
      ).create(recursive: true);

      final InputFileStream stream = InputFileStream(packagePath);
      final Archive archive = ZipDecoder().decodeStream(stream);

      await extractArchiveToDisk(archive, target.path);
      changeStatus(plugin.id, PluginStatus.usable);
    } catch (e) {
      changeStatus(plugin.id, PluginStatus.disabled);
      rethrow;
    }
  }
}

final StateNotifierProvider<PluginManagerNotifier, Map<String, Plugin>>
pluginManagerProvider = StateNotifierProvider(
  (ref) => PluginManagerNotifier(ref),
);
