import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_config_store.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';

PluginManifestV2 _manifest() {
  return PluginManifestV2(
    id: 'secret-keeper',
    name: 'Secret Keeper',
    version: '1.0.0',
    type: PluginType.service,
    platforms: const ['macos'],
    activationEvents: const [],
    contributes: PluginContributions(
      configuration: const [
        PluginConfigurationContribution(
          id: 'secret-keeper.api_key',
          title: 'API Key',
          type: 'password',
        ),
      ],
    ),
  );
}

void main() {
  late Directory temp;
  late ContributionRegistry registry;
  late PluginConfigStore store;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pyrite-config-password');
    registry = ContributionRegistry(ContextKeyService());
    registry.registerPlugin(_manifest());
    store = PluginConfigStore(
      registry: registry,
      emit: (_, _) {},
      dataDirectoryForPlugin: (pluginId) =>
          Directory('${temp.path}/$pluginId').path,
    );
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  group('password configuration type', () {
    test('accepts a string and reports it through list()', () async {
      await store.set('secret-keeper', 'secret-keeper.api_key', 'sk-secret');

      final items = await store.list('secret-keeper');
      expect(items, hasLength(1));
      expect(items.single['value'], 'sk-secret');
    });

    test('rejects a non-string', () async {
      await expectLater(
        store.set('secret-keeper', 'secret-keeper.api_key', 42),
        throwsArgumentError,
      );
    });

    test('validation error never carries the rejected value', () async {
      Object? failure;
      try {
        // The rejected value deliberately embeds a secret-looking string so
        // the test fails loudly if the error ever echoes its argument.
        await store.set('secret-keeper', 'secret-keeper.api_key', {
          'token': 'sk-secret',
        });
      } catch (error) {
        failure = error;
      }
      expect(failure, isNotNull);
      expect('$failure', isNot(contains('sk-secret')));
    });
  });
}
