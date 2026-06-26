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
  bool _routerListenerRegistered = false;

  PluginRunManagerNotifier(this.ref) : super({});

  Future<void> start(Plugin plugin) async {
    if (state.containsKey(plugin)) return;

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

    await SeriousPython.runProgram(
      path.join(target.path, "__main__.py"),
      script: Platform.isWindows ? "" : null,
      environmentVariables: {"PYRITE_IDE_PLUGIN_PORT": "$port"},
    );

    final PluginRunManager runManager = PluginRunManager(
      port: port,
      assetsPath: target.path,
    );
    runManager.onDataChanged = () {
      state = {...state};
    };
    state = {...state, plugin: runManager};
    await runManager.sendLifecycleHooks(LifecycleHooks.onStart.value);
  }

  void setupRouterListener() {
    if (_routerListenerRegistered) return;
    _routerListenerRegistered = true;

    String? previousLocation;
    String? previousPluginId;

    routes.routerDelegate.addListener(() {
      final currentLocation = routes.state.fullPath;
      if (previousLocation == currentLocation) return;

      String? currentPluginId;
      if (currentLocation == "/plugins/body") {
        currentPluginId = routes.state.uri.queryParameters['id'];
      }

      if (currentPluginId != null) {
        for (final entry in state.entries) {
          if (entry.key.id == currentPluginId) {
            entry.value.sendLifecycleHooks(LifecycleHooks.onResume.value);
          } else if (previousPluginId != null &&
              entry.key.id != previousPluginId) {
            entry.value.sendLifecycleHooks(LifecycleHooks.onPause.value);
          }
        }
      }

      if (previousPluginId != null && previousPluginId != currentPluginId) {
        for (final entry in state.entries) {
          if (entry.key.id == previousPluginId) {
            if (entry.key.keepAlive) {
              entry.value.sendLifecycleHooks(LifecycleHooks.onPause.value);
            } else {
              entry.value.sendLifecycleHooks(LifecycleHooks.onDispose.value);
            }
          }
        }
      }

      previousLocation = currentLocation;
      previousPluginId = currentPluginId;
    });
  }

  @override
  void dispose() {
    for (final runManager in state.values) {
      runManager.dispose();
    }
    super.dispose();
  }
}

final StateNotifierProvider<
  PluginRunManagerNotifier,
  Map<Plugin, PluginRunManager>
>
pluginRunManagerProvider = StateNotifierProvider(
  (ref) => PluginRunManagerNotifier(ref),
);
