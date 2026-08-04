import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/core/sdk/view_route_stack.dart';

ViewInstanceId _instance(
  String instanceId, {
  String pluginId = 'p1',
  String sessionId = 's1',
  String viewId = 'outline',
}) => ViewInstanceId(
  pluginId: pluginId,
  sessionId: sessionId,
  viewId: viewId,
  instanceId: instanceId,
);

void main() {
  late ViewRouteStacks stacks;

  setUp(() => stacks = ViewRouteStacks());

  test('an untouched instance starts on an implicit root entry', () {
    final instance = _instance('sidebar');
    expect(stacks.current(instance).route, kViewRootRoute);
    expect(stacks.stackOf(instance), hasLength(1));
  });

  test('push adds an entry and carries its params', () {
    final instance = _instance('sidebar');
    stacks.push(instance, 'detail', {'id': 42});
    expect(stacks.current(instance).route, 'detail');
    expect(stacks.current(instance).params['id'], 42);
    expect(stacks.routesOf(instance), [kViewRootRoute, 'detail']);
  });

  test('the same view in two instances navigates independently', () {
    final sidebar = _instance('sidebar');
    final tab = _instance('tab');
    stacks.push(sidebar, 'detail', {'id': 1});
    stacks.push(sidebar, 'edit');
    expect(stacks.routesOf(sidebar), [kViewRootRoute, 'detail', 'edit']);
    // Same pluginId and viewId, different instance: untouched by the pushes.
    expect(stacks.routesOf(tab), [kViewRootRoute]);
    expect(stacks.current(tab).route, kViewRootRoute);
  });

  test('popping one instance leaves the other where it was', () {
    final sidebar = _instance('sidebar');
    final tab = _instance('tab');
    stacks.push(sidebar, 'detail');
    stacks.push(tab, 'settings');
    expect(stacks.pop(sidebar), isTrue);
    expect(stacks.current(sidebar).route, kViewRootRoute);
    expect(stacks.current(tab).route, 'settings');
  });

  test('pop at the root reports false and keeps the root entry', () {
    final instance = _instance('sidebar');
    expect(stacks.pop(instance), isFalse);
    expect(stacks.routesOf(instance), [kViewRootRoute]);
  });

  test('pop unwinds one entry at a time', () {
    final instance = _instance('sidebar');
    stacks.push(instance, 'a');
    stacks.push(instance, 'b');
    expect(stacks.pop(instance), isTrue);
    expect(stacks.current(instance).route, 'a');
    expect(stacks.pop(instance), isTrue);
    expect(stacks.current(instance).route, kViewRootRoute);
    expect(stacks.pop(instance), isFalse);
  });

  test('replace swaps the top entry without changing depth', () {
    final instance = _instance('sidebar');
    stacks.push(instance, 'detail');
    stacks.replace(instance, 'other', {'k': 'v'});
    expect(stacks.routesOf(instance), [kViewRootRoute, 'other']);
    expect(stacks.current(instance).params['k'], 'v');
    // Depth was preserved, so a pop still returns to the root.
    expect(stacks.pop(instance), isTrue);
    expect(stacks.current(instance).route, kViewRootRoute);
  });

  test('goto collapses the stack to a single entry', () {
    final instance = _instance('sidebar');
    stacks.push(instance, 'a');
    stacks.push(instance, 'b');
    stacks.goto(instance, 'fresh', {'n': 1});
    expect(stacks.routesOf(instance), ['fresh']);
    expect(stacks.current(instance).params['n'], 1);
    expect(stacks.pop(instance), isFalse);
  });

  test('clear resets one instance back to its implicit root', () {
    final instance = _instance('sidebar');
    stacks.push(instance, 'detail');
    stacks.clear(instance);
    expect(stacks.routesOf(instance), [kViewRootRoute]);
  });

  test('clearSession drops only that session\'s instances', () {
    final oldRun = _instance('sidebar', sessionId: 's1');
    final newRun = _instance('sidebar', sessionId: 's2');
    final otherPlugin = _instance('sidebar', pluginId: 'p2', sessionId: 's1');
    stacks.push(oldRun, 'a');
    stacks.push(newRun, 'b');
    stacks.push(otherPlugin, 'c');

    stacks.clearSession('p1', 's1');

    expect(stacks.routesOf(oldRun), [kViewRootRoute]);
    expect(stacks.current(newRun).route, 'b');
    expect(stacks.current(otherPlugin).route, 'c');
  });

  test('clearPlugin drops every session and view of that plugin', () {
    final a = _instance('sidebar', sessionId: 's1');
    final b = _instance('tab', sessionId: 's2', viewId: 'tree');
    final other = _instance('sidebar', pluginId: 'p2');
    stacks.push(a, 'a');
    stacks.push(b, 'b');
    stacks.push(other, 'c');

    stacks.clearPlugin('p1');

    expect(stacks.routesOf(a), [kViewRootRoute]);
    expect(stacks.routesOf(b), [kViewRootRoute]);
    expect(stacks.current(other).route, 'c');
  });

  test('two views of one plugin keep separate stacks', () {
    final outline = _instance('i1', viewId: 'outline');
    final tree = _instance('i1', viewId: 'tree');
    stacks.push(outline, 'detail');
    expect(stacks.routesOf(tree), [kViewRootRoute]);
  });

  test('stackOf exposes an unmodifiable view of the stack', () {
    final instance = _instance('sidebar');
    expect(
      () => stacks.stackOf(instance).add(const ViewRouteEntry(route: 'x')),
      throwsUnsupportedError,
    );
  });
}
