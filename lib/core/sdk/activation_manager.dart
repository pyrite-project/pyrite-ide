import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';

enum ActivationState {
  installed,
  enabled,
  activating,
  active,
  deactivating,
  failed,
}

class ActivationRecord {
  const ActivationRecord({required this.state, this.reason, this.error});

  final ActivationState state;
  final String? reason;
  final Object? error;
}

/// Serializes activation requests so multiple views/commands share one session.
class ActivationManagerNotifier
    extends StateNotifier<Map<String, ActivationRecord>> {
  ActivationManagerNotifier({
    required Future<bool> Function(Plugin plugin) startPlugin,
    required Future<void> Function(Plugin plugin) stopPlugin,
    Future<void> Function()? stopAll,
  }) : _startPlugin = startPlugin,
       _stopPlugin = stopPlugin,
       _stopAll = stopAll,
       super({});

  final Future<bool> Function(Plugin plugin) _startPlugin;
  final Future<void> Function(Plugin plugin) _stopPlugin;
  final Future<void> Function()? _stopAll;
  final Map<String, Future<bool>> _pending = {};
  final Map<String, Future<void>> _stopping = {};

  ActivationRecord? record(String pluginId) => state[pluginId];

  /// Activates every usable plugin that declares `onView:<viewId>`.
  Future<bool> activateForView(Plugin plugin, String viewId) =>
      activate(plugin, reason: 'onView:$viewId');

  /// Activates the plugins that declare `onCommand:<commandId>`.
  ///
  /// Commands are dispatched by ID without knowing the owning plugin, so this
  /// resolves candidates from their manifests instead of taking a [Plugin].
  Future<List<String>> activateForCommand(
    Iterable<Plugin> plugins,
    String commandId,
  ) => _activateMatching(plugins, 'onCommand:$commandId');

  /// Activates the plugins that declare `onLanguage:<languageId>`.
  Future<List<String>> activateForLanguage(
    Iterable<Plugin> plugins,
    String languageId,
  ) => _activateMatching(plugins, 'onLanguage:$languageId');

  Future<List<String>> _activateMatching(
    Iterable<Plugin> plugins,
    String reason,
  ) async {
    final targets = plugins
        .where(
          (plugin) =>
              plugin.status == PluginStatus.usable &&
              plugin.manifest != null &&
              plugin.manifest!.activationEvents.contains(reason),
        )
        .toList(growable: false);
    final activated = <String>[];
    await Future.wait([
      for (final plugin in targets)
        activate(plugin, reason: reason).then((started) {
          if (started) activated.add(plugin.id);
        }),
    ]);
    return activated;
  }

  Future<bool> activate(Plugin plugin, {required String reason}) {
    if (plugin.manifest == null ||
        !plugin.manifest!.activationEvents.contains(reason)) {
      state = {
        ...state,
        plugin.id: ActivationRecord(
          state: ActivationState.failed,
          reason: reason,
          error: StateError('No matching activation event: $reason'),
        ),
      };
      return Future.value(false);
    }
    final current = state[plugin.id];
    if (current?.state == ActivationState.active) return Future.value(true);
    final pending = _pending[plugin.id];
    if (pending != null) return pending;

    final operation = _activate(plugin, reason: reason);
    _pending[plugin.id] = operation;
    operation.whenComplete(() => _pending.remove(plugin.id));
    return operation;
  }

  Future<bool> _activate(Plugin plugin, {required String reason}) async {
    if (plugin.status != PluginStatus.usable || plugin.manifest == null) {
      state = {
        ...state,
        plugin.id: const ActivationRecord(state: ActivationState.failed),
      };
      return false;
    }
    state = {
      ...state,
      plugin.id: ActivationRecord(
        state: ActivationState.activating,
        reason: reason,
      ),
    };
    try {
      final started = await _startPlugin(plugin);
      final nextState = started
          ? ActivationState.active
          : ActivationState.failed;
      state = {
        ...state,
        plugin.id: ActivationRecord(
          state: nextState,
          reason: reason,
          error: started ? null : StateError('Plugin activation failed'),
        ),
      };
      return started;
    } catch (error) {
      state = {
        ...state,
        plugin.id: ActivationRecord(
          state: ActivationState.failed,
          reason: reason,
          error: error,
        ),
      };
      return false;
    }
  }

  /// Stops [plugin] and clears its runtime state.
  ///
  /// Concurrent callers share one stop operation, so disable-then-uninstall
  /// cannot tear the same session down twice.
  Future<void> deactivate(Plugin plugin) {
    final inFlight = _stopping[plugin.id];
    if (inFlight != null) return inFlight;
    final operation = _deactivate(plugin);
    _stopping[plugin.id] = operation;
    operation.whenComplete(() => _stopping.remove(plugin.id));
    return operation;
  }

  Future<void> _deactivate(Plugin plugin) async {
    // Let a start that is already in flight settle first, otherwise the
    // session it creates would outlive this deactivation.
    final pending = _pending[plugin.id];
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // Activation failures are already recorded by _activate.
      }
    }
    state = {
      ...state,
      plugin.id: const ActivationRecord(state: ActivationState.deactivating),
    };
    try {
      await _stopPlugin(plugin);
      state = {
        ...state,
        plugin.id: ActivationRecord(
          state: plugin.status == PluginStatus.usable
              ? ActivationState.enabled
              : ActivationState.installed,
        ),
      };
    } catch (error) {
      state = {
        ...state,
        plugin.id: ActivationRecord(
          state: ActivationState.failed,
          error: error,
        ),
      };
    }
  }

  /// Waits for in-flight activations and deactivations, then stops everything.
  ///
  /// Called on IDE shutdown so plugins get their dispose hook instead of being
  /// killed mid-activation.
  Future<void> deactivateAllForShutdown() async {
    final inFlight = <Future<void>>[
      ..._pending.values.map((future) => future.catchError((_) => false)),
      ..._stopping.values,
    ];
    if (inFlight.isNotEmpty) await Future.wait(inFlight);
    final stopAll = _stopAll;
    if (stopAll != null) await stopAll();
    state = {
      for (final entry in state.entries)
        entry.key: ActivationRecord(
          state: entry.value.state == ActivationState.failed
              ? ActivationState.failed
              : ActivationState.enabled,
        ),
    };
  }

  Future<void> activateOnStartup(Iterable<Plugin> plugins) async {
    for (final plugin in plugins) {
      if (plugin.status != PluginStatus.usable || plugin.manifest == null) {
        continue;
      }
      state = {
        ...state,
        plugin.id: ActivationRecord(
          state: ActivationState.enabled,
          reason: 'metadata-loaded',
        ),
      };
      if (plugin.type == PluginType.data) {
        await _activate(plugin, reason: 'data-startup');
      } else if (plugin.manifest!.activationEvents.contains('onStartup')) {
        await activate(plugin, reason: 'onStartup');
      }
    }
  }
}

final StateNotifierProvider<
  ActivationManagerNotifier,
  Map<String, ActivationRecord>
>
activationManagerProvider =
    StateNotifierProvider<
      ActivationManagerNotifier,
      Map<String, ActivationRecord>
    >(
      (ref) => ActivationManagerNotifier(
        startPlugin: (plugin) async {
          final manager = ref.read(pluginRunManagerProvider.notifier);
          if (plugin.type == PluginType.data) {
            await manager.runOnce(plugin);
            return true;
          }
          await manager.start(plugin);
          return ref
              .read(pluginRunManagerProvider)
              .keys
              .any((candidate) => candidate.id == plugin.id);
        },
        stopPlugin: ref.read(pluginRunManagerProvider.notifier).stop,
        stopAll: ref.read(pluginRunManagerProvider.notifier).stopAllForShutdown,
      ),
    );
