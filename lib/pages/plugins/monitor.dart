import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:pyrite_ide/core/sdk/permission_log.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_metrics.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';

class PermissionMonitor extends ConsumerWidget {
  const PermissionMonitor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(pluginMetricsProvider);
    final runManagers = ref.watch(pluginRunManagerProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(translateForWidget(ref, I18nKey.pluginsMonitorTitle)),
          actions: [
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: translateInContext(
                context,
                I18nKey.pluginsMonitorRestartRuntime,
              ),
              onPressed: () => unawaited(_restartRuntime(context, ref)),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(
                icon: const Icon(Icons.monitor_heart_outlined),
                text: translateInContext(
                  context,
                  I18nKey.pluginsMonitorTabState,
                ),
              ),
              Tab(
                icon: Icon(Icons.subject),
                text: translateInContext(
                  context,
                  I18nKey.pluginsMonitorTabOutput,
                ),
              ),
              Tab(
                icon: Icon(Icons.policy_outlined),
                text: translateInContext(
                  context,
                  I18nKey.pluginsMonitorTabPermissions,
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MetricsTab(metrics: metrics, activeManagers: runManagers.length),
            const _OutputLogTab(),
            const _PermissionLogTab(),
          ],
        ),
      ),
    );
  }

  Future<void> _restartRuntime(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(pluginRunManagerProvider.notifier).restartRuntime();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              translateInContext(context, I18nKey.pluginsMonitorRestarted),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              translateInContextWithReplacements(
                context,
                I18nKey.pluginsMonitorRestartFailed,
                {'error': '$error'},
              ),
            ),
          ),
        );
      }
    }
  }
}

class _MetricsTab extends ConsumerWidget {
  const _MetricsTab({required this.metrics, required this.activeManagers});

  final PluginMetricsRegistry metrics;
  final int activeManagers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(pluginManagerProvider);
    final runManagers = ref.watch(pluginRunManagerProvider);
    final sessions = metrics.sessions.toList()
      ..sort((left, right) => left.pluginId.compareTo(right.pluginId));

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.hub_outlined),
          title: Text(
            'Runtime generation ${metrics.runtimeGeneration}',
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          subtitle: Text(
            translateForWidgetWithReplacements(
              ref,
              I18nKey.pluginsMonitorRestartCount,
              {'count': '${metrics.runtimeRestarts}'},
            ),
          ),
          trailing: Text('$activeManagers active'),
        ),
        const Divider(height: 1),
        Expanded(
          child: sessions.isEmpty
              ? Center(
                  child: Text(
                    translateInContext(
                      context,
                      I18nKey.pluginsMonitorNoSession,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final plugin = plugins[session.pluginId];
                    final manager = plugin == null ? null : runManagers[plugin];
                    return _SessionMetricsCard(
                      session: session,
                      pluginName: plugin?.name ?? session.pluginId,
                      canPing: manager != null,
                      onPing: manager == null
                          ? null
                          : () async {
                              try {
                                final latency = await manager.ping();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${session.pluginId}: ${latency.inMilliseconds} ms',
                                      ),
                                    ),
                                  );
                                }
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        translateInContextWithReplacements(
                                          context,
                                          I18nKey.pluginsMonitorHealthFailed,
                                          {'error': '$error'},
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                      onResume: session.eventDeliveryPaused
                          ? () => ref
                                .read(pluginRunManagerProvider.notifier)
                                .resumeDelivery(session.pluginId)
                          : null,
                      onRestart: plugin == null
                          ? null
                          : () => ref
                                .read(pluginRunManagerProvider.notifier)
                                .restart(plugin),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SessionMetricsCard extends StatelessWidget {
  const _SessionMetricsCard({
    required this.session,
    required this.pluginName,
    required this.canPing,
    required this.onPing,
    required this.onResume,
    required this.onRestart,
  });

  final PluginSessionMetrics session;
  final String pluginName;
  final bool canPing;
  final Future<void> Function()? onPing;
  final VoidCallback? onResume;
  final Future<void> Function()? onRestart;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = switch (session.state) {
      'ready' => Colors.green,
      'failed' => colorScheme.error,
      'stopping' => Colors.orange,
      _ => colorScheme.onSurfaceVariant,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(Icons.extension_outlined, color: statusColor),
        title: Text(pluginName),
        subtitle: Text(
          '${session.state}  session ${_shortId(session.sessionId)}  '
          'generation ${session.generation}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        trailing: session.eventDeliveryPaused
            ? Tooltip(
                message: translateInContext(
                  context,
                  I18nKey.pluginsMonitorDeliveryPaused,
                ),
                child: const Icon(Icons.pause_circle, color: Colors.orange),
              )
            : null,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          _MetricLine(
            label: translateInContext(
              context,
              I18nKey.pluginsMonitorMetricLatency,
            ),
            value:
                '${session.activationDuration?.inMilliseconds ?? '-'} / '
                '${session.rpcP50Ms ?? '-'} / ${session.rpcP95Ms ?? '-'} ms',
          ),
          _MetricLine(
            label: translateInContext(
              context,
              I18nKey.pluginsMonitorMetricTraffic,
            ),
            value:
                '${translateInContextWithReplacements(context, I18nKey.pluginsMonitorMetricMessages, {'sent': '${session.messagesSent}', 'received': '${session.messagesReceived}'})}'
                ', ${_bytes(session.bytesSent)} / ${_bytes(session.bytesReceived)}',
          ),
          _MetricLine(
            label: translateInContext(
              context,
              I18nKey.pluginsMonitorMetricQueueDepth,
            ),
            value:
                'event ${session.eventQueueDepth}/${session.eventQueueHighWater}, '
                'control ${session.controlQueueDepth}/${session.controlQueueHighWater}, '
                'patch ${session.patchQueueDepth}/${session.patchQueueHighWater}',
          ),
          _MetricLine(
            label: translateInContext(
              context,
              I18nKey.pluginsMonitorMetricFaults,
            ),
            value:
                '${session.timeouts} / ${session.cancellations} / '
                '${session.drops} / ${session.errors}',
          ),
          _MetricLine(
            label: 'View patch / resync',
            value: '${session.viewPatches} / ${session.viewResyncs}',
          ),
          _MetricLine(
            label: 'Health',
            value: session.lastHealthAt == null
                ? translateInContext(
                    context,
                    I18nKey.pluginsMonitorHealthUnchecked,
                  )
                : session.healthOk
                ? '${session.lastHealthLatencyMs ?? '-'} ms'
                : translateInContext(
                    context,
                    I18nKey.pluginsMonitorHealthFailedShort,
                  ),
          ),
          if (session.lastError != null)
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                '${session.lastError}\n${session.lastTraceback ?? ''}',
                style: TextStyle(
                  color: colorScheme.error,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              IconButton.filledTonal(
                onPressed: canPing ? () => unawaited(onPing!()) : null,
                tooltip: 'Ping',
                icon: const Icon(Icons.monitor_heart_outlined),
              ),
              if (onResume != null)
                IconButton.filledTonal(
                  onPressed: onResume,
                  tooltip: translateInContext(
                    context,
                    I18nKey.pluginsMonitorResume,
                  ),
                  icon: const Icon(Icons.play_arrow),
                ),
              IconButton.filledTonal(
                onPressed: onRestart == null
                    ? null
                    : () => unawaited(onRestart!()),
                tooltip: translateInContext(
                  context,
                  I18nKey.pluginsMonitorRestart,
                ),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _shortId(String value) =>
      value.length <= 8 ? value : value.substring(0, 8);

  static String _bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

class _OutputLogTab extends ConsumerStatefulWidget {
  const _OutputLogTab();

  @override
  ConsumerState<_OutputLogTab> createState() => _OutputLogTabState();
}

class _OutputLogTabState extends ConsumerState<_OutputLogTab> {
  String? _pluginId;
  String? _sessionId;

  @override
  Widget build(BuildContext context) {
    final allEntries = ref.watch(ideOutputLogProvider);
    final pluginEntries = allEntries
        .where((entry) => entry.source == IdeOutputSource.plugin)
        .toList(growable: false);
    final pluginIds =
        pluginEntries
            .map((entry) => entry.pluginId)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    final sessionIds =
        pluginEntries
            .where((entry) => _pluginId == null || entry.pluginId == _pluginId)
            .map((entry) => entry.sessionId)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    final entries = pluginEntries
        .where(
          (entry) =>
              (_pluginId == null || entry.pluginId == _pluginId) &&
              (_sessionId == null || entry.sessionId == _sessionId),
        )
        .toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: pluginIds.contains(_pluginId)
                      ? _pluginId
                      : null,
                  decoration: const InputDecoration(labelText: 'Plugin'),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: UseText(I18nKey.pluginsMonitorAll),
                    ),
                    for (final id in pluginIds)
                      DropdownMenuItem(value: id, child: Text(id)),
                  ],
                  onChanged: (value) => setState(() {
                    _pluginId = value;
                    _sessionId = null;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: sessionIds.contains(_sessionId)
                      ? _sessionId
                      : null,
                  decoration: const InputDecoration(labelText: 'Session'),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: UseText(I18nKey.pluginsMonitorAll),
                    ),
                    for (final id in sessionIds)
                      DropdownMenuItem(value: id, child: Text(_shortId(id))),
                  ],
                  onChanged: (value) => setState(() => _sessionId = value),
                ),
              ),
              IconButton(
                onPressed: () =>
                    ref.read(ideOutputLogProvider.notifier).clear(),
                tooltip: translateInContext(
                  context,
                  I18nKey.pluginsMonitorClear,
                ),
                icon: const Icon(Icons.delete_sweep),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    translateInContext(context, I18nKey.pluginsMonitorNoOutput),
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[entries.length - 1 - index];
                    return ListTile(
                      dense: true,
                      title: SelectableText(
                        entry.message,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      subtitle: Text(
                        '${entry.pluginId ?? '-'} / '
                        '${entry.sessionId == null ? '-' : _shortId(entry.sessionId!)}',
                      ),
                      trailing: Text(_formatDateTime(entry.time)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static String _shortId(String value) =>
      value.length <= 8 ? value : value.substring(0, 8);
}

class _PermissionLogTab extends ConsumerWidget {
  const _PermissionLogTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(permissionLogServiceProvider);
    final plugins = ref.watch(pluginManagerProvider);
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: translateForWidget(ref, I18nKey.pluginsMonitorClearLog),
            onPressed: log.clear,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _PermissionLogList(log: log, plugins: plugins),
        ),
      ],
    );
  }
}

class _PermissionLogList extends ConsumerWidget {
  const _PermissionLogList({required this.log, required this.plugins});

  final PermissionLogService log;
  final Map<String, dynamic> plugins;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(permissionLogServiceProvider).entries;
    if (entries.isEmpty) {
      return Center(
        child: Text(translateForWidget(ref, I18nKey.pluginsMonitorEmpty)),
      );
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[entries.length - 1 - index];
        final pluginName = plugins[entry.pluginId]?.name ?? entry.pluginId;
        final (icon, color) = switch (entry.decision) {
          PermissionDecision.allowed => (Icons.check_circle, Colors.green),
          PermissionDecision.denied => (Icons.cancel, Colors.red),
          PermissionDecision.unknown => (Icons.help, Colors.orange),
        };
        return ListTile(
          leading: Icon(icon, color: color),
          title: Text(
            entry.command,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          subtitle: Text(
            translateForWidget(
              ref,
              I18nKey.pluginsMonitorRequired,
            ).replaceAll('{resource}', entry.required),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(pluginName, style: const TextStyle(fontSize: 12)),
              Text(
                _formatTime(entry.timestamp),
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(int ms) =>
      _formatDateTime(DateTime.fromMillisecondsSinceEpoch(ms));
}

String _formatDateTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:'
    '${value.second.toString().padLeft(2, '0')}';
