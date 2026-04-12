import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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

  Plugin copyWith({
    String? id,
    String? name,
    PluginStatus? status,
    List? permissions,
  }) {
    return Plugin(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      permissions: permissions ?? this.permissions,
    );
  }
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

  void changeStatus(String id, PluginStatus status) {
    if (state[id] != null) {
      state = {...state, id: state[id]!.copyWith(status: status)};
    }
  }

  Future<void> install(Plugin plugin, String packagePath) async {
    register(plugin);

    Directory root = await getApplicationSupportDirectory();
    print(root);
    Directory target = await Directory(
      path.join(root.path, "plugin", plugin.id),
    ).create(recursive: true);

    final InputFileStream stream = InputFileStream(packagePath);
    final Archive archive = ZipDecoder().decodeStream(stream);

    await extractArchiveToDisk(archive, target.path);
    changeStatus(plugin.id, PluginStatus.usable);
  }
}

final StateNotifierProvider<PluginManagerNotifier, Map<String, Plugin>>
pluginManagerProvider = StateNotifierProvider(
  (ref) => PluginManagerNotifier(ref),
);
