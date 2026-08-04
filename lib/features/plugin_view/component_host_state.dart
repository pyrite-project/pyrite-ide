import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pyrite_ide/core/sdk/component_method_registry.dart';
import 'package:pyrite_ide/core/sdk/tree_index.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';

typedef ComponentMethodHandler =
    Future<Object?> Function(String method, Map<String, dynamic> arguments);

/// Host-local edit and imperative-controller state for one plugin view.
class ComponentHostState implements ComponentMethodHostEntry {
  ComponentHostState({
    required this.instance,
    this.onChanged,
    this.debounce = const Duration(milliseconds: 200),
  });

  @override
  ViewInstanceId instance;
  final VoidCallback? onChanged;
  final Duration debounce;

  final Map<String, TextEditingController> _text = {};
  final Map<String, FocusNode> _focus = {};
  final Map<String, Timer> _debounces = {};
  final Map<String, Object?> _localValues = {};
  final Map<String, TreeIndex> _trees = {};
  final Map<String, String> _componentTypes = {};
  final Map<String, Map<String, dynamic>> _componentProps = {};
  final Map<String, ComponentMethodHandler> _methodHandlers = {};
  final Map<String, Map<String, dynamic>> _propOverrides = {};
  final Map<String, GlobalKey> _componentKeys = {};
  final Map<String, GlobalKey> _stateKeys = {};
  final Map<String, Type> _stateKeyTypes = {};
  final Map<String, Object> _controllers = {};
  final Set<String> _seenComponents = {};

  void beginBuild() => _seenComponents.clear();

  void endBuild() {
    final stale = _componentTypes.keys
        .where((id) => !_seenComponents.contains(id))
        .toList();
    for (final id in stale) {
      _componentTypes.remove(id);
      _componentProps.remove(id);
      _methodHandlers.remove(id);
      _propOverrides.remove(id);
      _componentKeys.remove(id);
      _stateKeys.remove(id);
      _stateKeyTypes.remove(id);
      final controller = _controllers.remove(id);
      if (controller is ChangeNotifier) controller.dispose();
    }
  }

  Map<String, dynamic> effectiveProps(Map<String, dynamic> props) {
    final id = props['id']?.toString();
    if (id == null || id.isEmpty) return props;
    final overrides = _propOverrides[id];
    return overrides == null ? props : {...props, ...overrides};
  }

  GlobalKey componentKey(String id) =>
      _componentKeys.putIfAbsent(id, GlobalKey.new);

  GlobalKey<T> stateKey<T extends State<StatefulWidget>>(String id) {
    if (_stateKeyTypes[id] != T) {
      _stateKeys[id] = GlobalKey<T>();
      _stateKeyTypes[id] = T;
    }
    return _stateKeys[id]! as GlobalKey<T>;
  }

  T controller<T extends Object>(String id, T Function() create) =>
      _controllers.putIfAbsent(id, create) as T;

  void registerComponent(
    String id,
    String type,
    Map<String, dynamic> props, {
    ComponentMethodHandler? handler,
  }) {
    if (id.isEmpty) return;
    _seenComponents.add(id);
    _componentTypes[id] = type;
    _componentProps[id] = props;
    if (handler != null) _methodHandlers[id] = handler;
  }

  void setOverride(String id, String name, Object? value) {
    (_propOverrides[id] ??= {})[name] = value;
    onChanged?.call();
  }

  TreeIndex treeIndex(
    String id,
    List<Map<String, dynamic>> nodes, {
    Set<String>? expanded,
  }) {
    final existing = _trees[id];
    if (existing == null) {
      final index = TreeIndex()
        ..reset([for (final node in nodes) _toModel(node)], expanded: expanded);
      _trees[id] = index;
      return index;
    }
    _reconcile(existing, nodes);
    return existing;
  }

  void _reconcile(TreeIndex index, List<Map<String, dynamic>> nodes) {
    final incoming = <String, Map<String, dynamic>>{
      for (final node in nodes)
        if (node['id'] != null) node['id'].toString(): node,
    };
    final sameShape =
        incoming.length == index.nodeCount &&
        incoming.keys.every(index.nodeById.containsKey);
    if (sameShape) {
      for (final entry in incoming.entries) {
        final model = index.node(entry.key)!;
        final label = entry.value['label']?.toString();
        if (label != null && label != model.label) model.label = label;
        model.icon = entry.value['icon']?.toString() ?? model.icon;
        model.hasChildren = entry.value['hasChildren'] == true;
        model.data = entry.value;
        final state = _childrenState(entry.value);
        if (state != null) model.childrenState = state;
      }
      return;
    }
    final expanded = Set<String>.from(index.expandedNodeIds);
    index.reset([
      for (final node in nodes) _toModel(node),
    ], expanded: expanded.where(incoming.containsKey).toSet());
  }

  TreeNodeModel _toModel(Map<String, dynamic> node) => TreeNodeModel(
    id: node['id']?.toString() ?? '',
    label: node['label']?.toString() ?? '',
    parentId: node['parentId']?.toString(),
    icon: node['icon']?.toString(),
    hasChildren: node['hasChildren'] == true,
    childrenState: _childrenState(node) ?? ChildrenState.loaded,
    data: node,
  );

  ChildrenState? _childrenState(Map<String, dynamic> node) =>
      switch (node['childrenState']?.toString()) {
        'unloaded' => ChildrenState.unloaded,
        'loading' => ChildrenState.loading,
        'error' => ChildrenState.error,
        'loaded' => ChildrenState.loaded,
        _ => null,
      };

  TextEditingController textController(String id, String value) {
    final existing = _text[id];
    if (existing == null) {
      final controller = TextEditingController(text: value);
      _text[id] = controller;
      return controller;
    }
    final focused = _focus[id]?.hasFocus ?? false;
    if (!focused && !_localValues.containsKey(id) && existing.text != value) {
      existing.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    return existing;
  }

  FocusNode focusNode(String id) => _focus.putIfAbsent(id, FocusNode.new);
  bool hasFocus(String id) => _focus[id]?.hasFocus ?? false;

  void recordEdit(String id, Object? value, void Function(Object? value) emit) {
    _localValues[id] = value;
    _debounces[id]?.cancel();
    _debounces[id] = Timer(debounce, () {
      _debounces.remove(id);
      emit(value);
    });
  }

  void flush(String id, Object? value, void Function(Object? value) emit) {
    _debounces.remove(id)?.cancel();
    _localValues[id] = value;
    emit(value);
  }

  Object? displayValue(String id, Object? pluginValue) =>
      _localValues.containsKey(id) ? _localValues[id] : pluginValue;

  void acknowledge(String id, Object? pluginValue) {
    if (_localValues.containsKey(id) && _localValues[id] == pluginValue) {
      _localValues.remove(id);
    }
  }

  @override
  Future<Object?> invokeComponentMethod(
    String componentId,
    String method,
    Map<String, dynamic> arguments,
  ) async {
    final type = _componentTypes[componentId];
    if (type == null) {
      throw ComponentMethodException(
        'component_not_found',
        'Component "$componentId" is not mounted',
      );
    }
    final props = _componentProps[componentId] ?? const {};
    switch (type) {
      case 'TextField':
        return _invokeText(
          textController(componentId, props['value']?.toString() ?? ''),
          componentId,
          method,
          arguments,
        );
      case 'NumberField':
        return _invokeNumber(componentId, props, method, arguments);
      case 'Tabs':
        return _invokeTabs(componentId, props, method, arguments);
      case 'Section':
        final expanded =
            !((_propOverrides[componentId]?['collapsed'] ??
                    props['collapsed']) ==
                true);
        if (method == 'is_expanded') return expanded;
        if (method == 'expand' || method == 'collapse' || method == 'toggle') {
          setOverride(
            componentId,
            'collapsed',
            method == 'expand'
                ? false
                : method == 'collapse'
                ? true
                : expanded,
          );
          return true;
        }
    }
    final handler = _methodHandlers[componentId];
    if (handler != null) return handler(method, arguments);
    throw ComponentMethodException(
      'method_not_supported',
      '$type does not support "$method"',
      details: {'componentType': type, 'method': method},
    );
  }

  Object? _invokeText(
    TextEditingController controller,
    String id,
    String method,
    Map<String, dynamic> arguments,
  ) {
    switch (method) {
      case 'get_text':
        return controller.text;
      case 'set_text':
        final text = arguments['text']?.toString() ?? '';
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        _localValues[id] = text;
        return true;
      case 'clear':
        controller.clear();
        _localValues[id] = '';
        return true;
      case 'select_all':
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
        return true;
      case 'get_selection':
        return {
          'start': controller.selection.start,
          'end': controller.selection.end,
        };
      case 'set_selection':
        final start = (arguments['start'] as num?)?.toInt() ?? 0;
        final end = (arguments['end'] as num?)?.toInt() ?? start;
        controller.selection = TextSelection(
          baseOffset: start.clamp(0, controller.text.length),
          extentOffset: end.clamp(0, controller.text.length),
        );
        return true;
      case 'replace_selection':
        final replacement = arguments['text']?.toString() ?? '';
        final selection = controller.selection;
        final start = selection.isValid
            ? selection.start
            : controller.text.length;
        final end = selection.isValid ? selection.end : controller.text.length;
        final text = controller.text.replaceRange(start, end, replacement);
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(
            offset: start + replacement.length,
          ),
        );
        _localValues[id] = text;
        return true;
      case 'request_focus':
        focusNode(id).requestFocus();
        return true;
      case 'unfocus':
        focusNode(id).unfocus();
        return true;
    }
    throw ComponentMethodException(
      'method_not_supported',
      'TextField does not support "$method"',
    );
  }

  Object? _invokeNumber(
    String id,
    Map<String, dynamic> props,
    String method,
    Map<String, dynamic> arguments,
  ) {
    final controller = textController(
      id,
      (props['value'] as num?)?.toString() ?? '',
    );
    if (method == 'get_value') return num.tryParse(controller.text);
    if (method == 'set_value') {
      final value = arguments['value'];
      if (value is! num) {
        throw const ComponentMethodException(
          'invalid_arguments',
          'set_value requires a numeric value',
        );
      }
      controller.text = value.toString();
      _localValues[id] = value;
      return true;
    }
    if (method == 'increment' || method == 'decrement') {
      final current = num.tryParse(controller.text) ?? 0;
      final step = (props['step'] as num?) ?? 1;
      var value = method == 'increment' ? current + step : current - step;
      final min = props['min'] as num?;
      final max = props['max'] as num?;
      if (min != null && value < min) value = min;
      if (max != null && value > max) value = max;
      controller.text = value.toString();
      _localValues[id] = value;
      return value;
    }
    return _invokeText(controller, id, method, arguments);
  }

  Object? _invokeTabs(
    String id,
    Map<String, dynamic> props,
    String method,
    Map<String, dynamic> arguments,
  ) {
    final ids =
        (props['_tabIds'] as List?)
            ?.map((value) => value.toString())
            .toList() ??
        const <String>[];
    final selected = (_propOverrides[id]?['selected'] ?? props['selected'])
        ?.toString();
    if (method == 'get_selected') {
      return selected ?? (ids.isEmpty ? null : ids.first);
    }
    if (method == 'select') {
      final target = arguments['id']?.toString();
      if (target == null || !ids.contains(target)) {
        throw const ComponentMethodException(
          'invalid_arguments',
          'Unknown tab id',
        );
      }
      setOverride(id, 'selected', target);
      return target;
    }
    if ((method == 'next' || method == 'previous') && ids.isNotEmpty) {
      var index = ids.indexOf(selected ?? ids.first);
      if (index < 0) index = 0;
      index = method == 'next'
          ? (index + 1) % ids.length
          : (index - 1 + ids.length) % ids.length;
      setOverride(id, 'selected', ids[index]);
      return ids[index];
    }
    throw ComponentMethodException(
      'method_not_supported',
      'Tabs does not support "$method"',
    );
  }

  void dispose() {
    for (final timer in _debounces.values) {
      timer.cancel();
    }
    for (final controller in _text.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    for (final tree in _trees.values) {
      tree.clear();
    }
    _debounces.clear();
    _text.clear();
    _focus.clear();
    _localValues.clear();
    _trees.clear();
    _componentTypes.clear();
    _componentProps.clear();
    _methodHandlers.clear();
    _propOverrides.clear();
    _componentKeys.clear();
    _stateKeys.clear();
    _stateKeyTypes.clear();
    for (final controller in _controllers.values) {
      if (controller is ChangeNotifier) controller.dispose();
    }
    _controllers.clear();
  }
}
