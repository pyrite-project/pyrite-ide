import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:serious_python/serious_python.dart';
import 'package:path/path.dart' as path;
import 'package:freeport/freeport.dart';

class PluginRunManagerNotifier
    extends StateNotifier<Map<Plugin, PluginRunManager>> {
  final Ref ref;
  PluginRunManagerNotifier(this.ref) : super({});

  void start(Plugin plugin) async {
    Directory root = await getApplicationDocumentsDirectory();
    Directory.current = path.join(root.path, "plugin", plugin.id);
    final PluginRunManager runManager = PluginRunManager(
      port: await freePort(),
    );
    state = {...state, plugin: runManager};
    SeriousPython.runProgram("__main__.py");
  }

  void update() {}

  void destory() {}
}

// 这是运行时管理器，插件管理器另论

final StateNotifierProvider<
  PluginRunManagerNotifier,
  Map<Plugin, PluginRunManager>
>
pluginRunManagerProvider = StateNotifierProvider(
  (ref) => PluginRunManagerNotifier(ref),
);
