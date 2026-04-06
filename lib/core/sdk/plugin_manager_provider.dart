import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

enum PluginStatus { usable, installing, disusable, uninstall }

class Plugin {
  const Plugin({
    required this.id,
    required this.name,
    this.status = PluginStatus.installing,
    this.permission,
  });
  final String id;
  final String name;
  final PluginStatus status;
  final List? permission;
}

class PluginManagerNotifier extends StateNotifier<List<Plugin>> {
  final Ref ref;

  PluginManagerNotifier(this.ref) : super([]);

  void install(Plugin plugin, String packagePath) async {
    Directory root = await getApplicationDocumentsDirectory();
    Directory target = Directory(path.join(root.path, plugin.id));

    final ByteData data = await rootBundle.load(packagePath);
    final Uint8List bytes = data.buffer.asUint8List();
    final Archive archive = ZipDecoder().decodeBytes(bytes);

    extractArchiveToDisk(archive, target.path);
  }

  void register(Plugin plugin) {
    for (Plugin p in state) {
      if (p.id == plugin.id) return;
    }

    state = [...state, plugin];
  }

  void remove(Plugin plugin) {
    state = state.where((p) => (plugin.id != p.id)).toList();
  }
}
