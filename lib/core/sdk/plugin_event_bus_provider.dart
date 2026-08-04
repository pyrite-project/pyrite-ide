import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus.dart';
import 'package:pyrite_ide/core/sdk/plugin_metrics.dart';
import 'package:pyrite_ide/core/sdk/plugin_perf_budget.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';

/// Host-wide event bus, shared across all plugin sessions.
///
/// Delivery routes each event to the run manager that owns the target
/// plugin/session, and only when that manager's session and generation still
/// match — so events from a stopped or restarted session are never delivered to
/// a newer one.
final Provider<PluginEventBus> pluginEventBusProvider = Provider((ref) {
  final metrics = ref.read(pluginMetricsProvider);
  final bus = PluginEventBus(
    deliver: (pluginId, sessionId, generation, event) {
      final managers = ref.read(pluginRunManagerProvider);
      for (final entry in managers.entries) {
        final manager = entry.value;
        if (entry.key.id != pluginId ||
            manager.sessionId != sessionId ||
            manager.generation != generation) {
          continue;
        }
        manager.sendEvent(
          subscriptionId: event.subscriptionId,
          topic: event.topic,
          payloads: event.payloads,
        );
        return;
      }
    },
    isDeliveryPaused: (pluginId) =>
        metrics.forPlugin(pluginId)?.eventDeliveryPaused == true,
    onQueueDepth: (pluginId, depth) {
      final session = metrics.forPlugin(pluginId);
      if (session == null) return;
      session.recordEventQueueDepth(depth);
      if (depth >= PluginPerfBudget.eventQueueHighWater) {
        session.recordDrop();
      }
    },
  );
  ref.onDispose(bus.disposeAll);
  return bus;
});
