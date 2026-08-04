import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';

/// The route every view instance starts on before a plugin navigates anywhere.
const String kViewRootRoute = 'home';

/// One entry on a view instance's route stack.
class ViewRouteEntry {
  const ViewRouteEntry({required this.route, this.params = const {}});

  final String route;
  final Map<String, dynamic> params;

  Map<String, dynamic> toJson() => {'route': route, 'params': params};

  @override
  bool operator ==(Object other) =>
      other is ViewRouteEntry &&
      other.route == route &&
      _sameParams(other.params, params);

  @override
  int get hashCode => route.hashCode;

  static bool _sameParams(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() => 'ViewRouteEntry($route, $params)';
}

/// Per-view-instance navigation stacks.
///
/// Routing is scoped to a [ViewInstanceId], not to a plugin: the same view
/// opened in the sidebar and as a tab are separate instances and must navigate
/// independently, so pushing in one cannot move the other.
///
/// Every instance has an implicit root entry ([kViewRootRoute]) created on first
/// access, which is why [pop] on a fresh stack is a no-op rather than an error.
class ViewRouteStacks {
  final Map<String, List<ViewRouteEntry>> _stacks = {};

  /// Kept alongside the stacks so session/plugin scoping compares real fields
  /// instead of parsing [ViewInstanceId.key].
  final Map<String, ViewInstanceId> _instances = {};

  /// How many instances have a stack allocated so far.
  int get length => _stacks.length;

  List<ViewRouteEntry> _stack(ViewInstanceId instance) {
    _instances[instance.key] ??= instance;
    return _stacks[instance.key] ??= [
      const ViewRouteEntry(route: kViewRootRoute),
    ];
  }

  /// The instance's current (top) entry.
  ViewRouteEntry current(ViewInstanceId instance) => _stack(instance).last;

  /// The instance's full stack, root first.
  List<ViewRouteEntry> stackOf(ViewInstanceId instance) =>
      List.unmodifiable(_stack(instance));

  /// Route names only, root first, as sent on the wire.
  List<String> routesOf(ViewInstanceId instance) => [
    for (final entry in _stack(instance)) entry.route,
  ];

  ViewRouteEntry push(
    ViewInstanceId instance,
    String route, [
    Map<String, dynamic>? params,
  ]) {
    final entry = ViewRouteEntry(route: route, params: params ?? const {});
    _stack(instance).add(entry);
    return entry;
  }

  /// Pops the top entry; false when only the root remains, which is left alone.
  bool pop(ViewInstanceId instance) {
    final stack = _stack(instance);
    if (stack.length <= 1) return false;
    stack.removeLast();
    return true;
  }

  /// Swaps the top entry, keeping the depth so a later [pop] still returns
  /// where it would have before.
  ViewRouteEntry replace(
    ViewInstanceId instance,
    String route, [
    Map<String, dynamic>? params,
  ]) {
    final entry = ViewRouteEntry(route: route, params: params ?? const {});
    final stack = _stack(instance);
    stack[stack.length - 1] = entry;
    return entry;
  }

  /// Collapses the history to [route] alone, so the instance can no longer pop
  /// back into a stale flow.
  ViewRouteEntry goto(
    ViewInstanceId instance,
    String route, [
    Map<String, dynamic>? params,
  ]) {
    final entry = ViewRouteEntry(route: route, params: params ?? const {});
    _stack(instance);
    _stacks[instance.key] = [entry];
    return entry;
  }

  /// Drops one instance's history; the next access starts at the root again.
  void clear(ViewInstanceId instance) {
    _stacks.remove(instance.key);
    _instances.remove(instance.key);
  }

  /// Drops the history of every instance in a stopped plugin session.
  void clearSession(String pluginId, String sessionId) => _removeWhere(
    (instance) =>
        instance.pluginId == pluginId && instance.sessionId == sessionId,
  );

  void clearPlugin(String pluginId) =>
      _removeWhere((instance) => instance.pluginId == pluginId);

  void _removeWhere(bool Function(ViewInstanceId) match) {
    final keys = [
      for (final entry in _instances.entries)
        if (match(entry.value)) entry.key,
    ];
    for (final key in keys) {
      _stacks.remove(key);
      _instances.remove(key);
    }
  }

  void clearAll() {
    _stacks.clear();
    _instances.clear();
  }
}

/// Host-wide view route stacks, shared across sessions.
///
/// Instance keys embed pluginId/sessionId, so a restarted session never inherits
/// a previous session's navigation history.
final Provider<ViewRouteStacks> viewRouteStacksProvider = Provider((ref) {
  final stacks = ViewRouteStacks();
  ref.onDispose(stacks.clearAll);
  return stacks;
});
