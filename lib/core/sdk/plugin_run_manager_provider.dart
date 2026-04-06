import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:serious_python/serious_python.dart';
import 'package:path/path.dart' as path;
import 'package:freeport/freeport.dart';

class PluginRunManagerNotifier
    extends StateNotifier<Map<int, PluginRunManager>> {
  final Ref ref;
  PluginRunManagerNotifier(this.ref) : super({});

  void start(Plugin plugin) async {
    Directory root = await getApplicationDocumentsDirectory();
    Directory.current = path.join(root.path, "plugin", plugin.id);
    final PluginRunManager runManager = PluginRunManager(
      port: await freePort(),
    );
    state = {...state, runManager.port: runManager};
    SeriousPython.runProgram("__main__.py");
  }
  // 稍等我去翻一下很久之前的代码

  void update() {}

  void destory() {}
}

// 这是运行时管理器，插件管理器另论
// 我一直没弄清什么是runtime (
// 我这里的 runtime 很狭隘，就是指插件进入生命周期后，说人话就是它启动后（
// 启动后的所有操作吗，这里是一个 Provider，提供当前正在生命周期内的插件的 PluginRunManager（就是你之前的 bridge）
// 刚才去看了一下什么是riverpod,清楚了

final StateNotifierProvider<
  PluginRunManagerNotifier,
  Map<int, PluginRunManager>
>
pluginManagerProvider = StateNotifierProvider(
  (ref) => PluginRunManagerNotifier(ref),
);
