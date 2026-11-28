import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_config_store.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';

const String _pluginId = 'corrupt-check';
const String _configId = 'corrupt-check.threshold';
const Object _defaultValue = 10;

PluginManifestV2 _manifest() {
  return PluginManifestV2(
    id: _pluginId,
    name: 'Corrupt Check',
    version: '1.0.0',
    type: PluginType.service,
    platforms: const ['macos'],
    activationEvents: const [],
    contributes: PluginContributions(
      configuration: const [
        PluginConfigurationContribution(
          id: _configId,
          title: 'Threshold',
          type: 'integer',
          defaultValue: _defaultValue,
        ),
      ],
    ),
  );
}

typedef _LogRecord = ({
  String area,
  String message,
  Object? error,
  StackTrace? stack,
});

void main() {
  late Directory temp;
  late ContributionRegistry registry;

  File configFile() => File('${temp.path}/$_pluginId/configuration.json');

  PluginConfigStore newStore(
    List<_LogRecord> logs, {
    String Function(String pluginId)? dataDirectoryForPlugin,
  }) => PluginConfigStore(
    registry: registry,
    emit: (_, _) {},
    dataDirectoryForPlugin:
        dataDirectoryForPlugin ??
        (pluginId) => Directory('${temp.path}/$pluginId').path,
    logWriter: (area, message, {error, stack}) =>
        logs.add((area: area, message: message, error: error, stack: stack)),
  );

  void writeCorruptFile(String content) {
    configFile()
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pyrite-config-corrupt');
    registry = ContributionRegistry(ContextKeyService());
    registry.registerPlugin(_manifest());
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  group('corrupt configuration recovery', () {
    test('a valid configuration loads without logging', () async {
      configFile()
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({_configId: 42}));

      final logs = <_LogRecord>[];
      final store = newStore(logs);

      expect(await store.get(_pluginId, _configId), 42);
      expect(await store.list(_pluginId), hasLength(1));
      expect(logs, isEmpty);
    });

    test('a corrupt file is reported with its path and preserved', () async {
      const broken = '{"corrupt-check.threshold": 42,';
      writeCorruptFile(broken);

      final logs = <_LogRecord>[];
      final store = newStore(logs);

      // The in-memory fallback is the contribution default, not a crash.
      expect(await store.get(_pluginId, _configId), _defaultValue);

      expect(logs, hasLength(1));
      expect(logs.single.area, 'plugin-config');
      expect(logs.single.message, contains(configFile().path));
      expect(logs.single.error, isA<FormatException>());

      // The unreadable bytes must survive at a recoverable location instead
      // of being replaced by an empty configuration.
      final backup = File('${configFile().path}.corrupt');
      expect(backup.existsSync(), isTrue);
      expect(backup.readAsStringSync(), broken);
      expect(configFile().existsSync(), isFalse);
    });

    test(
      'set() after a corrupt load keeps the original bytes recoverable',
      () async {
        const broken = '[1, 2, 3]';
        writeCorruptFile(broken);

        final logs = <_LogRecord>[];
        final store = newStore(logs);
        await store.get(_pluginId, _configId);

        await store.set(_pluginId, _configId, 7);

        expect(jsonDecode(configFile().readAsStringSync()), {_configId: 7});
        expect(File('${configFile().path}.corrupt').readAsStringSync(), broken);

        // A fresh store reads the value the caller just wrote.
        expect(await newStore(logs).get(_pluginId, _configId), 7);
      },
    );

    test('a failed load is retried instead of being cached as empty', () async {
      const broken = 'not json at all';
      writeCorruptFile(broken);

      var attempts = 0;
      final logs = <_LogRecord>[];
      final store = newStore(
        logs,
        dataDirectoryForPlugin: (pluginId) {
          attempts++;
          // First access cannot even resolve the data directory.
          if (attempts == 1) {
            throw const FileSystemException('directory unavailable');
          }
          return Directory('${temp.path}/$pluginId').path;
        },
      );

      expect(await store.get(_pluginId, _configId), _defaultValue);
      expect(logs, hasLength(1));

      // The failed load was not cached: the next access retries, reaches the
      // corrupt file, and preserves it.
      expect(await store.get(_pluginId, _configId), _defaultValue);
      expect(attempts, 2);
      expect(logs, hasLength(2));
      expect(File('${configFile().path}.corrupt').readAsStringSync(), broken);
    });

    test(
      'set() refuses to overwrite when the file cannot be preserved',
      () async {
        final logs = <_LogRecord>[];
        final store = newStore(
          logs,
          dataDirectoryForPlugin: (_) =>
              throw const FileSystemException('directory unavailable'),
        );

        await expectLater(
          store.set(_pluginId, _configId, 7),
          throwsA(isA<StateError>()),
        );

        expect(logs, isNotEmpty);
        expect(logs.first.message, contains(_pluginId));
      },
    );
  });
}
