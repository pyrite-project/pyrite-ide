import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/activation_manager.dart';
import 'package:pyrite_ide/core/sdk/types.dart';

Plugin _plugin({
  List<String> events = const ['onView:fixture.home'],
  String id = 'fixture',
  PluginStatus status = PluginStatus.usable,
}) => Plugin(
  id: id,
  name: 'Fixture',
  status: status,
  manifest: PluginManifestV2(
    id: id,
    name: 'Fixture',
    version: '1.0.0',
    type: PluginType.ui,
    activationEvents: events,
  ),
);

void main() {
  test('concurrent activation requests share one start operation', () async {
    final gate = Completer<bool>();
    var starts = 0;
    final manager = ActivationManagerNotifier(
      startPlugin: (_) {
        starts++;
        return gate.future;
      },
      stopPlugin: (_) async {},
    );
    final plugin = _plugin();

    final first = manager.activate(plugin, reason: 'onView:fixture.home');
    final second = manager.activate(plugin, reason: 'onView:fixture.home');
    expect(identical(first, second), isTrue);
    expect(starts, 1);
    gate.complete(true);

    expect(await first, isTrue);
    expect(manager.record(plugin.id)?.state, ActivationState.active);
    manager.dispose();
  });

  test('activation failure can be retried', () async {
    var starts = 0;
    final manager = ActivationManagerNotifier(
      startPlugin: (_) async => ++starts > 1,
      stopPlugin: (_) async {},
    );
    final plugin = _plugin();

    expect(
      await manager.activate(plugin, reason: 'onView:fixture.home'),
      isFalse,
    );
    expect(manager.record(plugin.id)?.state, ActivationState.failed);
    expect(
      await manager.activate(plugin, reason: 'onView:fixture.home'),
      isTrue,
    );
    expect(manager.record(plugin.id)?.state, ActivationState.active);
    expect(starts, 2);
    manager.dispose();
  });

  test('plugins without onStartup remain dormant', () async {
    var starts = 0;
    final manager = ActivationManagerNotifier(
      startPlugin: (_) async {
        starts++;
        return true;
      },
      stopPlugin: (_) async {},
    );
    await manager.activateOnStartup([
      _plugin(events: const ['onView:fixture.home']),
    ]);

    expect(starts, 0);
    expect(manager.record('fixture')?.state, ActivationState.enabled);
    manager.dispose();
  });

  test('onCommand activates only the plugins declaring that command', () async {
    final started = <String>[];
    final manager = ActivationManagerNotifier(
      startPlugin: (plugin) async {
        started.add(plugin.id);
        return true;
      },
      stopPlugin: (_) async {},
    );
    final plugins = [
      _plugin(id: 'owner', events: const ['onCommand:fixture.run']),
      _plugin(id: 'other', events: const ['onCommand:fixture.other']),
      _plugin(
        id: 'disabled',
        status: PluginStatus.disabled,
        events: const ['onCommand:fixture.run'],
      ),
    ];

    final activated = await manager.activateForCommand(plugins, 'fixture.run');

    expect(activated, ['owner']);
    expect(started, ['owner']);
    expect(manager.record('owner')?.state, ActivationState.active);
    expect(manager.record('other'), isNull);
    manager.dispose();
  });

  test('onLanguage activates every plugin bound to the language', () async {
    final started = <String>[];
    final manager = ActivationManagerNotifier(
      startPlugin: (plugin) async {
        started.add(plugin.id);
        return true;
      },
      stopPlugin: (_) async {},
    );
    final plugins = [
      _plugin(id: 'lint', events: const ['onLanguage:python']),
      _plugin(id: 'format', events: const ['onLanguage:python']),
      _plugin(id: 'dart-only', events: const ['onLanguage:dart']),
    ];

    final activated = await manager.activateForLanguage(plugins, 'python');

    expect(activated..sort(), ['format', 'lint']);
    expect(started.length, 2);
    manager.dispose();
  });

  test('deactivate waits for an in-flight activation', () async {
    final gate = Completer<bool>();
    final order = <String>[];
    final manager = ActivationManagerNotifier(
      startPlugin: (_) async {
        final result = await gate.future;
        order.add('start');
        return result;
      },
      stopPlugin: (_) async => order.add('stop'),
    );
    final plugin = _plugin();

    final activation = manager.activate(plugin, reason: 'onView:fixture.home');
    final deactivation = manager.deactivate(plugin);
    gate.complete(true);
    await Future.wait([activation, deactivation]);

    expect(order, ['start', 'stop']);
    expect(manager.record(plugin.id)?.state, ActivationState.enabled);
    manager.dispose();
  });

  test('concurrent deactivate calls share one stop operation', () async {
    var stops = 0;
    final manager = ActivationManagerNotifier(
      startPlugin: (_) async => true,
      stopPlugin: (_) async => stops++,
    );
    final plugin = _plugin();
    await manager.activate(plugin, reason: 'onView:fixture.home');

    final first = manager.deactivate(plugin);
    final second = manager.deactivate(plugin);
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);

    expect(stops, 1);
    manager.dispose();
  });

  test('shutdown waits for pending work before stopping everything', () async {
    final gate = Completer<bool>();
    var stopAllCalls = 0;
    final manager = ActivationManagerNotifier(
      startPlugin: (_) => gate.future,
      stopPlugin: (_) async {},
      stopAll: () async => stopAllCalls++,
    );
    final plugin = _plugin();

    final activation = manager.activate(plugin, reason: 'onView:fixture.home');
    final shutdown = manager.deactivateAllForShutdown();
    gate.complete(true);
    await Future.wait([activation, shutdown]);

    expect(stopAllCalls, 1);
    expect(manager.record(plugin.id)?.state, ActivationState.enabled);
    manager.dispose();
  });
}
