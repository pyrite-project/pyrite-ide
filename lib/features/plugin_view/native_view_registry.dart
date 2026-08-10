import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/sdk/component_schema.dart';
import 'package:pyrite_ide/core/sdk/renderer_registry.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/features/plugin_view/component_builder.dart';
import 'package:pyrite_ide/features/plugin_view/component_error_boundary.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_icons.dart';

/// Everything a renderer builder needs to draw one view instance.
class NativeViewContext {
  const NativeViewContext({
    required this.instance,
    required this.nodes,
    required this.state,
    required this.builder,
    required this.onEvent,
    this.props = const {},
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
}

/// A resolved Manifest menu item ready for the host view title bar.
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
    RendererTokens.outline: (context, view) => _modelView(
      context,
      view,
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
    RendererTokens.log: (context, view) => _modelView(
      context,
      view,
      componentType: 'VirtualList',
      itemsProp: 'items',
      emptyLabel: 'No output',
      defaultItemHeight: 18.0,
    ),
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
    RendererTokens.variableInspector: (context, view) => _modelView(
      context,
      view,
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
          .where(
            (node) =>
                node['role'] != 'viewConfig' &&
                node['role'] != 'appBarAction' &&
                node['role'] != 'appBarMenu',
          )
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

  /// Builds renderer content while keeping view-chrome metadata out of its
  /// data component. The shared surface owns the title bar and its actions.
  static Widget _modelView(
    BuildContext context,
    NativeViewContext view, {
    required String componentType,
    required String itemsProp,
    required String emptyLabel,
    double? defaultItemHeight,
  }) {
    final rendererProps = _rendererProps(view);
    final placeholders = view.nodes
        .where((node) => node['role'] == 'placeholder')
        .toList(growable: false);
    final contextMenuProviders = view.nodes
        .where((node) => node['role'] == 'contextMenuProvider')
        .toList(growable: false);
    final content = _rendererNodes(view)
        .where(
          (node) =>
              node['role'] != 'placeholder' &&
              node['role'] != 'contextMenuProvider',
        )
        .toList(growable: false);

    return placeholders.isNotEmpty && content.isEmpty
        ? _placeholder(context, placeholders.first)
        : view.builder.build(context, {
            'type': componentType,
            'props': {
              'id': view.instance.viewId,
              itemsProp: content,
              'emptyLabel': emptyLabel,
              ...rendererProps,
              if (defaultItemHeight != null &&
                  rendererProps['itemHeight'] == null)
                'itemHeight': defaultItemHeight,
            },
            if (contextMenuProviders.isNotEmpty)
              'events': {'contextMenuRequest': true},
          });
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
