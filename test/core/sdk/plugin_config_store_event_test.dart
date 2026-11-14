import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_config_store.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';

/// Collects the events the bus delivers so tests can assert per-plugin routing.
class _Collector {
  final List<({String pluginId, DeliveredEvent event})> log = [];

  void deliver(
    String pluginId,
    String sessionId,
    int generation,
    DeliveredEvent event,
  ) => log.add((pluginId: pluginId, event: event));

  List<Map<String, dynamic>> payloadsFor(String pluginId, String topic) => [
    for (final entry in log)
      if (entry.pluginId == pluginId && entry.event.topic == topic)
        ...entry.event.payloads,
  ];
}

PluginManifestV2 _manifest(
  String id,
  List<PluginConfigurationContribution> configuration,
) {
  return PluginManifestV2(
    id: id,
    name: id,
    version: '1.0.0',
    type: PluginType.service,
    platforms: const ['macos'],
    activationEvents: const [],
    contributes: PluginContributions(configuration: configuration),
  );
}

void main() {
  late Directory temp;
  late ContributionRegistry registry;
  late PluginEventBus bus;
  late _Collector collector;
  late PluginConfigStore store;

  const changed = 'configuration.changed';

  void subscribe(String pluginId) {
    final result = bus.subscribe(
      subscriptionId: 'sub-$pluginId',
      pluginId: pluginId,
      sessionId: 'session-$pluginId',
      generation: 1,
      topicName: changed,
      pluginPermissions: const {},
    );
    expect(result.isOk, isTrue);
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pyrite-config-events');
    registry = ContributionRegistry(ContextKeyService());
    registry.registerPlugin(
      _manifest('owner', const [
        PluginConfigurationContribution(
          id: 'owner.theme',
          title: 'Theme',
          type: 'string',
          defaultValue: 'light',
        ),
        PluginConfigurationContribution(
          id: 'owner.api_key',
          title: 'API Key',
          type: 'password',
        ),
      ]),
    );
    registry.registerPlugin(
      _manifest('other', const [
        PluginConfigurationContribution(
          id: 'other.theme',
          title: 'Theme',
          type: 'string',
          defaultValue: 'light',
        ),
      ]),
    );
    collector = _Collector();
    bus = PluginEventBus(deliver: collector.deliver);
    store = PluginConfigStore(
      registry: registry,
      emit: bus.emit,
      dataDirectoryForPlugin: (pluginId) =>
          Directory('${temp.path}/$pluginId').path,
    );
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  group('configuration.changed audience', () {
    test('another plugin never receives the change', () async {
      subscribe('other');
      subscribe('owner');

      await store.set('owner', 'owner.theme', 'dark');

      expect(collector.payloadsFor('other', changed), isEmpty);
      expect(collector.payloadsFor('owner', changed), [
        {'pluginId': 'owner', 'id': 'owner.theme', 'value': 'dark'},
      ]);
    });

    test('the owner still gets its own change notification', () async {
      subscribe('owner');

      await store.set('owner', 'owner.theme', 'dark');

      expect(collector.payloadsFor('owner', changed), hasLength(1));
    });

    test(
      'replayLatest does not hand a late subscriber another plugin value',
      () async {
        await store.set('owner', 'owner.theme', 'dark');

        subscribe('other');

        expect(collector.payloadsFor('other', changed), isEmpty);
      },
    );

    test('replayLatest keeps one retained event per owning plugin', () async {
      await store.set('owner', 'owner.theme', 'dark');
      await store.set('other', 'other.theme', 'solarized');

      subscribe('owner');

      expect(collector.payloadsFor('owner', changed), [
        {'pluginId': 'owner', 'id': 'owner.theme', 'value': 'dark'},
      ]);
    });
  });

  group('password change notifications', () {
    test('the event never carries the password value', () async {
      subscribe('owner');

      await store.set('owner', 'owner.api_key', 'sk-live-secret');

      final payloads = collector.payloadsFor('owner', changed);
      expect(payloads, hasLength(1));
      expect(payloads.single, isNot(contains('value')));
      expect(payloads.single['redacted'], isTrue);
      expect(jsonEncode(payloads), isNot(contains('sk-live-secret')));
    });

    test('replayLatest never leaks a password to another plugin', () async {
      await store.set('owner', 'owner.api_key', 'sk-live-secret');

      subscribe('other');

      expect(collector.payloadsFor('other', changed), isEmpty);
    });

    test(
      'replayLatest gives the owner only the redacted notification',
      () async {
        await store.set('owner', 'owner.api_key', 'sk-live-secret');

        subscribe('owner');

        final payloads = collector.payloadsFor('owner', changed);
        expect(payloads, hasLength(1));
        expect(payloads.single, isNot(contains('value')));
        expect(payloads.single['redacted'], isTrue);
        expect(jsonEncode(payloads), isNot(contains('sk-live-secret')));
      },
    );
  });
}
