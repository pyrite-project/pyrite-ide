import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/sdk/utils.dart';
import 'package:pyrite_ide/core/sdk/worksapce/local.dart';
import 'package:pyrite_ide/core/sdk/worksapce/board.dart';
import 'package:pyrite_ide/core/sdk/editor.dart';
import 'package:pyrite_ide/core/sdk/persistence.dart';
import 'package:pyrite_ide/core/sdk/tab.dart';
import 'package:pyrite_ide/core/sdk/settings_api.dart';
import 'package:pyrite_ide/core/sdk/data_api.dart';
import 'package:pyrite_ide/core/sdk/permission_log.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:serious_python/serious_python.dart';
import 'package:path/path.dart' as path;
import 'package:freeport/freeport.dart';

class PluginRunManagerNotifier
    extends StateNotifier<Map<Plugin, PluginRunManager>> {
  final Ref ref;
  bool _routerListenerRegistered = false;

  PluginRunManagerNotifier(this.ref) : super({}) {
    ref.read(permissionLogServiceProvider).load();
  }

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

    final PluginRunManager runManager = PluginRunManager(
      port: port,
      assetsPath: target.path,
      pluginId: plugin.id,
      pluginPermissions: plugin.permissions,
      permissionLog: ref.read(permissionLogServiceProvider),
    );
    runManager.onDataChanged = () {
      state = {...state};
    };
    ref.read(sdkLocalWorkspaceProvider.notifier).bind(runManager);
    ref.read(sdkBoardWorkspaceProvider.notifier).bind(runManager);
    ref.read(sdkEditorProvider.notifier).bind(runManager);
    ref.read(sdkPersistenceProvider.notifier).bind(runManager);
    ref.read(sdkTabProvider.notifier).bind(runManager);
    ref.read(sdkSettingsProvider.notifier).bind(runManager);
    ref.read(sdkDataApiProvider.notifier).bind(runManager);
    state = {...state, plugin: runManager};

    // Fire-and-forget: Python script blocks forever with asyncio.run().
    // On Android sync=false so runProgram returns quickly; on desktop it
    // blocks but the WS server is the important part.
    // ignore: unawaited_futures
    SeriousPython.runProgram(
      path.join(target.path, "__main__.py"),
      script: Platform.isWindows ? "" : null,
      environmentVariables: {
        "PYRITE_IDE_PLUGIN_PORT": "$port",
        "PYTHONUNBUFFERED": "1",
      },
    );

    await runManager.sendLifecycleHook(LifecycleHook.start.value);
  }

  void stop(Plugin plugin) {
    final runManager = state[plugin];
    if (runManager == null) return;
    runManager.sendLifecycleHook(LifecycleHook.dispose.value);
    runManager.stop();
    // Clean up DataRegistry entries for this plugin
    ref.read(dataRegistryProvider).removePlugin(plugin.id);
    state = {...state}..remove(plugin);
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
        final samePlugin = currentPluginId == previousPluginId;
        for (final entry in state.entries) {
          if (entry.key.id == currentPluginId) {
            if (!samePlugin) {
              entry.value.sendLifecycleHook(LifecycleHook.resume.value);
              entry.value.sendPageRefresh();
            }
          } else if (previousPluginId != null &&
              entry.key.id != previousPluginId) {
            entry.value.sendLifecycleHook(LifecycleHook.pause.value);
          }
        }
      }

      if (previousPluginId != null && previousPluginId != currentPluginId) {
        for (final entry in state.entries) {
          if (entry.key.id == previousPluginId) {
            if (entry.key.keepAlive) {
              entry.value.sendLifecycleHook(LifecycleHook.pause.value);
            } else {
              entry.value.sendLifecycleHook(LifecycleHook.dispose.value);
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
    ref.read(permissionLogServiceProvider).dispose();
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
