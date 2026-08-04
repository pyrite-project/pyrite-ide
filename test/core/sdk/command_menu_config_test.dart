import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/menu_resolver.dart';
import 'package:pyrite_ide/core/sdk/plugin_config_store.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';

PluginManifestV2 _uiManifest() {
  return PluginManifestV2(
    id: 'debug-enhanced',
    name: '调试加强',
    version: '1.6.0',
    type: PluginType.ui,
    platforms: const ['windows'],
    activationEvents: const [
      'onView:debug-enhanced.device-variables',
      'onCommand:debug-enhanced.refreshVariables',
    ],
    contributes: PluginContributions(
      navigationContainers: const [
        PluginNavigationContainerContribution(
          id: 'debug-enhanced',
          title: '调试加强',
        ),
      ],
      views: const [
        PluginViewContribution(
          id: 'debug-enhanced.device-variables',
          container: 'debug-enhanced',
          title: '设备变量',
          renderer: 'native.variableInspector',
        ),
      ],
      commands: [
        PluginCommandContribution(
          id: 'debug-enhanced.refreshVariables',
          title: '刷新设备变量',
          icon: PluginIconReference.material('refresh'),
          when: "device.connected",
        ),
      ],
      menus: const [
        PluginMenuContribution(
          location: 'view/title',
          view: 'debug-enhanced.device-variables',
          command: 'debug-enhanced.refreshVariables',
          group: 'navigation',
          order: 10,
        ),
        PluginMenuContribution(
          location: 'view/context',
          view: 'debug-enhanced.device-variables',
          command: 'debug-enhanced.refreshVariables',
          order: 10,
        ),
      ],
      configuration: const [
        PluginConfigurationContribution(
          id: 'debug-enhanced.showPrivate',
          title: '显示私有变量',
          type: 'boolean',
          defaultValue: false,
        ),
      ],
    ),
  );
}

void main() {
  group('MenuResolver', () {
    test('view/title items are visible and disabled by command when', () {
      final keys = ContextKeyService();
      final registry = ContributionRegistry(keys);
      registry.registerPlugin(_uiManifest());
      final resolver = MenuResolver(registry: registry, contextKeys: keys);

      keys.setValue('device.connected', false);
      final disabled = resolver.resolve(
        location: MenuResolver.viewTitle,
        viewId: 'debug-enhanced.device-variables',
      );
      expect(disabled, hasLength(1));
      expect(disabled.single.commandId, 'debug-enhanced.refreshVariables');
      expect(disabled.single.enabled, isFalse);

      keys.setValue('device.connected', true);
      final enabled = resolver.resolve(
        location: MenuResolver.viewTitle,
        viewId: 'debug-enhanced.device-variables',
      );
      expect(enabled.single.enabled, isTrue);
    });

    test('view/context resolves the same command for a view', () {
      final keys = ContextKeyService();
      final registry = ContributionRegistry(keys);
      registry.registerPlugin(_uiManifest());
      keys.setValue('device.connected', true);
      final resolver = MenuResolver(registry: registry, contextKeys: keys);
      final items = resolver.resolve(
        location: MenuResolver.viewContext,
        viewId: 'debug-enhanced.device-variables',
      );
      expect(items.map((item) => item.commandId), [
        'debug-enhanced.refreshVariables',
      ]);
    });
  });

  group('PluginConfigStore', () {
    test('defaults, persists, and emits configuration.changed', () async {
      final root = await Directory.systemTemp.createTemp('pyrite-config-');
      addTearDown(() => root.delete(recursive: true));
      final keys = ContextKeyService();
      final registry = ContributionRegistry(keys);
      registry.registerPlugin(_uiManifest());
      final events = <Map<String, dynamic>>[];
      final store = PluginConfigStore(
        registry: registry,
        emit: (topic, payload) {
          expect(topic, ConfigurationTopics.changed);
          events.add(payload);
        },
        dataDirectoryForPlugin: (pluginId) =>
            Directory('${root.path}/$pluginId/data').path,
      );

      expect(
        await store.get('debug-enhanced', 'debug-enhanced.showPrivate'),
        false,
      );
      await store.set('debug-enhanced', 'debug-enhanced.showPrivate', true);
      expect(
        await store.get('debug-enhanced', 'debug-enhanced.showPrivate'),
        true,
      );
      expect(events, [
        {
          'pluginId': 'debug-enhanced',
          'id': 'debug-enhanced.showPrivate',
          'value': true,
        },
      ]);

      final reloaded = PluginConfigStore(
        registry: registry,
        emit: (_, _) {},
        dataDirectoryForPlugin: (pluginId) =>
            Directory('${root.path}/$pluginId/data').path,
      );
      expect(
        await reloaded.get('debug-enhanced', 'debug-enhanced.showPrivate'),
        true,
      );
    });

    test('rejects values that do not match the declared type', () async {
      final root = await Directory.systemTemp.createTemp('pyrite-config-');
      addTearDown(() => root.delete(recursive: true));
      final registry = ContributionRegistry(ContextKeyService());
      registry.registerPlugin(_uiManifest());
      final store = PluginConfigStore(
        registry: registry,
        emit: (_, _) {},
        dataDirectoryForPlugin: (pluginId) =>
            Directory('${root.path}/$pluginId/data').path,
      );
      expect(
        () => store.set('debug-enhanced', 'debug-enhanced.showPrivate', 'yes'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
