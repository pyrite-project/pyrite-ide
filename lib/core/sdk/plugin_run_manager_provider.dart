import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_metrics.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/python_runtime_host.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/sdk/api/file.dart';
import 'package:pyrite_ide/core/sdk/api/board.dart';
import 'package:pyrite_ide/core/sdk/api/editor.dart';
import 'package:pyrite_ide/core/sdk/api/persistence.dart';
import 'package:pyrite_ide/core/sdk/api/tab.dart';
import 'package:pyrite_ide/core/sdk/api/settings_api.dart';
import 'package:pyrite_ide/core/sdk/api/data_api.dart';
import 'package:pyrite_ide/core/sdk/api/message_api.dart';
import 'package:pyrite_ide/core/sdk/api/clipboard_api.dart';
import 'package:pyrite_ide/core/sdk/api/serial.dart';
import 'package:pyrite_ide/core/sdk/api/dialog.dart';
import 'package:pyrite_ide/core/sdk/api/events_api.dart';
import 'package:pyrite_ide/core/sdk/api/document_api.dart';
import 'package:pyrite_ide/core/sdk/api/runtime_api.dart';
import 'package:pyrite_ide/core/sdk/api/env_api.dart';
import 'package:pyrite_ide/core/sdk/api/view_api.dart';
import 'package:pyrite_ide/core/sdk/api/configuration_api.dart';
import 'package:pyrite_ide/core/sdk/component_method_registry.dart';
import 'package:pyrite_ide/core/sdk/context_key_host.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus_provider.dart';
import 'package:pyrite_ide/core/sdk/view_model_store_provider.dart';
import 'package:pyrite_ide/core/sdk/permission_log.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';

class PluginRunManagerNotifier
    extends StateNotifier<Map<Plugin, PluginRunManager>> {
  final Ref ref;
  final PermissionLogService _permissionLog;
  final PythonRuntimeHost _runtimeHost;
  PluginRunManagerNotifier(this.ref, {PythonRuntimeHost? runtimeHost})
    : _permissionLog = ref.read(permissionLogServiceProvider),
      _runtimeHost = runtimeHost ?? ref.read(pythonRuntimeHostProvider),
      super({}) {
    _permissionLog.load();
  }

  bool isRunning(String pluginId) =>
      state.keys.any((plugin) => plugin.id == pluginId);

  Future<void> start(Plugin plugin) async {
    if (!_canRun(plugin)) return;
    if (state.keys.any((candidate) => candidate.id == plugin.id)) return;
    if (plugin.type == PluginType.data) {
      await runOnce(plugin);
      return;
    }
    final outputLog = ref.read(ideOutputLogProvider.notifier);
    final metricsRegistry = ref.read(pluginMetricsProvider);
    final backoff = metricsRegistry.restartBackoffRemaining(plugin.id);
    if (backoff != null) {
      outputLog.add(
        IdeOutputSource.plugin,
        '[${plugin.id}] restart delayed for ${backoff.inMilliseconds} ms',
        pluginId: plugin.id,
      );
      return;
    }
    PluginRunManager? liveManager;
    try {
      final session = await _runtimeHost.startPlugin(
        plugin,
        permissionLog: _permissionLog,
        onOutput: (message) => outputLog.add(
          IdeOutputSource.plugin,
          message,
          pluginId: plugin.id,
          sessionId: liveManager?.sessionId,
        ),
        configureManager: (manager) {
          liveManager = manager;
          _bindManager(manager, dataOnly: false);
        },
        onStopped: () => _removeRuntimeState(plugin.id),
      );
      final manager = session.manager;
      manager.onDataChanged = () {
        if (state.values.contains(manager)) state = {...state};
      };
      state = {
        for (final entry in state.entries)
          if (entry.key.id != plugin.id) entry.key: entry.value,
        plugin: manager,
      };
      metricsRegistry.markActivated(plugin.id);
      metricsRegistry.noteRestartSuccess(plugin.id);
    } catch (error, stack) {
      if (error is PluginStartCancelledException) return;
      liveManager?.metrics?.markFailed(error, traceback: '$stack');
      metricsRegistry.noteRestartFailure(plugin.id);
      outputLog.add(
        IdeOutputSource.plugin,
        '[${plugin.id}] failed to start: $error\n$stack',
        pluginId: plugin.id,
        sessionId: liveManager?.sessionId,
      );
    }
  }

  Future<void> stop(Plugin plugin) async {
    final manager =
        state[state.keys.firstWhere(
          (candidate) => candidate.id == plugin.id,
          orElse: () => plugin,
        )];
    manager?.metrics?.markStopping();
    await _runtimeHost.stopPlugin(plugin.id);
    final stopTimedOut =
        _runtimeHost.sessions[plugin.id]?.programExited == false;
    ref
        .read(pluginMetricsProvider)
        .endSession(plugin.id, timedOut: stopTimedOut);
    if (manager != null) {
      ref
          .read(pluginEventBusProvider)
          .clearSession(plugin.id, manager.sessionId);
      ref
          .read(viewModelStoreProvider)
          .clearSession(plugin.id, manager.sessionId);
      ref
          .read(componentMethodRegistryProvider)
          .clearSession(plugin.id, manager.sessionId);
    } else {
      ref.read(pluginEventBusProvider).clearPlugin(plugin.id);
      ref.read(viewModelStoreProvider).clearPlugin(plugin.id);
      ref.read(componentMethodRegistryProvider).clearPlugin(plugin.id);
    }
    state = {
      for (final entry in state.entries)
        if (entry.key.id != plugin.id) entry.key: entry.value,
    };
  }

  Future<void> runOnce(Plugin plugin) async {
    if (!_canRun(plugin) || plugin.type != PluginType.data) return;
    final outputLog = ref.read(ideOutputLogProvider.notifier);
    final metricsRegistry = ref.read(pluginMetricsProvider);
    final backoff = metricsRegistry.restartBackoffRemaining(plugin.id);
    if (backoff != null) return;
    PluginRunManager? liveManager;
    try {
      await _runtimeHost.runPluginOnce(
        plugin,
        permissionLog: _permissionLog,
        onOutput: (message) => outputLog.add(
          IdeOutputSource.plugin,
          message,
          pluginId: plugin.id,
          sessionId: liveManager?.sessionId,
        ),
        configureManager: (manager) {
          liveManager = manager;
          _bindManager(manager, dataOnly: true);
        },
        // DataPlugin contributions are persistent data, not runtime state.
        onStopped: () =>
            _removeRuntimeState(plugin.id, removeDataContributions: false),
      );
      metricsRegistry.markActivated(plugin.id);
      metricsRegistry.endSession(plugin.id);
      metricsRegistry.noteRestartSuccess(plugin.id);
    } catch (error, stack) {
      if (error is PluginStartCancelledException) return;
      liveManager?.metrics?.markFailed(error, traceback: '$stack');
      metricsRegistry.noteRestartFailure(plugin.id);
      outputLog.add(
        IdeOutputSource.plugin,
        '[${plugin.id}] once-run failed: $error\n$stack',
        pluginId: plugin.id,
        sessionId: liveManager?.sessionId,
      );
    }
  }

  Future<void> restart(Plugin plugin) async {
    await stop(plugin);
    await start(plugin);
  }

  bool _canRun(Plugin plugin) {
    final manifest = plugin.manifest;
    if (plugin.status != PluginStatus.usable || manifest == null) return false;
    try {
      PluginManifestValidator().validate(manifest);
      return true;
    } on PluginManifestException {
      return false;
    }
  }

  Future<void> restartRuntime() async {
    final plugins = ref.read(pluginManagerProvider);
    final restoreIds = <String>{
      ..._visiblePluginIds(),
      for (final plugin in plugins.values)
        if (plugin.type == PluginType.service &&
            plugin.manifest?.autoStart == true)
          plugin.id,
    };
    for (final manager in state.values) {
      manager.metrics?.markStopping();
    }
    await _runtimeHost.restartRuntime();
    ref.read(pluginEventBusProvider)
      ..disposeAll()
      ..clearRetained();
    ref.read(viewModelStoreProvider).clear();
    ref.read(componentMethodRegistryProvider).clear();
    state = {};
    ref
        .read(pluginMetricsProvider)
        .recordRuntimeRestart(_runtimeHost.generation);
    for (final pluginId in restoreIds) {
      final plugin = plugins[pluginId];
      if (plugin != null) await start(plugin);
    }
  }

  void _bindManager(PluginRunManager manager, {required bool dataOnly}) {
    manager.metrics = ref
        .read(pluginMetricsProvider)
        .beginSession(
          pluginId: manager.pluginId,
          sessionId: manager.sessionId,
          generation: manager.generation,
        );
    if (!dataOnly) {
      ref.read(sdkFileProvider).bind(manager);
      ref.read(sdkBoardProvider).bind(manager);
      ref.read(sdkEditorProvider).bind(manager);
      ref.read(sdkPersistenceProvider).bind(manager);
      ref.read(sdkTabProvider).bind(manager);
      ref.read(sdkSerialProvider).bind(manager);
    }
    ref.read(sdkSettingsProvider).bind(manager);
    ref.read(sdkDataApiProvider).bind(manager);
    ref.read(sdkMessageApiProvider).bind(manager);
    ref.read(sdkClipboardApiProvider).bind(manager);
    ref.read(sdkDialogProvider).bind(manager);
    ref.read(sdkEventsProvider).bind(manager);
    if (!dataOnly) {
      ref.read(sdkEditorDocumentProvider).bind(manager);
      // Reading the host starts its tab listener so editor.document.* events
      // begin flowing once any UI/service plugin is running.
      ref.read(documentHostProvider);
      ref.read(sdkRuntimeProvider).bind(manager);
      // Reading the host starts its serial listener so runtime.* lifecycle
      // events begin flowing.
      ref.read(runtimeHostProvider);
      ref.read(sdkViewProvider).bind(manager);
    }
    // Every plugin type may ask about the platform and layout mode.
    ref.read(sdkEnvProvider).bind(manager);
    ref.read(sdkConfigurationProvider).bind(manager);
    // Start context-key producers so Manifest when expressions stay live.
    ref.read(contextKeyHostProvider);
  }

  void _removeRuntimeState(
    String pluginId, {
    bool removeDataContributions = true,
  }) {
    final runtimeSession = _runtimeHost.sessions[pluginId];
    final metrics = ref.read(pluginMetricsProvider).forPlugin(pluginId);
    if (runtimeSession?.state == PluginSessionState.failed) {
      metrics?.markFailed('Plugin process exited unexpectedly');
      ref.read(pluginMetricsProvider).noteRestartFailure(pluginId);
    } else if (metrics?.state != 'stopped') {
      metrics?.markStopped();
    }
    if (removeDataContributions) {
      ref.read(dataRegistryProvider).removePlugin(pluginId);
    }
    ref.read(pluginEventBusProvider).clearPlugin(pluginId);
    ref.read(viewModelStoreProvider).clearPlugin(pluginId);
    ref.read(componentMethodRegistryProvider).clearPlugin(pluginId);
    state = {
      for (final entry in state.entries)
        if (entry.key.id != pluginId) entry.key: entry.value,
    };
  }

  Set<String> _visiblePluginIds() {
    final uri = routes.state.uri;
    if (uri.path == '/plugin-view') {
      final id = uri.queryParameters['plugin'];
      return id == null || id.isEmpty ? const {} : {id};
    }
    return const {};
  }

  void resumeDelivery(String pluginId) {
    ref.read(pluginMetricsProvider).forPlugin(pluginId)?.resumeEventDelivery();
    PluginRunManager? manager;
    for (final entry in state.entries) {
      if (entry.key.id == pluginId) {
        manager = entry.value;
        break;
      }
    }
    if (manager == null) return;
    final store = ref.read(viewModelStoreProvider);
    for (final instance in store.instancesForPlugin(pluginId)) {
      if (instance.sessionId != manager.sessionId) continue;
      manager.sendViewFrame(IdeCommands.viewResync, {
        'instance': instance.toJson(),
        'revision': store.model(instance)?.revision,
      });
      manager.metrics?.recordViewResync();
    }
  }

  Future<void> stopAllForShutdown() async {
    await _runtimeHost.stopAll();
    ref.read(pluginEventBusProvider).disposeAll();
    ref.read(viewModelStoreProvider).clear();
    ref.read(componentMethodRegistryProvider).clear();
    state = {};
  }

  @override
  void dispose() {
    unawaited(_runtimeHost.stopAll());
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
