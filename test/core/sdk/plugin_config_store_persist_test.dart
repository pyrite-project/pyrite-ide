import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_config_store.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';

PluginManifestV2 _manifest() {
  return PluginManifestV2(
    id: 'persist-check',
    name: 'Persist Check',
    version: '1.0.0',
    type: PluginType.service,
    platforms: const ['macos'],
    activationEvents: const [],
    contributes: PluginContributions(
      configuration: const [
        PluginConfigurationContribution(
          id: 'persist-check.threshold',
          title: 'Threshold',
          type: 'integer',
          defaultValue: 10,
        ),
      ],
    ),
  );
}

void main() {
  late Directory temp;
  late ContributionRegistry registry;

  PluginConfigStore newStore() => PluginConfigStore(
    registry: registry,
    emit: (_, _) {},
    dataDirectoryForPlugin: (pluginId) =>
        Directory('${temp.path}/$pluginId').path,
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pyrite-config-persist');
    registry = ContributionRegistry(ContextKeyService());
    registry.registerPlugin(_manifest());
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  group('set() persistence', () {
    test(
      'a successful set survives a fresh store over the same directory',
      () async {
        final store = newStore();
        await store.set('persist-check', 'persist-check.threshold', 42);

        final reloaded = await newStore().get(
          'persist-check',
          'persist-check.threshold',
        );
        expect(reloaded, 42);
      },
    );

    test('a failed persist rolls the in-memory value back', () async {
      final store = newStore();
      await store.set('persist-check', 'persist-check.threshold', 42);

      // Sabotage the persist target: replace the file with a directory so
      // writeAsString fails on every platform.
      final configPath = '${temp.path}/persist-check/configuration.json';
      File(configPath).deleteSync();
      Directory(configPath).createSync();

      await expectLater(
        store.set('persist-check', 'persist-check.threshold', 99),
        throwsA(isA<FileSystemException>()),
      );

      // Same instance: the rejected value is gone and the last persisted
      // value is back.
      expect(await store.get('persist-check', 'persist-check.threshold'), 42);
    });

    test(
      'a failed persist for a previously unset key leaves no stored entry on disk',
      () async {
        final store = newStore();
        Directory(
          '${temp.path}/persist-check/configuration.json',
        ).createSync(recursive: true);

        await expectLater(
          store.set('persist-check', 'persist-check.threshold', 99),
          throwsA(isA<FileSystemException>()),
        );

        // A fresh store sees the contribution default, not the rejected value.
        expect(
          await newStore().get('persist-check', 'persist-check.threshold'),
          10,
        );
      },
    );
  });
}
