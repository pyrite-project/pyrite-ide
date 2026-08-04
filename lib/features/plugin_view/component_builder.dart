import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/sdk/component_schema.dart';
import 'package:pyrite_ide/core/sdk/component_method_registry.dart';
import 'package:pyrite_ide/features/plugin_view/component_error_boundary.dart';
import 'package:pyrite_ide/features/plugin_view/component_host_state.dart';
import 'package:pyrite_ide/features/plugin_view/data/plugin_data_table.dart';
import 'package:pyrite_ide/features/plugin_view/data/plugin_tree_view.dart';
import 'package:pyrite_ide/features/plugin_view/data/plugin_virtual_list.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_icons.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_dialog.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_markdown.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_menu.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_split_view.dart';
import 'package:pyrite_ide/core/sdk/plugin_resources.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_video_player.dart';

/// Signature for dispatching a component event back to the plugin.
///
/// [componentId] is the schema `id` prop, [event] the declared event name, and
/// [payload] any event-specific data (selected id, new value, …).
typedef ComponentEventSink =
    void Function(
      String componentId,
      String event,
      Map<String, dynamic> payload,
    );

typedef ComponentContextMenuRequest =
    Future<Map<String, dynamic>?> Function(
      String componentId,
      String targetId,
      String targetType,
    );

/// Builds Flutter widgets from validated component schema nodes.
///
/// The mapping is deliberately one-way and host-owned: schema prop names never
/// map straight onto Flutter constructor arguments, so this layer can be
/// rewritten (T17 replaces the data widgets with high-performance ones) without
/// changing the plugin-facing contract.
class ComponentBuilder {
  ComponentBuilder({
    required this.registry,
    required this.hostState,
    required this.onEvent,
    this.onContextMenuRequest,
    this.limits = const ComponentLimits(),
    this.pluginRootPath,
  });

  final ComponentRegistry registry;
  final ComponentHostState hostState;
  final ComponentEventSink onEvent;
  final ComponentContextMenuRequest? onContextMenuRequest;
  final ComponentLimits limits;
  final String? pluginRootPath;

  /// Validates [node] and builds it, returning an error boundary when the tree
  /// is malformed so a bad plugin can't crash the page.
  Widget build(BuildContext context, Map<String, dynamic> node) {
    final validation = registry.validate(node, limits: limits);
    if (!validation.isValid) {
      return ComponentErrorBoundary(diagnostics: validation.diagnostics);
    }
    return _build(context, node);
  }

  Widget _build(BuildContext context, Map<String, dynamic> node) {
    final type = node['type']?.toString() ?? '';
    var props = hostState.effectiveProps(_props(node));
    if (type == 'Tabs') {
      props = {
        ...props,
        '_tabIds': [
          for (final child in _children(node))
            if (_props(child)['id'] != null) _props(child)['id'].toString(),
        ],
      };
    }
    final normalized = {...node, 'props': props};
    final child = _buildRaw(context, normalized);
    final id = _id(props);
    if (id.isEmpty) return child;
    hostState.registerComponent(
      id,
      type,
      props,
      handler: (method, arguments) =>
          _invokeBuiltComponent(context, type, id, props, method, arguments),
    );
    final keyed = KeyedSubtree(key: hostState.componentKey(id), child: child);
    if (type == 'TextField' || type == 'NumberField') return keyed;
    return Focus(focusNode: hostState.focusNode(id), child: keyed);
  }

  Widget _buildRaw(BuildContext context, Map<String, dynamic> node) {
    final type = node['type']?.toString() ?? '';
    final props = _props(node);
    final children = _children(node);
    final hasContextMenuProvider = _hasEvent(node, 'contextMenuRequest');
    final hasContextMenuEvent = _hasEvent(node, 'contextMenu');

    switch (type) {
      // -- Layout ------------------------------------------------------------
      case 'Row':
        return Row(
          mainAxisAlignment: _mainAxis(props['justify']),
          crossAxisAlignment: _crossAxis(props['align']),
          children: _spaced(context, children, props['gap'], Axis.horizontal),
        );
      case 'Column':
        return Column(
          mainAxisAlignment: _mainAxis(props['justify']),
          crossAxisAlignment: _crossAxis(props['align']),
          mainAxisSize: MainAxisSize.min,
          children: _spaced(context, children, props['gap'], Axis.vertical),
        );
      case 'Flex':
        // Flex distributes space, so children are expanded along the axis.
        // This is what gives a scrollable child (VirtualList, TreeView…) a
        // bounded extent; a plain Column would leave it unconstrained.
        final vertical = props['direction'] == 'vertical';
        final axis = vertical ? Axis.vertical : Axis.horizontal;
        // Expanded is only legal when the incoming constraint along the axis is
        // bounded. A plugin may nest a Flex inside a min-size Column, so fall
        // back to shrink-wrapped children rather than throwing.
        return LayoutBuilder(
          builder: (context, constraints) {
            final bounded = vertical
                ? constraints.hasBoundedHeight
                : constraints.hasBoundedWidth;
            if (!bounded) {
              return Flex(
                direction: axis,
                mainAxisSize: MainAxisSize.min,
                children: _spaced(context, children, props['gap'], axis),
              );
            }
            return Flex(
              direction: axis,
              children: [
                for (final child in children)
                  Expanded(
                    flex: (_props(child)['flex'] as num?)?.toInt() ?? 1,
                    child: _build(context, child),
                  ),
              ],
            );
          },
        );
      case 'Grid':
        final columns = (props['columns'] as num?)?.toInt() ?? 1;
        final gap = (props['gap'] as num?)?.toDouble() ?? 0;
        return GridView.count(
          crossAxisCount: columns,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final c in children) _build(context, c)],
        );
      case 'Wrap':
        return Wrap(
          spacing: (props['gap'] as num?)?.toDouble() ?? 0,
          runSpacing: (props['runGap'] as num?)?.toDouble() ?? 0,
          children: [for (final c in children) _build(context, c)],
        );
      case 'SplitView':
        final ratio = (props['initialRatio'] as num?)?.toDouble() ?? 0.5;
        final vertical = props['direction'] == 'vertical';
        return PluginSplitView(
          key: hostState.stateKey<PluginSplitViewState>(_id(props)),
          direction: vertical ? Axis.vertical : Axis.horizontal,
          initialRatio: ratio,
          children: [for (final child in children) _build(context, child)],
        );
      case 'Tabs':
        return _buildTabs(context, props, children);
      case 'Tab':
        return children.isEmpty
            ? const SizedBox.shrink()
            : _build(context, children.first);
      case 'Section':
        return _buildSection(context, props, children);
      case 'Toolbar':
        return Container(
          height: props['dense'] == true ? 32 : 40,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: Row(children: _spaced(context, children, 4, Axis.horizontal)),
        );

      // -- Content -----------------------------------------------------------
      case 'Text':
        return Text(
          props['value']?.toString() ?? '',
          style: _textStyle(context, props),
          maxLines: (props['maxLines'] as num?)?.toInt(),
          overflow: props['maxLines'] == null ? null : TextOverflow.ellipsis,
        );
      case 'Icon':
        return Icon(
          _icon(props['name']?.toString()),
          size: (props['size'] as num?)?.toDouble() ?? 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
      case 'Image':
        final source = props['src']?.toString() ?? '';
        final assetPath = pluginResourcePath(source);
        final file = assetPath == null || pluginRootPath == null
            ? null
            : resolvePluginAssetFile(pluginRootPath!, assetPath);
        if (assetPath != null && file == null) {
          return const Icon(Icons.broken_image_outlined);
        }
        return file == null
            ? Image.network(
                source,
                width: (props['width'] as num?)?.toDouble(),
                height: (props['height'] as num?)?.toDouble(),
                fit: switch (props['fit']) {
                  'cover' => BoxFit.cover,
                  'fill' => BoxFit.fill,
                  'none' => BoxFit.none,
                  _ => BoxFit.contain,
                },
                errorBuilder: (context, error, stack) => Icon(
                  Icons.broken_image_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
              )
            : Image.file(
                file,
                width: (props['width'] as num?)?.toDouble(),
                height: (props['height'] as num?)?.toDouble(),
                fit: switch (props['fit']) {
                  'cover' => BoxFit.cover,
                  'fill' => BoxFit.fill,
                  'none' => BoxFit.none,
                  _ => BoxFit.contain,
                },
                errorBuilder: (context, error, stack) => Icon(
                  Icons.broken_image_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
              );
      case 'Video':
        final source = props['src']?.toString() ?? '';
        final assetPath = pluginResourcePath(source);
        final file = assetPath == null || pluginRootPath == null
            ? null
            : resolvePluginAssetFile(pluginRootPath!, assetPath);
        if (file == null) return const Icon(Icons.broken_image_outlined);
        return PluginVideoPlayer(
          key: hostState.stateKey<PluginVideoPlayerState>(_id(props)),
          source: file.path,
          sourceType: 'file',
          package: null,
          autoplay: props['autoplay'] == true,
          looping: props['looping'] == true,
          muted: props['muted'] == true,
          showControls: props['showControls'] != false,
          fit: switch (props['fit']) {
            'cover' => BoxFit.cover,
            'fill' => BoxFit.fill,
            'none' => BoxFit.none,
            _ => BoxFit.contain,
          },
          width: (props['width'] as num?)?.toDouble(),
          height: (props['height'] as num?)?.toDouble(),
        );
      case 'Markdown':
        final id = _id(props);
        return PluginMarkdown(
          key: hostState.stateKey<PluginMarkdownState>(id),
          data: props['value']?.toString() ?? '',
          pluginRootPath: pluginRootPath,
          onTapLink: id.isEmpty
              ? null
              : (href) => onEvent(id, 'linkTap', {'href': href}),
        );
      case 'CodeBlock':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SelectableText(
            props['code']?.toString() ?? '',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        );
      case 'Badge':
        return _buildBadge(context, props);

      // -- Input -------------------------------------------------------------
      case 'TextField':
        return _buildTextField(context, props);
      case 'NumberField':
        return _buildNumberField(context, props);
      case 'Select':
        return _buildSelect(context, props);
      case 'Checkbox':
        return _buildCheckbox(context, props);
      case 'Switch':
        return _buildSwitch(context, props);
      case 'Slider':
        return _buildSlider(context, props);

      // -- Actions -----------------------------------------------------------
      case 'Button':
        return _buildButton(context, props);
      case 'IconButton':
        return _buildIconButton(context, props);
      case 'Dropdown':
        return _buildDropdown(context, props);
      case 'Menu':
        return PluginMenuButton(
          controller: hostState.controller<MenuController>(
            _id(props),
            MenuController.new,
          ),
          items: _entryList(props['items']),
          label: props['label']?.toString(),
          icon: props['icon']?.toString(),
          tooltip: props['tooltip']?.toString(),
          enabled: _enabled(props),
          alignment: props['alignment']?.toString() ?? 'bottomStart',
          offsetX: (props['offsetX'] as num?)?.toDouble() ?? 0,
          offsetY: (props['offsetY'] as num?)?.toDouble() ?? 0,
          useRootOverlay: props['useRootOverlay'] != false,
          trigger: children.isEmpty ? null : _build(context, children.first),
          iconOnly: props['iconOnly'] == true,
          onSelected: (payload) => onEvent(_id(props), 'select', payload),
        );
      case 'MenuBar':
        return PluginMenuBar(
          controller: hostState.controller<PluginMenuBarController>(
            _id(props),
            PluginMenuBarController.new,
          ),
          items: _entryList(props['items']),
          onSelected: (payload) => onEvent(_id(props), 'select', payload),
        );
      case 'ContextMenu':
        return children.isEmpty
            ? const SizedBox.shrink()
            : buildPluginContextMenu(
                child: _build(context, children.first),
                items: _entryList(props['items']),
                enabled: _enabled(props),
                onSelected: (payload) => onEvent(_id(props), 'select', payload),
              );
      case 'Dialog':
        return PluginDialogHost(
          key: hostState.stateKey<PluginDialogHostState>(_id(props)),
          open: props['open'] == true,
          title: props['title']?.toString(),
          onClosed: (result) =>
              onEvent(_id(props), 'close', {'result': result}),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final child in children) _build(context, child)],
          ),
        );
      case 'Tooltip':
        return Tooltip(
          message: props['message']?.toString() ?? '',
          child: children.isEmpty
              ? const SizedBox.shrink()
              : _build(context, children.first),
        );

      // -- Data --------------------------------------------------------------
      // Basic implementations; T17 replaces these with the high-performance
      // VirtualList/TreeView/DataTable backed by super_tree and
      // material_table_view.
      case 'VirtualList':
        return _buildVirtualList(context, props, hasContextMenuProvider);
      case 'TreeView':
        return _buildTreeView(
          context,
          props,
          hasContextMenuProvider,
          hasContextMenuEvent,
        );
      case 'DataTable':
        return _buildDataTable(context, props, hasContextMenuProvider);
      case 'PropertyGrid':
        return _buildPropertyGrid(context, props, hasContextMenuProvider);
    }

    // Unreachable for validated trees; kept as a defensive boundary.
    return ComponentErrorBoundary(
      compact: true,
      diagnostics: [
        ComponentDiagnostic(
          path: type,
          message: 'no builder registered for "$type"',
        ),
      ],
    );
  }

  Future<Object?> _invokeBuiltComponent(
    BuildContext context,
    String type,
    String id,
    Map<String, dynamic> props,
    String method,
    Map<String, dynamic> arguments,
  ) async {
    final mountedContext = hostState.componentKey(id).currentContext;
    if (method == 'is_mounted') return mountedContext != null;
    if (method == 'ensure_visible') {
      if (mountedContext == null) return false;
      await Scrollable.ensureVisible(
        mountedContext,
        alignment: (arguments['alignment'] as num?)?.toDouble() ?? 0.5,
        duration: arguments['animated'] == false
            ? Duration.zero
            : const Duration(milliseconds: 180),
      );
      return true;
    }
    if (method == 'get_bounds') {
      final box = mountedContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return null;
      final offset = box.localToGlobal(Offset.zero);
      return {
        'x': offset.dx,
        'y': offset.dy,
        'width': box.size.width,
        'height': box.size.height,
      };
    }
    if (method == 'request_focus' || method == 'unfocus') {
      final focus = hostState.focusNode(id);
      method == 'request_focus' ? focus.requestFocus() : focus.unfocus();
      return true;
    }
    final animated = arguments['animated'] != false;
    switch (type) {
      case 'VirtualList':
        final state = hostState
            .stateKey<PluginVirtualListState>(id)
            .currentState;
        if (state == null) return false;
        switch (method) {
          case 'select':
            return state.selectItem(arguments['id']?.toString() ?? '');
          case 'clear_selection':
            state.clearSelection();
            return true;
          case 'reveal_item':
            return state.revealItem(
              arguments['id']?.toString() ?? '',
              animated: animated,
            );
          case 'jump_to_index':
          case 'animate_to_index':
            await state.scrollToIndex(
              (arguments['index'] as num?)?.toInt() ?? 0,
              animated: method == 'animate_to_index',
            );
            return true;
          case 'scroll_by':
            await state.scrollBy(
              (arguments['delta'] as num?)?.toDouble() ?? 0,
              animated: animated,
            );
            return true;
          case 'get_visible_range':
            return state.visibleRange;
        }
      case 'TreeView':
      case 'PropertyGrid':
        final state = hostState.stateKey<PluginTreeViewState>(id).currentState;
        if (state == null) return false;
        final target = arguments['id']?.toString() ?? '';
        switch (method) {
          case 'select':
            return state.selectNode(target);
          case 'clear_selection':
            state.clearSelection();
            return true;
          case 'reveal':
            return state.revealNode(target, animated: animated);
          case 'expand':
            return state.expandNode(target);
          case 'collapse':
            return state.collapseNode(target);
          case 'toggle':
            return state.toggleNode(target);
          case 'expand_all':
            state.expandAll();
            return true;
          case 'collapse_all':
            state.collapseAll();
            return true;
          case 'is_expanded':
            return state.widget.index.isExpanded(target);
          case 'get_visible_nodes':
            return state.visibleNodeIds;
          case 'activate':
            if (state.widget.index.node(target) == null) return false;
            onEvent(id, 'activate', {'nodeId': target});
            return true;
        }
      case 'DataTable':
        final state = hostState.stateKey<PluginDataTableState>(id).currentState;
        if (state == null) return false;
        switch (method) {
          case 'select_row':
            return state.selectRow(arguments['id']?.toString() ?? '');
          case 'clear_selection':
            state.clearSelection();
            return true;
          case 'reveal_row':
            return state.revealRow(
              arguments['id']?.toString() ?? '',
              animated: animated,
            );
          case 'reveal_cell':
            return state.revealCell(
              arguments['rowId']?.toString() ?? '',
              arguments['columnId']?.toString() ?? '',
              animated: animated,
            );
          case 'jump_to_row':
          case 'animate_to_row':
            await state.scrollToRow(
              (arguments['index'] as num?)?.toInt() ?? 0,
              animated: method == 'animate_to_row',
            );
            return true;
          case 'get_visible_range':
            return state.visibleRange;
        }
      case 'SplitView':
        final state = hostState.stateKey<PluginSplitViewState>(id).currentState;
        if (state == null) return false;
        switch (method) {
          case 'get_ratios':
            return state.ratios;
          case 'set_ratio':
            return state.setRatio(
              (arguments['index'] as num?)?.toInt() ?? 0,
              (arguments['ratio'] as num?)?.toDouble() ?? 0.5,
            );
          case 'set_ratios':
            final values = arguments['ratios'];
            return values is List
                ? state.setRatios([
                    for (final value in values)
                      if (value is num) value.toDouble(),
                  ])
                : false;
          case 'reset':
            state.resetRatios();
            return true;
        }
      case 'Video':
        final state = hostState
            .stateKey<PluginVideoPlayerState>(id)
            .currentState;
        if (state == null) return false;
        switch (method) {
          case 'play':
            await state.play();
            return true;
          case 'pause':
            await state.pause();
            return true;
          case 'seek_to':
            await state.seekTo(
              Duration(
                milliseconds: (arguments['positionMs'] as num?)?.toInt() ?? 0,
              ),
            );
            return true;
          case 'set_volume':
            await state.setVolume(
              (arguments['volume'] as num?)?.toDouble() ?? 1,
            );
            return true;
          case 'set_speed':
            await state.setPlaybackSpeed(
              (arguments['speed'] as num?)?.toDouble() ?? 1,
            );
            return true;
          case 'set_looping':
            await state.setLooping(arguments['looping'] == true);
            return true;
          case 'get_state':
            return state.playbackState;
          case 'enter_fullscreen':
            unawaited(state.enterFullscreen());
            return true;
          case 'exit_fullscreen':
            state.exitFullscreen();
            return true;
        }
      case 'Image':
        final provider = _componentImageProvider(props);
        if (provider == null) return false;
        if (method == 'reload' || method == 'evict_cache') {
          final evicted = await provider.evict();
          if (method == 'reload') hostState.onChanged?.call();
          return evicted;
        }
        if (method == 'get_intrinsic_size') {
          final completer = Completer<Map<String, dynamic>>();
          late final ImageStreamListener listener;
          final stream = provider.resolve(
            createLocalImageConfiguration(context),
          );
          listener = ImageStreamListener(
            (image, synchronousCall) {
              stream.removeListener(listener);
              if (!completer.isCompleted) {
                completer.complete({
                  'width': image.image.width,
                  'height': image.image.height,
                });
              }
            },
            onError: (Object error, StackTrace? stackTrace) {
              stream.removeListener(listener);
              if (!completer.isCompleted) {
                completer.completeError(error, stackTrace);
              }
            },
          );
          stream.addListener(listener);
          return completer.future;
        }
      case 'Markdown':
        final state = hostState.stateKey<PluginMarkdownState>(id).currentState;
        if (state == null) return false;
        switch (method) {
          case 'scroll_to_anchor':
            return state.scrollToAnchor(arguments['anchor']?.toString() ?? '');
          case 'get_anchor_offset':
            return state.anchorOffset(arguments['anchor']?.toString() ?? '');
          case 'select_all':
            return state.selectAll();
          case 'copy_selection':
            await state.copySelection();
            return true;
        }
      case 'Menu':
        final controller = hostState.controller<MenuController>(
          id,
          MenuController.new,
        );
        if (method == 'is_open') return controller.isOpen;
        if (method == 'open') controller.open();
        if (method == 'close') controller.close();
        if (method == 'toggle') {
          controller.isOpen ? controller.close() : controller.open();
        }
        if (const {'open', 'close', 'toggle'}.contains(method)) return true;
      case 'MenuBar':
        final controller = hostState.controller<PluginMenuBarController>(
          id,
          PluginMenuBarController.new,
        );
        if (method == 'open_menu') {
          return controller.openMenu(arguments['id']?.toString() ?? '');
        }
        if (method == 'close') {
          controller.close();
          return true;
        }
        if (method == 'is_open') return controller.isOpen;
      case 'Dropdown':
        final popup = hostState.controller<PluginPopupController>(
          id,
          PluginPopupController.new,
        );
        if (method == 'open') {
          final state = hostState
              .stateKey<PopupMenuButtonState<String>>(id)
              .currentState;
          if (state == null) return false;
          state.showButtonMenu();
          popup.isOpen = true;
          return true;
        }
        if (method == 'close') {
          if (popup.isOpen && mountedContext != null) {
            Navigator.of(mountedContext).maybePop();
          }
          popup.isOpen = false;
          return true;
        }
        if (method == 'select') {
          final itemId = arguments['id']?.toString();
          if (!_entryList(
            props['items'],
          ).any((item) => item['id']?.toString() == itemId)) {
            return false;
          }
          popup.selectedId = itemId;
          onEvent(id, 'select', {'itemId': itemId});
          return true;
        }
        if (method == 'get_selected') return popup.selectedId;
        if (method == 'is_open') return popup.isOpen;
      case 'ContextMenu':
        final popup = hostState.controller<PluginPopupController>(
          id,
          PluginPopupController.new,
        );
        if (method == 'is_open') return popup.isOpen;
        if (method == 'close') {
          if (popup.isOpen && mountedContext != null) {
            Navigator.of(mountedContext).maybePop();
          }
          popup.isOpen = false;
          return true;
        }
        if (method == 'show' && mountedContext != null) {
          final overlay =
              Overlay.of(mountedContext).context.findRenderObject()
                  as RenderBox;
          final box = mountedContext.findRenderObject() as RenderBox?;
          final origin = arguments['x'] is num && arguments['y'] is num
              ? Offset(
                  (arguments['x'] as num).toDouble(),
                  (arguments['y'] as num).toDouble(),
                )
              : box?.localToGlobal(Offset.zero) ?? Offset.zero;
          popup.isOpen = true;
          unawaited(
            showMenu<String>(
              context: mountedContext,
              position: RelativeRect.fromRect(
                Rect.fromLTWH(origin.dx, origin.dy, 1, 1),
                Offset.zero & overlay.size,
              ),
              items: [
                for (final item in _entryList(props['items']))
                  if (item['type'] != 'divider')
                    PopupMenuItem<String>(
                      value: item['id']?.toString(),
                      enabled: item['enabled'] != false,
                      child: Text(item['label']?.toString() ?? ''),
                    ),
              ],
            ).then((selected) {
              popup.isOpen = false;
              if (selected != null) {
                onEvent(id, 'select', {'itemId': selected});
              }
            }),
          );
          return true;
        }
      case 'Dialog':
        final state = hostState
            .stateKey<PluginDialogHostState>(id)
            .currentState;
        if (state == null) return false;
        if (method == 'is_open') return state.isOpen;
        if (method == 'show') {
          hostState.setOverride(id, 'open', true);
          state.show();
          return true;
        }
        if (method == 'close') {
          final result = arguments['result'];
          hostState.setOverride(id, 'open', false);
          state.close(result);
          return result ?? true;
        }
    }
    throw ComponentMethodException(
      'method_not_supported',
      '$type does not support "$method"',
      details: {'componentType': type, 'method': method},
    );
  }

  ImageProvider<Object>? _componentImageProvider(Map<String, dynamic> props) {
    final source = props['src']?.toString() ?? '';
    final assetPath = pluginResourcePath(source);
    final file = assetPath == null || pluginRootPath == null
        ? null
        : resolvePluginAssetFile(pluginRootPath!, assetPath);
    if (file != null) return FileImage(file);
    final uri = Uri.tryParse(source);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https')
        ? NetworkImage(source)
        : null;
  }

  // -- Helpers ---------------------------------------------------------------

  Map<String, dynamic> _props(Map<String, dynamic> node) {
    final raw = node['props'];
    return raw is Map
        ? raw.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _children(Map<String, dynamic> node) {
    final raw = node['children'];
    return raw is List
        ? [
            for (final child in raw)
              if (child is Map) child.map((k, v) => MapEntry(k.toString(), v)),
          ]
        : const <Map<String, dynamic>>[];
  }

  bool _hasEvent(Map<String, dynamic> node, String event) {
    final events = node['events'];
    return events is Map && events[event] == true;
  }

  String _id(Map<String, dynamic> props) => props['id']?.toString() ?? '';

  bool _enabled(Map<String, dynamic> props) => props['enabled'] != false;

  List<Widget> _spaced(
    BuildContext context,
    List<Map<String, dynamic>> children,
    Object? gap,
    Axis axis,
  ) {
    final spacing = (gap as num?)?.toDouble() ?? 0;
    final built = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      built.add(_build(context, children[i]));
      if (spacing > 0 && i != children.length - 1) {
        built.add(
          axis == Axis.horizontal
              ? SizedBox(width: spacing)
              : SizedBox(height: spacing),
        );
      }
    }
    return built;
  }

  MainAxisAlignment _mainAxis(Object? value) => switch (value) {
    'center' => MainAxisAlignment.center,
    'end' => MainAxisAlignment.end,
    'spaceBetween' => MainAxisAlignment.spaceBetween,
    'spaceAround' => MainAxisAlignment.spaceAround,
    _ => MainAxisAlignment.start,
  };

  CrossAxisAlignment _crossAxis(Object? value) => switch (value) {
    'center' => CrossAxisAlignment.center,
    'end' => CrossAxisAlignment.end,
    'stretch' => CrossAxisAlignment.stretch,
    _ => CrossAxisAlignment.start,
  };

  TextStyle? _textStyle(BuildContext context, Map<String, dynamic> props) {
    final theme = Theme.of(context).textTheme;
    final base = switch (props['style']) {
      'caption' => theme.bodySmall,
      'title' => theme.titleSmall,
      'heading' => theme.titleMedium,
      'code' => theme.bodySmall?.copyWith(fontFamily: 'monospace'),
      _ => theme.bodyMedium,
    };
    if (props['muted'] == true) {
      return base?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    return base;
  }

  /// Maps a stable icon token to a Material icon, so plugins never reference
  /// Flutter's IconData directly.
  IconData _icon(String? token) => pluginIcon(token);

  List<Map<String, dynamic>> _entryList(Object? raw) => raw is List
      ? [
          for (final e in raw)
            if (e is Map) e.map((k, v) => MapEntry(k.toString(), v)),
        ]
      : const <Map<String, dynamic>>[];

  // -- Layout builders -------------------------------------------------------

  Widget _buildTabs(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    if (children.isEmpty) return const SizedBox.shrink();
    final selected = props['selected']?.toString();
    var index = children.indexWhere(
      (c) => _props(c)['id']?.toString() == selected,
    );
    if (index < 0) index = 0;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < children.length; i++)
              _tabHeader(context, children[i], i == index, scheme),
          ],
        ),
        _build(context, children[index]),
      ],
    );
  }

  Widget _tabHeader(
    BuildContext context,
    Map<String, dynamic> tab,
    bool active,
    ColorScheme scheme,
  ) {
    final tabProps = _props(tab);
    return InkWell(
      onTap: () =>
          onEvent('tabs', 'change', {'id': tabProps['id']?.toString()}),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          tabProps['label']?.toString() ?? '',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: active ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    Map<String, dynamic> props,
    List<Map<String, dynamic>> children,
  ) {
    final collapsed = props['collapsed'] == true;
    final collapsible = props['collapsible'] == true;
    final header = props['title'] == null
        ? null
        : InkWell(
            onTap: collapsible
                ? () => onEvent('section', 'toggle', {'collapsed': !collapsed})
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  if (collapsible)
                    Icon(
                      collapsed ? Icons.chevron_right : Icons.expand_more,
                      size: 16,
                    ),
                  Text(
                    props['title'].toString(),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?header,
        if (!collapsed)
          for (final child in children) _build(context, child),
      ],
    );
  }

  Widget _buildBadge(BuildContext context, Map<String, dynamic> props) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (props['tone']) {
      'info' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      'success' => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      'warning' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      'danger' => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        props['label']?.toString() ?? '',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }

  // -- Input builders --------------------------------------------------------

  Widget _buildTextField(BuildContext context, Map<String, dynamic> props) {
    final id = _id(props);
    final pluginValue = props['value']?.toString() ?? '';
    // The controller is host-owned: keystrokes render immediately and only the
    // debounced change event crosses to Python.
    final controller = hostState.textController(id, pluginValue);
    return TextField(
      controller: controller,
      focusNode: hostState.focusNode(id),
      enabled: _enabled(props),
      maxLines: props['multiline'] == true ? null : 1,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: true,
        labelText: props['label']?.toString(),
        hintText: props['placeholder']?.toString(),
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) => hostState.recordEdit(
        id,
        value,
        (v) => onEvent(id, 'change', {'value': v}),
      ),
      onSubmitted: (value) => hostState.flush(
        id,
        value,
        (v) => onEvent(id, 'submit', {'value': v}),
      ),
    );
  }

  Widget _buildNumberField(BuildContext context, Map<String, dynamic> props) {
    final id = _id(props);
    final pluginValue = (props['value'] as num?)?.toString() ?? '';
    final controller = hostState.textController(id, pluginValue);
    return TextField(
      controller: controller,
      focusNode: hostState.focusNode(id),
      enabled: _enabled(props),
      keyboardType: TextInputType.number,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: true,
        labelText: props['label']?.toString(),
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) => hostState.recordEdit(
        id,
        num.tryParse(value),
        (v) => onEvent(id, 'change', {'value': v}),
      ),
      onSubmitted: (value) => hostState.flush(
        id,
        num.tryParse(value),
        (v) => onEvent(id, 'submit', {'value': v}),
      ),
    );
  }

  Widget _buildSelect(BuildContext context, Map<String, dynamic> props) {
    final id = _id(props);
    final options = _entryList(props['options']);
    final value = hostState.displayValue(id, props['value'])?.toString();
    return DropdownButton<String>(
      value: options.any((o) => o['value']?.toString() == value) ? value : null,
      isDense: true,
      hint: Text(props['label']?.toString() ?? ''),
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option['value']?.toString(),
            child: Text(option['label']?.toString() ?? ''),
          ),
      ],
      onChanged: _enabled(props)
          ? (selected) => hostState.flush(
              id,
              selected,
              (v) => onEvent(id, 'change', {'value': v}),
            )
          : null,
    );
  }

  Widget _buildCheckbox(BuildContext context, Map<String, dynamic> props) {
    final id = _id(props);
    final value = hostState.displayValue(id, props['value']) == true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: _enabled(props)
              ? (next) => hostState.flush(
                  id,
                  next,
                  (v) => onEvent(id, 'change', {'value': v}),
                )
              : null,
        ),
        if (props['label'] != null)
          Text(
            props['label'].toString(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
      ],
    );
  }

  Widget _buildSwitch(BuildContext context, Map<String, dynamic> props) {
    final id = _id(props);
    final value = hostState.displayValue(id, props['value']) == true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: value,
          onChanged: _enabled(props)
              ? (next) => hostState.flush(
                  id,
                  next,
                  (v) => onEvent(id, 'change', {'value': v}),
                )
              : null,
        ),
        if (props['label'] != null)
          Text(
            props['label'].toString(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
      ],
    );
  }

  Widget _buildSlider(BuildContext context, Map<String, dynamic> props) {
    final id = _id(props);
    final min = (props['min'] as num?)?.toDouble() ?? 0;
    final max = (props['max'] as num?)?.toDouble() ?? 100;
    final raw = hostState.displayValue(id, props['value']);
    final value = ((raw as num?)?.toDouble() ?? min).clamp(min, max);
    return Slider(
      value: value,
      min: min,
      max: max,
      divisions: props['step'] is num && (props['step'] as num) > 0
          ? ((max - min) / (props['step'] as num)).round().clamp(1, 1000)
          : null,
      onChanged: _enabled(props)
          ? (next) => hostState.recordEdit(
              id,
              next,
              (v) => onEvent(id, 'change', {'value': v}),
            )
          : null,
    );
  }

  // -- Action builders -------------------------------------------------------

  Widget _buildButton(BuildContext context, Map<String, dynamic> props) {
    final id = _id(props);
    final label = Text(props['label']?.toString() ?? '');
    final icon = props['icon'] == null
        ? null
        : Icon(_icon(props['icon'].toString()), size: 16);
    final onPressed = _enabled(props)
        ? () => onEvent(id, 'press', const {})
        : null;
    return switch (props['variant']) {
      'secondary' =>
        icon == null
            ? OutlinedButton(onPressed: onPressed, child: label)
            : OutlinedButton.icon(
                onPressed: onPressed,
                icon: icon,
                label: label,
              ),
      'ghost' =>
        icon == null
            ? TextButton(onPressed: onPressed, child: label)
            : TextButton.icon(onPressed: onPressed, icon: icon, label: label),
      'danger' => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        child: label,
      ),
      _ =>
        icon == null
            ? FilledButton(onPressed: onPressed, child: label)
            : FilledButton.icon(onPressed: onPressed, icon: icon, label: label),
    };
  }

  Widget _buildIconButton(BuildContext context, Map<String, dynamic> props) {
    final id = _id(props);
    return IconButton(
      icon: Icon(_icon(props['icon']?.toString()), size: 16),
      tooltip: props['tooltip']?.toString(),
      visualDensity: VisualDensity.compact,
      onPressed: _enabled(props) ? () => onEvent(id, 'press', const {}) : null,
    );
  }

  Widget _buildDropdown(BuildContext context, Map<String, dynamic> props) {
    final id = _id(props);
    final items = _entryList(props['items']);
    final popup = hostState.controller<PluginPopupController>(
      id,
      PluginPopupController.new,
    );
    return PopupMenuButton<String>(
      key: hostState.stateKey<PopupMenuButtonState<String>>(id),
      tooltip: props['label']?.toString(),
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem(
            value: item['id']?.toString(),
            enabled: item['enabled'] != false,
            child: Row(
              children: [
                if (item['icon'] != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(_icon(item['icon'].toString()), size: 16),
                  ),
                Text(item['label']?.toString() ?? ''),
              ],
            ),
          ),
      ],
      onOpened: () => popup.isOpen = true,
      onSelected: (selected) {
        popup
          ..isOpen = false
          ..selectedId = selected;
        onEvent(id, 'select', {'itemId': selected});
      },
      onCanceled: () => popup.isOpen = false,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            props['label']?.toString() ?? '',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const Icon(Icons.expand_more, size: 16),
        ],
      ),
    );
  }

  // -- Data builders ---------------------------------------------------------
  //
  // Rows build lazily via ListView.builder so a large model does not create a
  // widget per logical row. T17 replaces these with the tuned implementations
  // (super_tree for TreeView, material_table_view for DataTable) and adds
  // keyboard navigation, incremental visible-index maintenance, and paging.

  Widget _buildVirtualList(
    BuildContext context,
    Map<String, dynamic> props,
    bool hasContextMenuProvider,
  ) {
    final id = _id(props);
    final items = _entryList(props['items']);
    // itemCount may exceed the loaded window: the rest arrive via requestRange.
    final declared = (props['itemCount'] as num?)?.toInt();
    final itemCount = declared != null && declared > items.length
        ? declared
        : items.length;
    if (itemCount == 0) return _emptyState(context, props);
    return PluginVirtualList(
      key: hostState.stateKey<PluginVirtualListState>(id),
      items: {for (var i = 0; i < items.length; i++) i: items[i]},
      itemCount: itemCount,
      itemExtent: (props['itemHeight'] as num?)?.toDouble() ?? 22,
      selectedId: props['selectedId']?.toString(),
      emptyLabel: props['emptyLabel']?.toString(),
      onSelect: (itemId) => onEvent(id, 'select', {'itemId': itemId}),
      onActivate: (itemId) => onEvent(id, 'activate', {'itemId': itemId}),
      onRequestRange: (start, count) =>
          onEvent(id, 'requestRange', {'start': start, 'count': count}),
      contextMenuBuilder: _contextMenuBuilder(
        id,
        'listItem',
        hasContextMenuProvider,
      ),
    );
  }

  Widget _buildTreeView(
    BuildContext context,
    Map<String, dynamic> props,
    bool hasContextMenuProvider,
    bool hasContextMenuEvent,
  ) {
    final id = _id(props);
    final nodes = _entryList(props['nodes']);
    if (nodes.isEmpty) return _emptyState(context, props);
    // The index is host-local, so expansion survives plugin snapshots and a
    // patch splices rows instead of re-flattening the tree.
    final index = hostState.treeIndex(
      id,
      nodes,
      expanded: (props['expandedIds'] as List?)
          ?.map((e) => e.toString())
          .toSet(),
    );
    return PluginTreeView(
      key: hostState.stateKey<PluginTreeViewState>(id),
      index: index,
      selectedId: props['selectedId']?.toString(),
      indent: (props['indent'] as num?)?.toDouble() ?? 16,
      emptyLabel: props['emptyLabel']?.toString(),
      onSelect: (nodeId) => onEvent(id, 'select', {'nodeId': nodeId}),
      onActivate: (nodeId) => onEvent(id, 'activate', {'nodeId': nodeId}),
      onExpand: (nodeId) => onEvent(id, 'expand', {'nodeId': nodeId}),
      onCollapse: (nodeId) => onEvent(id, 'collapse', {'nodeId': nodeId}),
      onRequestChildren: (nodeId) =>
          onEvent(id, 'requestChildren', {'nodeId': nodeId}),
      onContextMenu: hasContextMenuEvent
          ? (nodeId, position) => onEvent(id, 'contextMenu', {
              'nodeId': nodeId,
              'x': position.dx,
              'y': position.dy,
            })
          : null,
      contextMenuBuilder: _contextMenuBuilder(
        id,
        'treeNode',
        hasContextMenuProvider,
      ),
    );
  }

  Widget _buildDataTable(
    BuildContext context,
    Map<String, dynamic> props,
    bool hasContextMenuProvider,
  ) {
    final id = _id(props);
    final rows = _entryList(props['rows']);
    // rowCount may exceed the loaded window; gaps arrive via requestRange.
    final declared = (props['rowCount'] as num?)?.toInt();
    final rowCount = declared != null && declared > rows.length
        ? declared
        : rows.length;
    return PluginDataTable(
      key: hostState.stateKey<PluginDataTableState>(id),
      columns: [
        for (final column in _entryList(props['columns']))
          PluginColumn.fromJson(column),
      ],
      rows: {for (var i = 0; i < rows.length; i++) i: rows[i]},
      rowCount: rowCount,
      rowHeight: (props['rowHeight'] as num?)?.toDouble() ?? 28,
      showHeader: props['showHeader'] != false,
      selectedId: props['selectedId']?.toString(),
      sortColumn: props['sortColumn']?.toString(),
      sortAscending: props['sortAscending'] != false,
      emptyLabel: props['emptyLabel']?.toString(),
      onSelect: (rowId) => onEvent(id, 'select', {'rowId': rowId}),
      onActivate: (rowId) => onEvent(id, 'activate', {'rowId': rowId}),
      onSort: (columnId) => onEvent(id, 'sort', {'columnId': columnId}),
      onRequestRange: (start, count) =>
          onEvent(id, 'requestRange', {'start': start, 'count': count}),
      contextMenuBuilder: _contextMenuBuilder(
        id,
        'tableRow',
        hasContextMenuProvider,
      ),
    );
  }

  Widget Function(Widget child, String targetId)? _contextMenuBuilder(
    String componentId,
    String targetType,
    bool enabled,
  ) {
    final request = onContextMenuRequest;
    if (!enabled || request == null) return null;
    return (child, targetId) => buildDynamicPluginContextMenu(
      child: child,
      targetId: targetId,
      targetType: targetType,
      menuProvider: () => request(componentId, targetId, targetType),
      onSelected: (menuId, payload) => onEvent(menuId, 'select', payload),
    );
  }

  Widget _buildPropertyGrid(
    BuildContext context,
    Map<String, dynamic> props,
    bool hasContextMenuProvider,
  ) {
    final id = _id(props);
    final entries = _entryList(props['entries']);
    if (entries.isEmpty) return _emptyState(context, props);
    final treeEntries = [
      for (final entry in entries)
        {
          ...entry,
          'label': entry['name']?.toString() ?? '',
          'hasChildren': entry['hasChildren'] == true,
        },
    ];
    final index = hostState.treeIndex('property-grid:$id', treeEntries);
    return PluginTreeView(
      key: hostState.stateKey<PluginTreeViewState>(id),
      index: index,
      selectedId: props['selectedId']?.toString(),
      indent: (props['indent'] as num?)?.toDouble() ?? 16,
      emptyLabel: props['emptyLabel']?.toString(),
      onSelect: (nodeId) => onEvent(id, 'select', {'nodeId': nodeId}),
      onActivate: (nodeId) => onEvent(id, 'activate', {'nodeId': nodeId}),
      onExpand: (nodeId) => onEvent(id, 'expand', {'nodeId': nodeId}),
      onCollapse: (nodeId) => onEvent(id, 'collapse', {'nodeId': nodeId}),
      onRequestChildren: (nodeId) =>
          onEvent(id, 'requestChildren', {'nodeId': nodeId}),
      contextMenuBuilder: _contextMenuBuilder(
        id,
        'propertyEntry',
        hasContextMenuProvider,
      ),
      contentBuilder: (context, model) {
        final entry = model.data;
        final type = entry['type']?.toString() ?? '';
        final representation =
            entry['repr']?.toString() ?? entry['value']?.toString() ?? '';
        final style = Theme.of(context).textTheme.bodySmall;
        return Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                model.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (type.isNotEmpty)
              Expanded(
                child: Text(
                  type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
            Expanded(
              flex: 3,
              child: Text(
                representation,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(
                  fontFamily: 'monospace',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyState(BuildContext context, Map<String, dynamic> props) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            props['emptyLabel']?.toString() ?? 'Nothing to show',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
}
