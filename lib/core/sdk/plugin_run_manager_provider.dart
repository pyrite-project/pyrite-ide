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

  Future<void> start(Plugin plugin) async {
    print("RUN START");
    Directory root = await getApplicationSupportDirectory();
    Directory target = await Directory(path.join(root.path, "plugin", plugin.id)).create(recursive: true);
    Directory.current = target.path;
    final PluginRunManager runManager = PluginRunManager(
      port: 8765,
    );
    state = {...state, plugin: runManager};
    print("STATE $state");
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
