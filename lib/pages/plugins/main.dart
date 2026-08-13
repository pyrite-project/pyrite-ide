import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/constants/theme_density.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/sdk/activation_manager.dart';
import 'package:pyrite_ide/core/sdk/context_key_host.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_resources.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_icons.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_view_surface.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/plugins.dart';
import 'package:pyrite_ide/pages/plugins/detail.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Plugins extends ConsumerWidget {
  const Plugins({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = ref.watch(themeStyle);
    final tokens = ThemeDensityTokens.forStyle(tier);
    final showPlugins = ref
        .watch(pluginManagerProvider)
        .values
        .where((p) => p.status != PluginStatus.uninstalled)
        .toList();
    final compact = ref.watch(themeStyle) == ThemeStyle.compact;
    return Scaffold(
      appBar: AppBar(
        title: const UseText(I18nKey.pluginsTitle),
        actions: [
          IconButton(
            icon: Icon(Icons.add_box_outlined, size: tokens.headerIconSize),
            tooltip: translateForWidget(ref, I18nKey.pluginsInstall),
            onPressed: () => _installPlugin(context, ref),
          ),
          IconButton(
            icon: Icon(Icons.monitor, size: tokens.headerIconSize),
            tooltip: translateForWidget(ref, I18nKey.pluginsPermissionMonitor),
            onPressed: () => context.push('/plugins/monitor'),
          ),
        ],
      ),
      body: showPlugins.isEmpty
          ? _PluginsEmptyState(onInstall: () => _installPlugin(context, ref))
          : ListView.builder(
              padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
              itemCount: showPlugins.length,
              itemBuilder: (context, index) {
                final plugin = showPlugins[index];
                final isUsable = plugin.status == PluginStatus.usable;

                final statusText = _pluginStatusText(ref, plugin.status);
                final typeText = _pluginTypeText(ref, plugin.type);

                final isUi = plugin.type == PluginType.ui;
                final isService = plugin.type == PluginType.service;
                final isRunning =
                    ref.watch(pluginRunManagerProvider)[plugin] != null;

                return ListTile(
                  visualDensity: compact ? VisualDensity.compact : null,
                  leading: plugin.manifest?.icons == null
                      ? const Icon(Icons.extension_outlined)
                      : PluginAssetImage(
                          pluginId: plugin.id,
                          assetPath: plugin.manifest!.icons!.full,
                          revision: plugin.version,
                          width: compact ? 28 : 36,
                          height: compact ? 28 : 36,
                          fallback: const Icon(Icons.extension_outlined),
                        ),
                  title: Text(plugin.name),
                  subtitle: Text(
                    [
                      if (plugin.author.isNotEmpty) plugin.author,
                      typeText,
                      statusText,
                    ].join(' · '),
                  ),
                  onTap: () => context.push(
                    Uri(
                      path: '/plugins/detail',
                      queryParameters: {'id': plugin.id},
                    ).toString(),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) =>
                        _handleMenuAction(context, ref, plugin, value),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'details',
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 20),
                            SizedBox(width: 8),
                            UseText(I18nKey.pluginsActionDetails),
                          ],
                        ),
                      ),
                      if (isUsable && isUi)
                        PopupMenuItem(
                          value: 'restart',
                          child: Row(
                            children: [
                              Icon(Icons.refresh, size: 20),
                              SizedBox(width: 8),
                              UseText(I18nKey.pluginsActionRestart),
                            ],
                          ),
                        ),
                      if (isUsable && isService && !isRunning)
                        PopupMenuItem(
                          value: 'start',
                          child: Row(
                            children: [
                              Icon(
                                Icons.play_arrow,
                                size: 20,
                                color: Colors.green,
                              ),
                              SizedBox(width: 8),
                              UseText(
                                I18nKey.pluginsActionStart,
                                color: Colors.green,
                              ),
                            ],
                          ),
                        ),
                      if (isUsable && isService && isRunning)
                        PopupMenuItem(
                          value: 'stop',
                          child: Row(
                            children: [
                              Icon(Icons.stop, size: 20, color: Colors.orange),
                              SizedBox(width: 8),
                              UseText(
                                I18nKey.pluginsActionStop,
                                color: Colors.orange,
                                style: TextStyle(color: Colors.orange),
                              ),
                            ],
                          ),
                        ),
                      if (isUsable)
                        PopupMenuItem(
                          value: 'disable',
                          child: Row(
                            children: [
                              Icon(Icons.pause_circle_outline, size: 20),
                              SizedBox(width: 8),
                              UseText(I18nKey.pluginsActionDisable),
                            ],
                          ),
                        ),
                      if (plugin.status == PluginStatus.disabled)
                        PopupMenuItem(
                          value: 'enable',
                          child: Row(
                            children: [
                              Icon(
                                Icons.play_circle_outline,
                                size: 20,
                                color: Colors.green,
                              ),
                              SizedBox(width: 8),
                              UseText(
                                I18nKey.pluginsActionEnable,
                                color: Colors.green,
                              ),
                            ],
                          ),
                        ),
                      if (isUsable)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: Colors.red,
                              ),
                              SizedBox(width: 8),
                              UseText(
                                I18nKey.pluginsActionDelete,
                                color: Colors.red,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _installPlugin(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null || result.files.isEmpty) return;

      final zipPath = result.files.single.path!;
      if (!context.mounted) return;
      showIdeMessage(
        context,
        translateForWidget(ref, I18nKey.pluginsInstalling),
      );
      await ref
          .read(pluginManagerProvider.notifier)
          .install(zipPath); // install 会返回一个bool表示是否为更新插件
      if (context.mounted) {
        showIdeSuccess(
          context,
          translateForWidget(ref, I18nKey.pluginsInstallSuccessfully),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showIdeError(
          context,
          '${translateForWidget(ref, I18nKey.pluginsInstallFailed)}: $e',
        );
      }
    }
  }

  void _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    Plugin plugin,
    String value,
  ) {
    switch (value) {
      case 'details':
        context.push(
          Uri(
            path: '/plugins/detail',
            queryParameters: {'id': plugin.id},
          ).toString(),
        );
        break;
      case 'restart':
        ref.read(pluginManagerProvider.notifier).restart(plugin);
        break;
      case 'start':
        ref.read(pluginRunManagerProvider.notifier).start(plugin);
        break;
      case 'stop':
        unawaited(ref.read(pluginRunManagerProvider.notifier).stop(plugin));
        break;
      case 'disable':
        ref
            .read(pluginManagerProvider.notifier)
            .changeStatus(plugin.id, PluginStatus.disabled);
        break;
      case 'enable':
        ref
            .read(pluginManagerProvider.notifier)
            .changeStatus(plugin.id, PluginStatus.usable);
        break;
      case 'delete':
        _confirmDelete(context, ref, plugin);
        break;
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Plugin plugin) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const UseText(I18nKey.pluginsConfirmDeleteTitle),
        content: Text(
          translateForWidget(
            ref,
            I18nKey.pluginsConfirmDeleteMessage,
          ).replaceAll('{name}', plugin.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const UseText(I18nKey.commonCancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await ref
                    .read(pluginManagerProvider.notifier)
                    .uninstall(plugin.id);
              } catch (error) {
                if (context.mounted) {
                  showIdeError(
                    context,
                    '${translateForWidget(ref, I18nKey.pluginsUninstallFailed)}: $error',
                  );
                }
              }
            },
            child: const UseText(
              I18nKey.pluginsActionDelete,
              color: Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  String _pluginStatusText(WidgetRef ref, PluginStatus status) =>
      pluginStatusText(ref, status);

  String _pluginTypeText(WidgetRef ref, PluginType type) =>
      pluginTypeText(ref, type);
}

class _PluginsEmptyState extends StatelessWidget {
  const _PluginsEmptyState({required this.onInstall});

  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension_outlined, size: 56, color: scheme.primary),
              const SizedBox(height: 18),
              UseText(
                I18nKey.pluginsEmptyTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              UseText(
                I18nKey.pluginsEmptyMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onInstall,
                icon: const Icon(Icons.add_box_outlined),
                label: const UseText(I18nKey.pluginsInstall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PluginViewHost extends ConsumerStatefulWidget {
  const PluginViewHost({
    super.key,
    required this.pluginId,
    required this.containerId,
    this.viewId,
  });

  final String pluginId;
  final String containerId;
  final String? viewId;

  @override
  ConsumerState<PluginViewHost> createState() => _PluginViewHostState();
}

class _PluginViewHostState extends ConsumerState<PluginViewHost> {
  late final PluginEventBus _eventBus;
  String? _selectedViewId;
  String? _activeViewId;

  Map<String, dynamic> _viewPayload(String viewId) => {
    'pluginId': widget.pluginId,
    'containerId': widget.containerId,
    'viewId': viewId,
  };

  @override
  void initState() {
    super.initState();
    _eventBus = ref.read(pluginEventBusProvider);
    _selectedViewId = widget.viewId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _activateSelected());
  }

  @override
  void didUpdateWidget(covariant PluginViewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pluginId != widget.pluginId ||
        oldWidget.containerId != widget.containerId ||
        oldWidget.viewId != widget.viewId) {
      final activeViewId = _activeViewId;
      if (activeViewId != null) {
        _eventBus.emit('view.closed', {
          'pluginId': oldWidget.pluginId,
          'containerId': oldWidget.containerId,
          'viewId': activeViewId,
        });
      }
      _activeViewId = null;
      _selectedViewId = widget.viewId;
      WidgetsBinding.instance.addPostFrameCallback((_) => _activateSelected());
    }
  }

  @override
  void dispose() {
    final activeViewId = _activeViewId;
    if (activeViewId != null) {
      _eventBus.emit('view.closed', _viewPayload(activeViewId));
    }
    super.dispose();
  }

  List<PluginViewContribution> _containerViews() {
    final views = ref
        .read(contributionRegistryProvider)
        .views
        .visible
        .where(
          (entry) =>
              entry.pluginId == widget.pluginId &&
              entry.value.container == widget.containerId,
        )
        .map((entry) => entry.value)
        .toList();
    views.sort((left, right) {
      final order = left.order.compareTo(right.order);
      return order != 0 ? order : left.id.compareTo(right.id);
    });
    return views;
  }

  String? _resolvedViewId([List<PluginViewContribution>? availableViews]) {
    final views = availableViews ?? _containerViews();
    final requested = _selectedViewId ?? widget.viewId;
    if (requested != null && views.any((view) => view.id == requested)) {
      return requested;
    }
    return views.firstOrNull?.id;
  }

  Future<void> _activateSelected() async {
    if (!mounted) return;
    final viewId = _resolvedViewId();
    if (viewId == null || _activeViewId == viewId) return;
    final plugin = ref.read(pluginManagerProvider)[widget.pluginId];
    if (plugin == null) return;
    final previousViewId = _activeViewId;
    if (previousViewId != null) {
      _eventBus.emit('view.closed', _viewPayload(previousViewId));
    }
    _activeViewId = viewId;
    final activated = await ref
        .read(activationManagerProvider.notifier)
        .activateForView(plugin, viewId);
    if (!mounted || _activeViewId != viewId) return;
    if (!activated) {
      _activeViewId = null;
      return;
    }
    // Emit view.opened only after activation completes. A cold-started plugin
    // subscribes during its on_start hook, which the activation await waits for;
    // emitting earlier (view.opened is a non-replay topic) means the owning
    // plugin never sees the open and never sends its first snapshot, leaving the
    // surface stuck on the loading indicator.
    _eventBus.emit('view.opened', _viewPayload(viewId));
    _eventBus.emit('view.focused', _viewPayload(viewId));
    ref.read(contextKeyHostProvider).setActiveView(viewId);
  }

  void _selectView(String viewId) {
    if (_resolvedViewId() == viewId) return;
    setState(() => _selectedViewId = viewId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _activateSelected());
  }

  @override
  Widget build(BuildContext context) {
    final container = ref
        .watch(contributionRegistryProvider)
        .navigation
        .visible
        .where(
          (entry) =>
              entry.pluginId == widget.pluginId &&
              entry.value.id == widget.containerId,
        )
        .firstOrNull;
    if (container == null) {
      return const Scaffold(body: Center(child: Text('插件视图不可用')));
    }
    final plugin = ref.watch(pluginManagerProvider)[widget.pluginId];
    if (plugin == null) {
      return const Scaffold(body: Center(child: Text('插件视图不可用')));
    }
    final views = ref
        .watch(contributionRegistryProvider)
        .views
        .visible
        .where(
          (entry) =>
              entry.pluginId == widget.pluginId &&
              entry.value.container == widget.containerId,
        )
        .map((entry) => entry.value)
        .toList();
    views.sort((left, right) {
      final order = left.order.compareTo(right.order);
      return order != 0 ? order : left.id.compareTo(right.id);
    });
    final targetView = _resolvedViewId(views);
    if (targetView == null) {
      return const Scaffold(body: Center(child: Text('插件视图不可用')));
    }
    if (_activeViewId != targetView) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _activateSelected());
    }
    final activation = ref.watch(activationManagerProvider)[widget.pluginId];
    if (activation == null ||
        activation.state == ActivationState.enabled ||
        activation.state == ActivationState.activating) {
      return const Center(child: CircularProgressIndicator());
    }
    if (activation.state == ActivationState.failed) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('插件启动失败'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _activateSelected,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(selectedPluginId) != widget.pluginId) {
        ref.read(selectedPluginId.notifier).state = widget.pluginId;
      }
      if (ref.read(page) != targetView) {
        ref.read(page.notifier).state = targetView;
      }
    });

    // Resolve the renderer from the view contribution. Views are matched by
    // their fully-qualified id, falling back to the container's first view so a
    // container-level route still lands somewhere sensible.
    final view = views.where((entry) => entry.id == targetView).firstOrNull;
    if (view == null) {
      return const Scaffold(body: Center(child: Text('插件视图不可用')));
    }

    final manager = ref
        .watch(pluginRunManagerProvider)
        .entries
        .where((entry) => entry.key.id == widget.pluginId)
        .map((entry) => entry.value)
        .firstOrNull;
    if (manager == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedIndex = views.indexWhere((entry) => entry.id == targetView);
    final activeIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final pluginVersion = ref.watch(
      pluginManagerProvider.select(
        (plugins) => plugins[widget.pluginId]?.version,
      ),
    );
    final surfaces = [
      for (var index = 0; index < views.length; index++)
        _buildSurface(manager, views[index], visible: index == activeIndex),
    ];
    if (views.length == 1) return Scaffold(body: surfaces.single);

    return Scaffold(
      body: DefaultTabController(
        // This key must remain stable while only the selected view changes.
        // Otherwise Flutter disposes the whole subtree (and each surface's
        // TextEditingController) on every tab switch.
        key: ValueKey('${widget.pluginId}:${widget.containerId}'),
        length: views.length,
        initialIndex: activeIndex,
        child: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: SizedBox(
                height: 38,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerHeight: 1,
                  labelStyle: Theme.of(context).textTheme.labelMedium,
                  onTap: (index) => _selectView(views[index].id),
                  tabs: [
                    for (final entry in views)
                      _viewTab(entry, revision: pluginVersion),
                  ],
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(index: activeIndex, children: surfaces),
            ),
          ],
        ),
      ),
    );
  }

  PluginViewSurface _buildSurface(
    PluginRunManager manager,
    PluginViewContribution view, {
    required bool visible,
  }) => PluginViewSurface(
    key: ValueKey('plugin-view:${view.id}'),
    instance: ViewInstanceId(
      pluginId: widget.pluginId,
      sessionId: manager.sessionId,
      viewId: view.id,
      // The sidebar placement is one instance per container; a tab host passes
      // its own instanceId so the same view can be open in both at once.
      instanceId: 'container:${widget.containerId}',
    ),
    renderer: view.renderer,
    title: view.title,
    visible: visible,
  );

  Widget _viewTab(PluginViewContribution view, {required Object? revision}) {
    final icon = view.icon;
    Widget? iconWidget;
    if (icon?.kind == PluginIconKind.material) {
      iconWidget = Icon(pluginIcon('material:${icon!.value}'), size: 16);
    } else if (icon?.kind == PluginIconKind.asset) {
      iconWidget = PluginAssetImage(
        pluginId: widget.pluginId,
        assetPath: icon!.value,
        revision: revision,
        width: 16,
        height: 16,
        monochrome: true,
        fallback: const Icon(Icons.extension_outlined, size: 16),
      );
    }
    return Tab(
      height: 38,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconWidget != null) ...[iconWidget, const SizedBox(width: 6)],
          Text(view.title),
        ],
      ),
    );
  }
}
