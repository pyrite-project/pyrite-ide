import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/sdk/utils.dart';
import 'package:serious_python/serious_python.dart';
import 'package:path/path.dart' as path;
import 'package:freeport/freeport.dart';

class PluginRunManagerNotifier
    extends StateNotifier<Map<Plugin, PluginRunManager>> {
  final Ref ref;
  PluginRunManagerNotifier(this.ref) : super({});

  Future<void> start(Plugin plugin) async {
    for (var entery in state.entries) {
      if (entery.key.id == plugin.id) {
        return;
      }
    }
    /*
    state.forEach((key, value) {
      if (key.id == plugin.id) {
        // state[plugin]!.sendLifecycleHooks(LifecycleHooks.onResume);
        return;
      }
    });
    */
    print("RUN START");

    final Directory root = await getApplicationSupportDirectory();
    final Directory target = await Directory(
      path.join(root.path, "plugin", plugin.id),
    ).create(recursive: true);

    Directory.current = target.path;
    final int port = await freePort();
    final String runtimeModulePaths = [
      path.join(target.path, "__pypackages__"),
      path.join(target.path, "site-packages"),
    ].map(escapeForPythonString).join("::");
    await SeriousPython.run(
      "assets/python_runtime_boot.zip",
      appFileName: "setup_sys_path.py",
      environmentVariables: {
        "RUNTIME_MODULE_PATHS": runtimeModulePaths,
        "RUNTIME_REPLACE_MODULE_PATHS": "1",
      },
    );
    SeriousPython.runProgram(
      path.join(target.path, "__main__.py"),
      script: Platform.isWindows ? "" : null,
      environmentVariables: {"PYRITE_IDE_PLUGIN_PORT": "$port"},
    );

    final PluginRunManager runManager = PluginRunManager(port: port, assetsPath: target.path);
    runManager.onRefresh = () {
      state = {...state};
    };
    runManager.onSetVar = () {
      state = {...state};
    };
    state = {...state, plugin: runManager};
    await runManager.sendLifecycleHooks(LifecycleHooks.onStart);
    print("STATE $state");
  }

  void update() {}

  void destory() {}

  void setupRouterListener() {
    String? previousLocation;
    Uri? previousUri;
    routes.routerDelegate.addListener(() {
      final currentLocation = routes.state.fullPath;
      final currentUri = routes.state.uri;
      if (previousLocation != currentLocation) {
        print('路由从 $previousLocation 变为 $currentLocation');
        if (currentLocation == "/plugins/body") {
          final String pluginId = currentUri.queryParameters['id']!;
          if (state.isEmpty) {
            // sendLifecycleHooks(LifecycleHooks.onStart);
            print(LifecycleHooks.onStart);
          }
          state.forEach((key, value) {
            if (key.id == pluginId) {
              value.sendLifecycleHooks(LifecycleHooks.onResume);
              print(LifecycleHooks.onResume.toString());
            } else {
              // 调用 sendLifecycleHooks 需要拿到对应的 value，此时插件尚未初始化，不存在这个对应的 value。故将发送生命周期的逻辑交给 value.start()。value.start() 由 _loadRemoteWidgets 调用。_loadRemoteWidgets 由 _PluginBodyState 的 initState 调用。
              // sendLifecycleHooks(LifecycleHooks.onStart);
              print(LifecycleHooks.onStart);
            }
          });
        } else if (previousLocation == "/plugins/body") {
          final String pluginId = previousUri!.queryParameters['id']!;
          state.forEach((key, value) {
            if (key.id == pluginId) {
              if (key.keepAlive) {
                value.sendLifecycleHooks(LifecycleHooks.onPause);
                print(LifecycleHooks.onPause.toString());
              } else {
                value.sendLifecycleHooks(LifecycleHooks.onDispose);
                print(LifecycleHooks.onDispose.toString());
              }
            }
          });
        }
        previousLocation = currentLocation;
        previousUri = currentUri;
      }
    });
  }
}

final StateNotifierProvider<
  PluginRunManagerNotifier,
  Map<Plugin, PluginRunManager>
>
pluginRunManagerProvider = StateNotifierProvider(
  (ref) => PluginRunManagerNotifier(ref),
);

