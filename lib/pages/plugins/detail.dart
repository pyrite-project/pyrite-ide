import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/sdk/activation_manager.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_config_store.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_metrics.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_resources.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

/// Full plugin detail page reached from the plugin center list.
///
/// The plugin center only discovers and manages; everything that describes a
/// single plugin lives here so the list item no longer opens plugin UI.
class PluginDetailPage extends ConsumerWidget {
  const PluginDetailPage({super.key, required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugin = ref.watch(pluginManagerProvider)[pluginId];
    if (plugin == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: UseText(I18nKey.pluginsDetailMissing)),
      );
    }

    final isRunning = ref.watch(pluginRunManagerProvider)[plugin] != null;
    final activation = ref.watch(activationManagerProvider)[pluginId];
    final manifest = plugin.manifest;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (manifest?.icons case final icons?) ...[
              PluginAssetImage(
                pluginId: plugin.id,
                assetPath: icons.full,
                revision: plugin.version,
                width: 28,
                height: 28,
                fallback: const Icon(Icons.extension_outlined, size: 24),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(child: Text(plugin.name)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Actions(plugin: plugin, isRunning: isRunning),
          const SizedBox(height: 8),
          if (manifest == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: UseText(I18nKey.pluginsDetailManifestInvalid),
                    ),
                  ],
                ),
              ),
            ),
          _MetadataSection(
            plugin: plugin,
            isRunning: isRunning,
            activation: activation,
          ),
          _MetricsSection(pluginId: pluginId),
          _PermissionsSection(plugin: plugin),
          if (manifest != null) _ContributionsSection(pluginId: pluginId),
          if (manifest != null) _ConfigurationSection(pluginId: pluginId),
        ],
      ),
    );
  }
}

class _MetricsSection extends ConsumerWidget {
  const _MetricsSection({required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(pluginMetricsProvider).forPlugin(pluginId);
    return _Section(
      title: const Text('运行诊断'),
      children: [
        if (metrics == null)
          const Text('暂无会话诊断数据')
        else ...[
          _Row(label: const Text('状态'), value: metrics.state),
          _Row(label: const Text('Session'), value: metrics.sessionId),
          _Row(label: const Text('Generation'), value: '${metrics.generation}'),
          _Row(
            label: const Text('激活耗时'),
            value: '${metrics.activationDuration?.inMilliseconds ?? '-'} ms',
          ),
          _Row(
            label: const Text('消息'),
            value:
                '发送 ${metrics.messagesSent} / 接收 ${metrics.messagesReceived}',
          ),
          _Row(
            label: const Text('RPC p50 / p95'),
            value: '${metrics.rpcP50Ms ?? '-'} / ${metrics.rpcP95Ms ?? '-'} ms',
          ),
          _Row(
            label: const Text('队列'),
            value:
                'event ${metrics.eventQueueDepth}/${metrics.eventQueueHighWater}, '
                'control ${metrics.controlQueueDepth}/${metrics.controlQueueHighWater}, '
                'patch ${metrics.patchQueueDepth}/${metrics.patchQueueHighWater}',
          ),
          _Row(
            label: const Text('故障计数'),
            value:
                'timeout ${metrics.timeouts}, cancel ${metrics.cancellations}, '
                'drop ${metrics.drops}, error ${metrics.errors}',
          ),
          if (metrics.lastError != null)
            SelectableText(
              '${metrics.lastError}\n${metrics.lastTraceback ?? ''}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
        ],
      ],
    );
  }
}

String pluginStatusText(WidgetRef ref, PluginStatus status) {
  final key = switch (status) {
    PluginStatus.usable => I18nKey.pluginsStatusUsable,
    PluginStatus.installing => I18nKey.pluginsStatusInstalling,
    PluginStatus.disabled => I18nKey.pluginsStatusDisabled,
    PluginStatus.uninstalled => I18nKey.pluginsStatusUninstalled,
  };
  return translateForWidget(ref, key);
}

String pluginTypeText(WidgetRef ref, PluginType type) {
  final key = switch (type) {
    PluginType.ui => I18nKey.pluginsTypeUi,
    PluginType.service => I18nKey.pluginsTypeService,
    PluginType.data => I18nKey.pluginsTypeData,
  };
  return translateForWidget(ref, key);
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final Widget title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.titleMedium,
              child: title,
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final Widget label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              child: label,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _MetadataSection extends ConsumerWidget {
  const _MetadataSection({
    required this.plugin,
    required this.isRunning,
    required this.activation,
  });

  final Plugin plugin;
  final bool isRunning;
  final ActivationRecord? activation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = activation?.error;
    return _Section(
      title: UseText(I18nKey.pluginsDetailOverview),
      children: [
        _Row(label: UseText(I18nKey.pluginsDetailId), value: plugin.id),
        _Row(
          label: UseText(I18nKey.pluginsDetailVersion),
          value: plugin.version,
        ),
        if (plugin.author.isNotEmpty)
          _Row(
            label: UseText(I18nKey.pluginsDetailAuthor),
            value: plugin.author,
          ),
        _Row(
          label: UseText(I18nKey.pluginsDetailType),
          value: pluginTypeText(ref, plugin.type),
        ),
        _Row(
          label: UseText(I18nKey.pluginsDetailStatus),
          value: pluginStatusText(ref, plugin.status),
        ),
        _Row(
          label: UseText(I18nKey.pluginsDetailRunning),
          value: isRunning
              ? translateForWidget(ref, I18nKey.commonYes)
              : translateForWidget(ref, I18nKey.commonNo),
        ),
        if (activation != null)
          _Row(
            label: UseText(I18nKey.pluginsDetailActivation),
            value: activation!.state.name,
          ),
        if (plugin.description.isNotEmpty)
          _Row(
            label: UseText(I18nKey.pluginsDetailDescription),
            value: plugin.description,
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '$error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _PermissionsSection extends ConsumerWidget {
  const _PermissionsSection({required this.plugin});

  final Plugin plugin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final declared = plugin.declaredPermissions;
    return _Section(
      title: UseText(I18nKey.pluginsDetailPermissions),
      children: [
        if (declared.isEmpty)
          UseText(I18nKey.pluginsDetailPermissionsNone)
        else
          for (final resource in declared.keys.toList()..sort())
            _Row(
              label: Text(resource),
              value: (declared[resource]!.toList()..sort()).join(', '),
            ),
      ],
    );
  }
}

class _ContributionsSection extends ConsumerWidget {
  const _ContributionsSection({required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(contributionRegistryProvider);
    final navigation = registry.navigation.all
        .where((entry) => entry.pluginId == pluginId)
        .toList();
    final views = registry.views.all
        .where((entry) => entry.pluginId == pluginId)
        .toList();
    final commands = registry.commands.all
        .where((entry) => entry.pluginId == pluginId)
        .toList();

    return _Section(
      title: UseText(I18nKey.pluginsDetailContributions),
      children: [
        if (navigation.isEmpty && views.isEmpty && commands.isEmpty)
          UseText(I18nKey.pluginsDetailContributionsNone)
        else ...[
          for (final entry in navigation)
            _Row(
              label: UseText(I18nKey.pluginsDetailNavigation),
              value: '${entry.value.title} (${entry.value.id})',
            ),
          for (final entry in views)
            _Row(
              label: UseText(I18nKey.pluginsDetailViews),
              value: '${entry.value.title} (${entry.value.id})',
            ),
          for (final entry in commands)
            _Row(
              label: UseText(I18nKey.pluginsDetailCommands),
              value: '${entry.value.title} (${entry.value.id})',
            ),
        ],
      ],
    );
  }
}

class _ConfigurationSection extends ConsumerStatefulWidget {
  const _ConfigurationSection({required this.pluginId});

  final String pluginId;

  @override
  ConsumerState<_ConfigurationSection> createState() =>
      _ConfigurationSectionState();
}

class _ConfigurationSectionState extends ConsumerState<_ConfigurationSection> {
  List<Map<String, dynamic>> _items = const [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _ConfigurationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pluginId != widget.pluginId) {
      _reload();
    }
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final items = await ref
          .read(pluginConfigStoreProvider)
          .list(widget.pluginId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loading = false;
      });
    }
  }

  Future<void> _set(String id, Object? value) async {
    await ref.read(pluginConfigStoreProvider).set(widget.pluginId, id, value);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: UseText(I18nKey.pluginsDetailConfiguration),
      children: [
        if (_loading)
          const SizedBox.shrink()
        else if (_items.isEmpty)
          UseText(I18nKey.pluginsDetailConfigurationNone)
        else
          for (final item in _items) _configurationTile(item),
      ],
    );
  }

  Widget _configurationTile(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    final title = item['title']?.toString() ?? id;
    final type = item['type']?.toString() ?? 'string';
    final value = item['value'];
    if (type == 'boolean') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(id, style: Theme.of(context).textTheme.bodySmall),
        value: value == true,
        onChanged: (next) => _set(id, next),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text('$id = $value'),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.plugin, required this.isRunning});

  final Plugin plugin;
  final bool isRunning;

  /// Only UI plugins have a navigation container to open.
  bool get _canOpen =>
      plugin.type == PluginType.ui &&
      plugin.status == PluginStatus.usable &&
      plugin.manifest != null &&
      plugin.manifest!.contributes.navigationContainers.isNotEmpty;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final container = plugin.manifest!.contributes.navigationContainers.first;
    final view = plugin.manifest!.contributes.views
        .where((entry) => entry.container == container.id)
        .firstOrNull;
    await ref
        .read(activationManagerProvider.notifier)
        .activateForView(plugin, view?.id ?? container.id);
    if (!context.mounted) return;
    context.push(
      Uri(
        path: '/plugin-view',
        queryParameters: {
          'plugin': plugin.id,
          'container': container.id,
          if (view != null) 'view': view.id,
        },
      ).toString(),
    );
  }

  /// Enabling revalidates the manifest, so it can fail with a conflict or a
  /// schema error. Surface that instead of dropping it into an async gap.
  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    PluginStatus status,
  ) async {
    try {
      await ref
          .read(pluginManagerProvider.notifier)
          .changeStatus(plugin.id, status);
    } catch (error) {
      if (context.mounted) showIdeError(context, '$error');
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: UseText(I18nKey.pluginsConfirmDeleteTitle),
        content: Text(
          translateForWidget(
            ref,
            I18nKey.pluginsConfirmDeleteMessage,
          ).replaceAll('{name}', plugin.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: UseText(I18nKey.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: UseText(I18nKey.pluginsActionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(pluginManagerProvider.notifier).uninstall(plugin.id);
      if (context.mounted) context.pop();
    } catch (error) {
      if (context.mounted) {
        showIdeError(
          context,
          '${translateForWidget(ref, I18nKey.pluginsUninstallFailed)}: $error',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUsable = plugin.status == PluginStatus.usable;
    final isService = plugin.type == PluginType.service;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_canOpen)
          FilledButton.icon(
            onPressed: () => unawaited(_open(context, ref)),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: UseText(I18nKey.pluginsActionOpen),
          ),
        if (isUsable)
          OutlinedButton.icon(
            onPressed: () =>
                unawaited(_changeStatus(context, ref, PluginStatus.disabled)),
            icon: const Icon(Icons.pause_circle_outline, size: 18),
            label: UseText(I18nKey.pluginsActionDisable),
          ),
        if (plugin.status == PluginStatus.disabled)
          OutlinedButton.icon(
            onPressed: () =>
                unawaited(_changeStatus(context, ref, PluginStatus.usable)),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: UseText(I18nKey.pluginsActionEnable),
          ),
        if (isUsable && isService && !isRunning)
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(pluginRunManagerProvider.notifier).start(plugin),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: UseText(I18nKey.pluginsActionStart),
          ),
        if (isUsable && isService && isRunning)
          OutlinedButton.icon(
            onPressed: () => unawaited(
              ref.read(pluginRunManagerProvider.notifier).stop(plugin),
            ),
            icon: const Icon(Icons.stop, size: 18),
            label: UseText(I18nKey.pluginsActionStop),
          ),
        if (isUsable)
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(pluginManagerProvider.notifier).restart(plugin),
            icon: const Icon(Icons.refresh, size: 18),
            label: UseText(I18nKey.pluginsActionRestart),
          ),
        OutlinedButton.icon(
          onPressed: () => unawaited(_confirmDelete(context, ref)),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: UseText(I18nKey.pluginsActionDelete),
        ),
      ],
    );
  }
}
