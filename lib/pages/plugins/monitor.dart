import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/sdk/permission_log.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';

class PermissionMonitor extends ConsumerWidget {
  const PermissionMonitor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(permissionLogServiceProvider);
    final plugins = ref.watch(pluginManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(translateForWidget(ref, I18nKey.pluginsMonitorTitle)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: translateForWidget(ref, I18nKey.pluginsMonitorClearLog),
            onPressed: () => log.clear(),
          ),
        ],
      ),
      body: _PermissionLogList(log: log, plugins: plugins),
    );
  }
}

class _PermissionLogList extends ConsumerWidget {
  final PermissionLogService log;
  final Map<String, dynamic> plugins;

  const _PermissionLogList({required this.log, required this.plugins});

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
        return ListTile(
          leading: Icon(
            entry.granted ? Icons.check_circle : Icons.cancel,
            color: entry.granted ? Colors.green : Colors.red,
          ),
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

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}
