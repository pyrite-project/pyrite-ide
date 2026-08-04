import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/sdk/component_schema.dart';
import 'package:pyrite_ide/core/sdk/renderer_registry.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/features/plugin_view/component_builder.dart';
import 'package:pyrite_ide/features/plugin_view/component_error_boundary.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_icons.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_menu.dart';

/// Everything a renderer builder needs to draw one view instance.
class NativeViewContext {
  const NativeViewContext({
    required this.instance,
    required this.nodes,
    required this.state,
    required this.builder,
    required this.onEvent,
    this.props = const {},
    this.titleMenuItems = const [],
    this.onCommand,
  });

  final ViewInstanceId instance;

  /// The view model's ordered nodes, straight from the T15 store.
  final List<Map<String, dynamic>> nodes;
  final ViewState state;

  /// Builds nested component trees (used by renderers that embed components).
  final ComponentBuilder builder;
  final ComponentEventSink onEvent;

  /// Renderer-level props supplied by the view contribution.
  final Map<String, dynamic> props;

  /// Manifest `view/title` menu items merged into the host AppBar.
  final List<NativeTitleMenuItem> titleMenuItems;

  /// Runs a Manifest command from a title-menu action.
  final Future<void> Function(String commandId)? onCommand;
}

/// A resolved Manifest menu item ready for the native AppBar.
class NativeTitleMenuItem {
  const NativeTitleMenuItem({
    required this.commandId,
    required this.title,
    required this.enabled,
    this.icon,
  });

  final String commandId;
  final String title;
  final bool enabled;
  final String? icon;
}

/// Signature for a renderer builder.
typedef NativeViewBuilder =
    Widget Function(BuildContext context, NativeViewContext view);

/// Maps renderer tokens to the Flutter widgets that draw them.
///
/// Each builder receives the view model rather than a component tree, so a
/// renderer like `native.outline` can own its row layout while still reusing the
/// common component layer for embedded pieces.
class NativePluginViewRegistry {
  NativePluginViewRegistry({
    RendererRegistry? renderers,
    Map<String, NativeViewBuilder>? builders,
  }) : renderers = renderers ?? RendererRegistry() {
    _builders.addAll(builders ?? _defaultBuilders());
  }

  final RendererRegistry renderers;
  final Map<String, NativeViewBuilder> _builders = {};

  bool isKnown(String token) => _builders.containsKey(token);
  Iterable<String> get tokens => _builders.keys;

  void register(String token, NativeViewBuilder builder) {
    _builders[token] = builder;
  }

  /// Builds the view for [token], falling back to an error boundary for an
  /// unknown renderer or model nodes that lack the fields it needs.
  Widget build(BuildContext context, String token, NativeViewContext view) {
    final builder = _builders[token];
    if (builder == null) {
      return ComponentErrorBoundary(
        title: 'Unknown renderer',
        diagnostics: [
          ComponentDiagnostic(
            path: token,
            message:
                'no renderer registered; known: ${tokens.toList()..sort()}',
          ),
        ],
      );
    }
    final problems = renderers.validateNodes(token, view.nodes);
    if (problems.isNotEmpty) {
      return ComponentErrorBoundary(
        title: 'View data does not match renderer "$token"',
        diagnostics: problems,
      );
    }
    if (view.state == ViewState.loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return builder(context, view);
  }

  /// Renderers are expressed as component trees so they inherit the component
  /// layer's theming, events, and error handling for free.
  static Map<String, NativeViewBuilder> _defaultBuilders() => {
    RendererTokens.tree: (context, view) {
      final props = _rendererProps(view);
      return view.builder.build(context, {
        'type': 'TreeView',
        'props': {
          'id': view.instance.viewId,
          'nodes': _rendererNodes(view),
          ...props,
        },
      });
    },
    RendererTokens.outline: (context, view) => _modelViewWithAppBar(
      context,
      view,
      defaultTitle: 'Outline',
      componentType: 'TreeView',
      itemsProp: 'nodes',
      emptyLabel: 'No symbols',
    ),
    RendererTokens.virtualList: (context, view) {
      final props = _rendererProps(view);
      return view.builder.build(context, {
        'type': 'VirtualList',
        'props': {
          'id': view.instance.viewId,
          'items': _rendererNodes(view),
          ...props,
        },
      });
    },
    RendererTokens.log: (context, view) {
      final props = _rendererProps(view);
      return view.builder.build(context, {
        'type': 'VirtualList',
        'props': {
          'id': view.instance.viewId,
          'items': _rendererNodes(view),
          'itemHeight': 18.0,
          'emptyLabel': 'No output',
          ...props,
        },
      });
    },
    RendererTokens.table: (context, view) {
      final props = _rendererProps(view);
      return view.builder.build(context, {
        'type': 'DataTable',
        'props': {
          'id': view.instance.viewId,
          'columns': props['columns'] ?? const [],
          'rows': _rendererNodes(view),
          ...props,
        },
      });
    },
    RendererTokens.variableInspector: (context, view) => _modelViewWithAppBar(
      context,
      view,
      defaultTitle: 'Device Variables',
      componentType: 'PropertyGrid',
      itemsProp: 'entries',
      emptyLabel: 'No device variables',
    ),
    RendererTokens.markdown: (context, view) => view.builder.build(context, {
      'type': 'Markdown',
      'props': {
        'id': view.instance.viewId,
        'value': _rendererNodes(
          view,
        ).map((n) => n['text']?.toString() ?? '').join('\n\n'),
      },
      'events': {'linkTap': true},
    }),
    // A form renders each node as a labelled input row.
    RendererTokens.form: (context, view) => view.builder.build(context, {
      'type': 'Column',
      'props': {'gap': 8},
      'children': [for (final node in _rendererNodes(view)) _formField(node)],
    }),
  };

  static List<Map<String, dynamic>> _rendererNodes(NativeViewContext view) =>
      view.nodes
          .where((node) => node['role'] != 'viewConfig')
          .toList(growable: false);

  static Map<String, dynamic> _rendererProps(NativeViewContext view) {
    final result = <String, dynamic>{...view.props};
    for (final node in view.nodes.where(
      (candidate) => candidate['role'] == 'viewConfig',
    )) {
      final props = node['props'];
      if (props is Map) {
        result.addAll(props.cast<String, dynamic>());
      }
    }
    return result;
  }

  /// Builds domain views with a host-owned title bar. Model nodes with
  /// `role=appBarAction` become icon actions, `role=appBarMenu` becomes a menu,
  /// and `role=placeholder` becomes a
  /// centred status message; neither is passed to the data component.
  static Widget _modelViewWithAppBar(
    BuildContext context,
    NativeViewContext view, {
    required String defaultTitle,
    required String componentType,
    required String itemsProp,
    required String emptyLabel,
  }) {
    final rendererProps = _rendererProps(view);
    final actions = view.nodes
        .where(
          (node) =>
              node['role'] == 'appBarAction' || node['role'] == 'appBarMenu',
        )
        .toList(growable: false);
    final placeholders = view.nodes
        .where((node) => node['role'] == 'placeholder')
        .toList(growable: false);
    final contextMenuProviders = view.nodes
        .where((node) => node['role'] == 'contextMenuProvider')
        .toList(growable: false);
    final content = view.nodes
        .where(
          (node) =>
              node['role'] != 'appBarAction' &&
              node['role'] != 'placeholder' &&
              node['role'] != 'appBarMenu' &&
              node['role'] != 'contextMenuProvider' &&
              node['role'] != 'viewConfig',
        )
        .toList(growable: false);
    final title =
        actions.firstOrNull?['appBarTitle']?.toString() ??
        rendererProps['title']?.toString() ??
        defaultTitle;

    final body = placeholders.isNotEmpty && content.isEmpty
        ? _placeholder(context, placeholders.first)
        : view.builder.build(context, {
            'type': componentType,
            'props': {
              'id': view.instance.viewId,
              itemsProp: content,
              'emptyLabel': emptyLabel,
              ...rendererProps,
            },
            if (contextMenuProviders.isNotEmpty)
              'events': {'contextMenuRequest': true},
          });

    return Column(
      children: [
        AppBar(
          primary: false,
          automaticallyImplyLeading: false,
          toolbarHeight: 40,
          titleSpacing: 12,
          elevation: 0,
          scrolledUnderElevation: 1,
          title: Text(title, style: Theme.of(context).textTheme.titleSmall),
          actions: [
            for (final item in view.titleMenuItems)
              IconButton(
                icon: Icon(
                  pluginIcon(item.icon ?? 'material:more_horiz'),
                  size: 18,
                ),
                tooltip: item.title,
                onPressed: !item.enabled || view.onCommand == null
                    ? null
                    : () => view.onCommand!(item.commandId),
              ),
            for (final action in actions)
              if (action['role'] == 'appBarMenu')
                PluginMenuButton(
                  items: pluginMenuEntries(action['items']),
                  icon: action['icon']?.toString() ?? 'material:more_vert',
                  tooltip: action['label']?.toString(),
                  iconOnly: true,
                  onSelected: (payload) => view.onEvent(
                    view.instance.viewId,
                    'select',
                    {'nodeId': action['id']?.toString(), ...payload},
                  ),
                )
              else
                IconButton(
                  icon: Icon(pluginIcon(action['icon']?.toString()), size: 18),
                  tooltip: action['label']?.toString(),
                  onPressed: () => view.onEvent(
                    view.instance.viewId,
                    'select',
                    {'nodeId': action['id']?.toString()},
                  ),
                ),
          ],
        ),
        Expanded(child: body),
      ],
    );
  }

  static Widget _placeholder(BuildContext context, Map<String, dynamic> node) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _actionIcon(node['icon']?.toString()),
              size: 24,
              color: node['state'] == 'error'
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              node['label']?.toString() ?? node['name']?.toString() ?? '',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _actionIcon(String? token) => pluginIcon(token);

  /// Maps one form model node to the input component it describes.
  static Map<String, dynamic> _formField(Map<String, dynamic> node) {
    final id = node['id']?.toString() ?? '';
    final label = node['label']?.toString();
    return switch (node['kind']?.toString()) {
      'number' => {
        'type': 'NumberField',
        'props': {'id': id, 'label': ?label, 'value': node['value']},
      },
      'boolean' => {
        'type': 'Switch',
        'props': {'id': id, 'label': ?label, 'value': node['value']},
      },
      'select' => {
        'type': 'Select',
        'props': {
          'id': id,
          'label': ?label,
          'value': node['value']?.toString(),
          'options': node['options'] ?? const [],
        },
      },
      _ => {
        'type': 'TextField',
        'props': {
          'id': id,
          'label': ?label,
          'value': node['value']?.toString(),
        },
      },
    };
  }
}
