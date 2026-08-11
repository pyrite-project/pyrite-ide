import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/api/view_api.dart';
import 'package:pyrite_ide/core/sdk/command_service.dart';
import 'package:pyrite_ide/core/sdk/component_method_registry.dart';
import 'package:pyrite_ide/core/sdk/component_schema.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/menu_resolver.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/core/sdk/view_model_store_provider.dart';
import 'package:pyrite_ide/features/plugin_view/component_builder.dart';
import 'package:pyrite_ide/features/plugin_view/component_error_boundary.dart';
import 'package:pyrite_ide/features/plugin_view/component_host_state.dart';
import 'package:pyrite_ide/features/plugin_view/native_view_registry.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_icons.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_menu.dart';

/// Renders one plugin view instance.
///
/// This is the single surface for native plugin views: the sidebar host and a
/// tab host both mount this same widget, differing only in the
/// [ViewInstanceId] they pass. Keeping one implementation is what stops the two
/// placements from drifting apart in capability.
///
/// Owns the host-local state for its instance (input buffers, focus, tree
/// expansion) and subscribes to just its own model, so a patch to a sibling view
/// never rebuilds this one.
class PluginViewSurface extends ConsumerStatefulWidget {
  const PluginViewSurface({
    super.key,
    required this.instance,
    required this.renderer,
    this.title,
    this.visible = true,
    this.viewProps = const {},
  });

  final ViewInstanceId instance;

  /// Renderer token from the view contribution, e.g. `native.outline`.
  final String renderer;

  /// Display title from the view contribution, when the host knows it.
  final String? title;

  /// Whether this surface is the currently visible placement of its view.
  ///
  /// Hidden surfaces stay mounted so their host-local widget state (for
  /// example, a TextField controller) survives switching between contributed
  /// views. The value is also forwarded to the plugin as a visibility signal so
  /// it can pause work for views that are kept alive but not displayed.
  final bool visible;

  /// Renderer-level props from the contribution (table columns, and so on).
  final Map<String, dynamic> viewProps;

  @override
  ConsumerState<PluginViewSurface> createState() => _PluginViewSurfaceState();
}

class _PluginViewSurfaceState extends ConsumerState<PluginViewSurface> {
  static const String manifestCommandMenuId = '__manifest.commands__';

  late final ComponentHostState _hostState = ComponentHostState(
    instance: widget.instance,
    onChanged: _onComponentChanged,
  );
  late final NativePluginViewRegistry _registry = NativePluginViewRegistry();
  late final ComponentRegistry _components = ComponentRegistry();
  late final SdkView _sdkView;
  late final ComponentMethodRegistry _componentMethods;
  PluginRunManager? _visibilityManager;
  bool _disposing = false;

  Listenable? _listenable;

  @override
  void initState() {
    super.initState();
    _sdkView = ref.read(sdkViewProvider);
    _componentMethods = ref.read(componentMethodRegistryProvider);
    _visibilityManager = _manager;
    _subscribe();
    _componentMethods.attach(widget.instance, _hostState);
    _scheduleVisibility(widget.instance, widget.visible);
  }

  @override
  void didUpdateWidget(covariant PluginViewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instance != widget.instance) {
      _componentMethods.detach(oldWidget.instance, _hostState);
      _hostState.instance = widget.instance;
      _componentMethods.attach(widget.instance, _hostState);
      _scheduleVisibility(oldWidget.instance, false);
      _listenable?.removeListener(_onModelChanged);
      _subscribe();
      _visibilityManager = _manager;
      _scheduleVisibility(widget.instance, widget.visible);
    } else if (oldWidget.visible != widget.visible) {
      _scheduleVisibility(widget.instance, widget.visible);
    }
  }

  void _subscribe() {
    _listenable =
        ref.read(viewModelStoreProvider).listenableFor(widget.instance)
          ..addListener(_onModelChanged);
  }

  void _onModelChanged() {
    if (!_disposing && mounted) setState(() {});
  }

  void _onComponentChanged() {
    if (!_disposing && mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposing = true;
    _listenable?.removeListener(_onModelChanged);
    _listenable = null;
    _scheduleVisibility(widget.instance, false);
    _componentMethods.detach(widget.instance, _hostState);
    _hostState.dispose();
    super.dispose();
  }

  /// The run manager for this instance's plugin, if it is still running.
  PluginRunManager? get _manager {
    for (final entry in ref.read(pluginRunManagerProvider).entries) {
      if (entry.key.id == widget.instance.pluginId) return entry.value;
    }
    return null;
  }

  /// Sends a component event back to the owning plugin.
  void _emit(String componentId, String event, Map<String, dynamic> payload) {
    if (event == 'select') {
      final itemId = payload['itemId']?.toString();
      if (itemId != null && _isManifestCommand(itemId)) {
        unawaited(
          _runCommand(
            itemId,
            context: {
              'viewId': widget.instance.viewId,
              'instanceId': widget.instance.instanceId,
              'pluginId': widget.instance.pluginId,
              if (payload['targetId'] != null) 'nodeId': payload['targetId'],
              if (payload['targetType'] != null)
                'targetType': payload['targetType'],
            },
          ),
        );
        return;
      }
    }
    final manager = _manager;
    if (manager == null) return;
    ref
        .read(sdkViewProvider)
        .sendComponentEvent(
          manager,
          widget.instance,
          componentId,
          event,
          payload,
        );
  }

  bool _isManifestCommand(String commandId) {
    final enabledPlugins = ref
        .read(pluginManagerProvider)
        .values
        .where((plugin) => plugin.status == PluginStatus.usable)
        .map((plugin) => plugin.id)
        .toSet();
    return ref
        .read(menuResolverProvider)
        .resolve(
          location: MenuResolver.viewContext,
          viewId: widget.instance.viewId,
          enabledPluginIds: enabledPlugins,
        )
        .any((item) => item.commandId == commandId);
  }

  Future<void> _runCommand(
    String commandId, {
    Map<String, dynamic> context = const {},
  }) async {
    try {
      await ref
          .read(commandServiceProvider)
          .execute(commandId, context: context);
    } on CommandException catch (error) {
      debugPrint('Plugin command failed (${error.code}): ${error.message}');
    }
  }

  Future<Map<String, dynamic>?> _requestContextMenu(
    String componentId,
    String targetId,
    String targetType,
  ) async {
    final manager = _manager;
    Map<String, dynamic>? pluginMenu;
    if (manager != null) {
      pluginMenu = await _sdkView.requestContextMenu(
        manager,
        widget.instance,
        componentId,
        targetId,
        targetType,
      );
    }
    return _mergeManifestContextMenu(pluginMenu);
  }

  Map<String, dynamic>? _mergeManifestContextMenu(
    Map<String, dynamic>? pluginMenu,
  ) {
    final enabledPlugins = ref
        .read(pluginManagerProvider)
        .values
        .where((plugin) => plugin.status == PluginStatus.usable)
        .map((plugin) => plugin.id)
        .toSet();
    final manifestItems = ref
        .read(menuResolverProvider)
        .resolve(
          location: MenuResolver.viewContext,
          viewId: widget.instance.viewId,
          enabledPluginIds: enabledPlugins,
        );
    if (manifestItems.isEmpty) return pluginMenu;

    final manifestEntries = [
      for (final item in manifestItems)
        {
          'id': item.commandId,
          'label': item.title,
          'enabled': item.enabled,
          if (item.materialIcon != null) 'icon': item.materialIcon,
        },
    ];

    if (pluginMenu == null || pluginMenu['type'] != 'ContextMenu') {
      return {
        'type': 'ContextMenu',
        'props': {'id': manifestCommandMenuId, 'items': manifestEntries},
      };
    }

    final props = Map<String, dynamic>.from(
      (pluginMenu['props'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value),
          ) ??
          const {},
    );
    final existing = List<dynamic>.from(
      props['items'] is List ? props['items'] as List : const [],
    );
    props['items'] = [
      ...existing,
      if (existing.isNotEmpty) {'kind': 'divider'},
      ...manifestEntries,
    ];
    return {'type': 'ContextMenu', 'props': props};
  }

  void _scheduleVisibility(ViewInstanceId instance, bool visible) {
    final manager = _visibilityManager;
    if (manager == null) return;
    final sdkView = _sdkView;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (visible && (_disposing || !mounted)) return;
      sdkView.sendVisibilityChanged(manager, instance, visible);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(viewModelStoreProvider);
    final model = store.model(widget.instance);

    if (model == null) {
      // The plugin has not sent its first snapshot yet.
      return const Center(child: CircularProgressIndicator());
    }

    if (model.state == ViewState.disconnected) {
      return _notice(
        context,
        icon: Icons.link_off,
        message: 'The plugin closed this view.',
      );
    }
    if (model.state == ViewState.error) {
      return ComponentErrorBoundary(
        title: 'The plugin reported a view error',
        diagnostics: [
          ComponentDiagnostic(
            path: widget.instance.viewId,
            message: 'the view is in an error state',
          ),
        ],
      );
    }

    final titleMenuItems = _titleMenuItems();
    final manifestTitleActions = _manifestTitleActions(titleMenuItems);
    final builder = ComponentBuilder(
      registry: _components,
      hostState: _hostState,
      onEvent: _emit,
      onContextMenuRequest: _requestContextMenu,
      hostAppBarActions: manifestTitleActions,
      pluginRootPath: _manager?.assetsPath,
    );
    _hostState.beginBuild();

    // A view model whose single node is a component tree renders as that tree;
    // otherwise the renderer interprets the nodes (rows, tree nodes, entries).
    final componentTree = _componentTreeOf(model);
    if (componentTree != null) {
      final result = builder.build(context, componentTree);
      _hostState.endBuild();
      return builder.hostAppBarActionsConsumed || manifestTitleActions.isEmpty
          ? result
          : _withHostAppBar(
              context,
              title: _viewTitle(model),
              actions: manifestTitleActions,
              body: result,
            );
    }

    final result = _registry.build(
      context,
      widget.renderer,
      NativeViewContext(
        instance: widget.instance,
        nodes: model.nodes,
        state: model.state,
        builder: builder,
        onEvent: _emit,
        props: widget.viewProps,
      ),
    );
    _hostState.endBuild();
    return _withHostAppBar(
      context,
      title: _viewTitle(model),
      actions: [...manifestTitleActions, ..._sdkTitleActions(model)],
      body: result,
    );
  }

  String _viewTitle(ViewModel model) {
    final actionTitle = model.nodes
        .where((node) => node['role'] == 'appBarAction')
        .map((node) => node['appBarTitle']?.toString())
        .whereType<String>()
        .firstOrNull;
    if (actionTitle != null && actionTitle.isNotEmpty) return actionTitle;

    final configTitle = model.nodes
        .where((node) => node['role'] == 'viewConfig')
        .map((node) => (node['props'] as Map?)?['title']?.toString())
        .whereType<String>()
        .firstOrNull;
    if (configTitle != null && configTitle.isNotEmpty) return configTitle;

    final contribution = ref
        .watch(contributionRegistryProvider)
        .views
        .byId(widget.instance.viewId);
    return widget.title ?? contribution?.value.title ?? widget.instance.viewId;
  }

  List<Widget> _manifestTitleActions(List<NativeTitleMenuItem> items) => [
    for (final item in items)
      IconButton(
        icon: Icon(pluginIcon(item.icon ?? 'material:more_horiz'), size: 18),
        tooltip: item.title,
        onPressed: !item.enabled
            ? null
            : () => _runCommand(
                item.commandId,
                context: {
                  'viewId': widget.instance.viewId,
                  'instanceId': widget.instance.instanceId,
                  'pluginId': widget.instance.pluginId,
                },
              ),
      ),
  ];

  List<Widget> _sdkTitleActions(ViewModel model) => [
    for (final action in model.nodes.where(
      (node) => node['role'] == 'appBarAction' || node['role'] == 'appBarMenu',
    ))
      if (action['role'] == 'appBarMenu')
        PluginMenuButton(
          items: pluginMenuEntries(action['items']),
          icon: action['icon']?.toString() ?? 'material:more_vert',
          tooltip: action['label']?.toString(),
          iconOnly: true,
          onSelected: (payload) => _emit(widget.instance.viewId, 'select', {
            'nodeId': action['id']?.toString(),
            ...payload,
          }),
        )
      else
        IconButton(
          icon: Icon(pluginIcon(action['icon']?.toString()), size: 18),
          tooltip: action['label']?.toString(),
          onPressed: () => _emit(widget.instance.viewId, 'select', {
            'nodeId': action['id']?.toString(),
          }),
        ),
  ];

  Widget _withHostAppBar(
    BuildContext context, {
    required String title,
    required List<Widget> actions,
    required Widget body,
  }) => Column(
    children: [
      AppBar(
        primary: false,
        automaticallyImplyLeading: false,
        toolbarHeight: 40,
        titleSpacing: 12,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        actions: actions,
      ),
      Expanded(child: body),
    ],
  );

  List<NativeTitleMenuItem> _titleMenuItems() {
    final enabledPlugins = ref
        .watch(pluginManagerProvider)
        .values
        .where((plugin) => plugin.status == PluginStatus.usable)
        .map((plugin) => plugin.id)
        .toSet();
    // Rebuild when context keys or contributions change.
    ref.watch(contributionRegistryProvider);
    ref.watch(contextKeyServiceProvider);
    return [
      for (final item
          in ref
              .read(menuResolverProvider)
              .resolve(
                location: MenuResolver.viewTitle,
                viewId: widget.instance.viewId,
                enabledPluginIds: enabledPlugins,
              ))
        NativeTitleMenuItem(
          commandId: item.commandId,
          title: item.title,
          enabled: item.enabled,
          icon: item.materialIcon ?? 'material:refresh',
        ),
    ];
  }

  /// Detects the "whole view is one component tree" shape.
  ///
  /// A plugin composing free-form UI sends a single node carrying a `component`
  /// map; renderer-driven views (tree, table, log) send plain data nodes.
  Map<String, dynamic>? _componentTreeOf(ViewModel model) {
    if (model.nodes.length != 1) return null;
    final node = model.nodes.first;
    if (node['type'] is String) return node;
    final component = node['component'];
    if (component is Map) {
      return component.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  Widget _notice(
    BuildContext context, {
    required IconData icon,
    required String message,
  }) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 6),
        Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
