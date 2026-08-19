import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:pyrite_ide/core/services/persistence/plugin_persistence.dart';

class _FailOncePluginPersistence extends PluginPersistence {
  bool failNextSave = false;

  @override
  Future<void> save(List<Plugin> plugins) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('save failed');
    }
    await super.save(plugins);
  }
}

class _RecordingPluginRunManager extends PluginRunManagerNotifier {
  _RecordingPluginRunManager(super.ref, this.started);

  final List<Plugin> started;
  final List<Plugin> stopped = [];
  final Set<String> running = {};

  @override
  bool isRunning(String pluginId) => running.contains(pluginId);

  @override
  Future<void> start(Plugin plugin) async {
    started.add(plugin);
    running.add(plugin.id);
  }

  @override
  Future<void> runOnce(Plugin plugin) async {
    started.add(plugin);
  }

  @override
  Future<void> stop(Plugin plugin) async {
    stopped.add(plugin);
    running.remove(plugin.id);
  }
}

Future<File> _writePackage(
  Directory root, {
  String id = 'example',
  required String version,
  String type = 'ui',
  bool autoStart = false,
  bool includeEntryPoint = true,
  List<String> permissions = const ['ui.view', 'ui.navigate'],
  Map<String, String> files = const {},
  String? viewId,
}) async {
  final permissionValues = permissions.map((value) => '"$value"').join(', ');
  final effectiveViewId = viewId ?? '$id.main';
  final activationEvents = autoStart
      ? '"onStartup"'
      : type == 'ui'
      ? '"onView:$effectiveViewId"'
      : '';
  final contributions = type == 'ui'
      ? '''
[[contributes.navigation_containers]]
id = "$id"
title = "Example"
icon = { material = "extension_outlined" }

[[contributes.views]]
id = "$effectiveViewId"
container = "$id"
title = "Example"
renderer = "native.form"
'''
      : '';
  final archive = Archive()
    ..addFile(
      ArchiveFile.string('plugin.toml', '''
manifest_version = 2
id = "$id"
name = "Example"
version = "$version"
type = "$type"
protocol_version = 1
activation_events = [$activationEvents]
permissions = [$permissionValues]
platforms = ["windows"]
$contributions
'''),
    );
  if (includeEntryPoint) {
    archive.addFile(ArchiveFile.string('__main__.py', version));
  }
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }

  final zip = File(path.join(root.path, '$id-$version.pyrix'));
  await zip.writeAsBytes(ZipEncoder().encodeBytes(archive));
  return zip;
}

Future<File> _writeManifestFixturePackage(
  Directory root,
  String fixture,
) async {
  final manifest = await File(
    path.join('test', 'fixtures', 'manifest_v2', '$fixture.toml'),
  ).readAsString();
  final archive = Archive()
    ..addFile(ArchiveFile.string('plugin.toml', manifest))
    ..addFile(ArchiveFile.string('__main__.py', 'print("fixture")'));
  final zip = File(path.join(root.path, '$fixture.pyrix'));
  await zip.writeAsBytes(ZipEncoder().encodeBytes(archive));
  return zip;
}

PluginPersistedData _persistedPlugin({
  required String id,
  PluginType type = PluginType.service,
  String? viewId,
  List<String> permissions = const [],
  Map<String, List<String>>? grantedPermissions,
}) {
  final effectiveViewId = viewId ?? '$id.main';
  final manifest = PluginManifestV2(
    id: id,
    name: id,
    version: '1.0.0',
    type: type,
    activationEvents: type == PluginType.ui
        ? ['onView:$effectiveViewId']
        : const [],
    permissions: permissions,
    platforms: const ['windows'],
    contributes: type == PluginType.ui
        ? PluginContributions(
            navigationContainers: [
              PluginNavigationContainerContribution(id: id, title: id),
            ],
            views: [
              PluginViewContribution(
                id: effectiveViewId,
                container: id,
                title: id,
                renderer: 'native.form',
              ),
            ],
          )
        : const PluginContributions(),
  );
  final declared = manifest.permissionsByResource;
  return PluginPersistedData(
    id: id,
    name: id,
    version: manifest.version,
    type: type.name,
    declaredPermissions: declared,
    permissions: grantedPermissions ?? declared,
    platforms: manifest.platforms,
    status: PluginStatus.usable.name,
    manifest: manifest,
    rawManifest: 'manifest_version = 2\n',
  );
}

ProviderContainer _createContainer(
  Directory root,
  PluginPersistence persistence, {
  List<Plugin>? startedPlugins,
}) {
  final overrides = [
    pluginManagerProvider.overrideWith(
      (ref) => PluginManagerNotifier(
        ref,
        persistence: persistence,
        supportDirectory: () async => root,
      ),
    ),
  ];
  if (startedPlugins != null) {
    overrides.add(
      pluginRunManagerProvider.overrideWith(
        (ref) => _RecordingPluginRunManager(ref, startedPlugins),
      ),
    );
  }
  return ProviderContainer(overrides: overrides);
}

Directory _active(Directory root, String id) =>
    Directory(path.join(root.path, 'plugin', id));

Directory _replacement(Directory root, String id) =>
    Directory(path.join(root.path, 'plugin_updates', 'new', id));

File _pendingDeletion(Directory root, String id) => File(
  path.join(root.path, 'plugin_updates', 'pending_deletions', '$id.json'),
);

Directory _activeBackup(Directory root, String id) =>
    Directory(path.join(root.path, 'plugin_updates', 'active_backups', id));

File _removal(Directory root, String id) =>
    File(path.join(root.path, 'plugin_updates', 'removals', id));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late List<ProviderContainer> containers;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pyrite-plugin-');
    containers = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
  });

  tearDown(() async {
    for (final container in containers) {
      container.dispose();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await root.exists()) await root.delete(recursive: true);
  });

  ProviderContainer createContainer(
    PluginPersistence persistence, {
    List<Plugin>? startedPlugins,
  }) {
    final container = _createContainer(
      root,
      persistence,
      startedPlugins: startedPlugins,
    );
    containers.add(container);
    return container;
  }

  void closeContainer(ProviderContainer container) {
    container.dispose();
    containers.remove(container);
  }

  Future<ProviderContainer> coldStart({
    PluginPersistence? persistence,
    List<Plugin>? startedPlugins,
  }) async {
    final container = createContainer(
      persistence ?? PluginPersistence(),
      startedPlugins: startedPlugins,
    );
    final manager = container.read(pluginManagerProvider.notifier);
    final persisted = await PluginPersistence().load();
    if (persisted != null) manager.loadPersisted(persisted);
    await manager.applyPendingChanges();
    return container;
  }

  test('new plugin is installed immediately and persisted', () async {
    final container = createContainer(PluginPersistence());
    final manager = container.read(pluginManagerProvider.notifier);
    final package = await _writePackage(root, version: '1.0.0');

    final updatePending = await manager.install(package.path);

    expect(updatePending, isFalse);
    expect(
      File(
        path.join(_active(root, 'example').path, '__main__.py'),
      ).readAsStringSync(),
      '1.0.0',
    );
    expect(
      container.read(pluginManagerProvider)['example']?.status,
      PluginStatus.usable,
    );
    final persisted = (await PluginPersistence().load())?.single;
    expect(persisted?.version, '1.0.0');
    expect(persisted?.rawManifest, contains('manifest_version = 2'));
    expect(persisted?.manifest?.contributes.views.single.id, 'example.main');
  });

  test('install rejects invalid manifests with stable error codes', () async {
    final container = createContainer(PluginPersistence());
    final manager = container.read(pluginManagerProvider.notifier);
    const cases = {
      'contribution_conflict': PluginManifestErrorCode.contributionConflict,
      'invalid_schema': PluginManifestErrorCode.invalidSchema,
      'invalid_when': PluginManifestErrorCode.invalidWhen,
      'manifest_v1': PluginManifestErrorCode.unsupportedVersion,
      'missing_navigation': PluginManifestErrorCode.missingNavigationContainer,
      'missing_version': PluginManifestErrorCode.missingVersion,
      'rfw_renderer': PluginManifestErrorCode.rfwRendererUnsupported,
      'unknown_renderer': PluginManifestErrorCode.unknownRenderer,
    };

    for (final entry in cases.entries) {
      final package = await _writeManifestFixturePackage(root, entry.key);
      await expectLater(
        manager.install(package.path),
        throwsA(
          isA<PluginManifestException>().having(
            (error) => error.code,
            'code',
            entry.value,
          ),
        ),
        reason: entry.key,
      );
    }
    expect(container.read(pluginManagerProvider), isEmpty);
  });

  test('install rejects conflicts with an existing pending update', () async {
    final container = createContainer(PluginPersistence());
    final manager = container.read(pluginManagerProvider.notifier);
    final parentV1 = await _writePackage(root, id: 'nested', version: '1.0.0');
    final childV1 = await _writePackage(
      root,
      id: 'nested.child',
      version: '1.0.0',
    );
    expect(await manager.install(parentV1.path), isFalse);
    expect(await manager.install(childV1.path), isFalse);

    final parentV2 = await _writePackage(
      root,
      id: 'nested',
      version: '2.0.0',
      viewId: 'nested.child.shared',
    );
    final childV2 = await _writePackage(
      root,
      id: 'nested.child',
      version: '2.0.0',
      viewId: 'nested.child.shared',
    );
    expect(await manager.install(parentV2.path), isTrue);

    await expectLater(
      manager.install(childV2.path),
      throwsA(
        isA<PluginManifestException>().having(
          (error) => error.code,
          'code',
          PluginManifestErrorCode.contributionConflict,
        ),
      ),
    );
    expect(await _replacement(root, 'nested').exists(), isTrue);
    expect(await _replacement(root, 'nested.child').exists(), isFalse);
  });

  test('enabling legacy persisted metadata is explicitly rejected', () async {
    final container = createContainer(PluginPersistence());
    final manager = container.read(pluginManagerProvider.notifier);
    manager.loadPersisted([
      PluginPersistedData.fromJson({
        'id': 'legacy',
        'name': 'Legacy',
        'status': 'disabled',
      }),
    ]);

    await expectLater(
      manager.changeStatus('legacy', PluginStatus.usable),
      throwsA(
        isA<PluginManifestException>().having(
          (error) => error.code,
          'code',
          PluginManifestErrorCode.missingVersion,
        ),
      ),
    );
    expect(
      container.read(pluginManagerProvider)['legacy']?.status,
      PluginStatus.disabled,
    );
  });

  test('cold start disables every plugin in a global manifest conflict', () {
    final container = createContainer(PluginPersistence());
    final manager = container.read(pluginManagerProvider.notifier);
    manager.loadPersisted([
      _persistedPlugin(
        id: 'nested',
        type: PluginType.ui,
        viewId: 'nested.child.shared',
        permissions: const ['ui.view'],
      ),
      _persistedPlugin(
        id: 'nested.child',
        type: PluginType.ui,
        viewId: 'nested.child.shared',
        permissions: const ['ui.view'],
      ),
    ]);

    final restored = container.read(pluginManagerProvider);
    expect(
      restored.values.map((plugin) => plugin.status),
      everyElement(PluginStatus.disabled),
    );
    expect(
      restored.values.map((plugin) => plugin.manifestErrorCode),
      everyElement(PluginManifestErrorCode.contributionConflict),
    );
  });

  test('cold start disables case-insensitive plugin ID aliases', () async {
    final container = createContainer(PluginPersistence());
    final manager = container.read(pluginManagerProvider.notifier);
    manager.loadPersisted([
      _persistedPlugin(id: 'Alias'),
      _persistedPlugin(id: 'alias'),
    ]);

    final restored = container.read(pluginManagerProvider);
    expect(restored, hasLength(2));
    expect(
      restored.values.map((plugin) => plugin.status),
      everyElement(PluginStatus.disabled),
    );
    expect(
      restored.values.map((plugin) => plugin.manifestErrorCode),
      everyElement(PluginManifestErrorCode.contributionConflict),
    );
    await expectLater(
      manager.changeStatus('Alias', PluginStatus.usable),
      throwsA(
        isA<PluginManifestException>().having(
          (error) => error.code,
          'code',
          PluginManifestErrorCode.contributionConflict,
        ),
      ),
    );
  });

  test('persisted and updated grants cannot exceed manifest permissions', () {
    final container = createContainer(PluginPersistence());
    final manager = container.read(pluginManagerProvider.notifier);
    manager.loadPersisted([
      _persistedPlugin(
        id: 'restricted',
        permissions: const ['file.read'],
        grantedPermissions: const {
          'file': ['read', 'write'],
          'serial': ['write'],
        },
      ),
    ]);

    expect(
      container.read(pluginManagerProvider)['restricted']?.permissions,
      const {
        'file': ['read'],
      },
    );
    manager.updatePermissions('restricted', const {
      'file': ['read', 'write'],
      'serial': ['write'],
    });
    expect(
      container.read(pluginManagerProvider)['restricted']?.permissions,
      const {
        'file': ['read'],
      },
    );
  });

  test('cold start initializes grants for pre-grant-schema metadata', () {
    final persisted = _persistedPlugin(
      id: 'legacy-grants',
      permissions: const ['editor.read', 'runtime.inspect'],
    );
    final json = persisted.toJson()
      ..['permissions'] = <String, List<String>>{}
      ..remove('permissionGrantsInitialized');
    final container = createContainer(PluginPersistence());

    container.read(pluginManagerProvider.notifier).loadPersisted([
      PluginPersistedData.fromJson(json),
    ]);

    expect(
      container.read(pluginManagerProvider)['legacy-grants']?.permissions,
      const {
        'editor': ['read'],
        'runtime': ['inspect'],
      },
    );
  });

  test('cold start disables contributions from an invalid plugin', () {
    const contribution = DataContributionRecord(
      pluginId: 'legacy-data',
      pluginType: 'data',
      kind: DataContributionKeys.theme,
      contributionId: 'legacy-theme',
      payload: {},
    );
    final container = createContainer(PluginPersistence());
    container.read(dataContributionsProvider.notifier).state = [contribution];
    container.read(dataRegistryProvider).restoreContributions([contribution]);
    final manager = container.read(pluginManagerProvider.notifier);

    manager.loadPersisted([
      PluginPersistedData.fromJson({
        'id': 'legacy-data',
        'name': 'Legacy Data',
        'type': 'data',
        'status': 'usable',
      }),
    ]);

    expect(container.read(dataContributionsProvider).single.enabled, isFalse);
    expect(
      container
          .read(dataRegistryProvider)
          .getThemeById('legacy-data::legacy-theme'),
      isNull,
    );
  });

  test('plugin metadata file is replaced by a complete new snapshot', () async {
    final persistence = PluginPersistence();
    await persistence.save([
      const Plugin(id: 'example', name: 'Example', version: '1.0.0'),
    ]);
    final temporary = Directory(
      path.join(root.path, 'data', 'plugins.json.tmp'),
    );
    await temporary.create();

    await expectLater(
      persistence.save([
        const Plugin(id: 'example', name: 'Example', version: '2.0.0'),
      ]),
      throwsA(isA<FileSystemException>()),
    );
    expect((await persistence.load())?.single.version, '1.0.0');

    await temporary.delete();
    await persistence.save([
      const Plugin(id: 'example', name: 'Example', version: '2.0.0'),
    ]);

    expect((await persistence.load())?.single.version, '2.0.0');
    expect(
      File(path.join(root.path, 'data', 'plugins.json.tmp')).existsSync(),
      isFalse,
    );
  });

  test(
    'malformed plugin metadata is reported instead of treated as empty',
    () async {
      final dataRoot = await Directory(path.join(root.path, 'data')).create();
      await File(path.join(dataRoot.path, 'plugins.json')).writeAsString('{');

      await expectLater(PluginPersistence().load(), throwsFormatException);
    },
  );

  test('metadata-unavailable session cannot overwrite plugin data', () async {
    final persistence = PluginPersistence();
    await persistence.save([
      const Plugin(id: 'existing', name: 'Existing', version: '1.0.0'),
    ]);
    final container = createContainer(persistence);
    final manager = container.read(pluginManagerProvider.notifier);
    manager.markMetadataUnavailable();

    await expectLater(
      manager.install(
        (await _writePackage(root, id: 'new-plugin', version: '1.0.0')).path,
      ),
      throwsStateError,
    );
    await expectLater(manager.uninstall('existing'), throwsStateError);
    await manager.applyPendingChanges();
    await manager.persist();

    final persisted = await persistence.load();
    expect(persisted?.map((plugin) => plugin.id), ['existing']);
  });

  test(
    'existing update is applied by a new container before auto-start',
    () async {
      final firstStarts = <Plugin>[];
      final first = createContainer(
        PluginPersistence(),
        startedPlugins: firstStarts,
      );
      final manager = first.read(pluginManagerProvider.notifier);
      final runManager =
          first.read(pluginRunManagerProvider.notifier)
              as _RecordingPluginRunManager;
      final v1 = await _writePackage(
        root,
        version: '1.0.0',
        type: 'service',
        autoStart: true,
        files: {'stale.txt': 'old'},
      );
      await manager.install(v1.path);
      expect(firstStarts.map((plugin) => plugin.version), ['1.0.0']);

      final active = _active(root, 'example');
      await Directory(path.join(active.path, 'data')).create();
      await File(
        path.join(active.path, 'data', 'settings.json'),
      ).writeAsString('keep');
      await Directory(path.join(active.path, 'cache')).create();
      await File(
        path.join(active.path, 'cache', 'index.db'),
      ).writeAsString('keep');
      final v2 = await _writePackage(
        root,
        version: '2.0.0',
        type: 'service',
        autoStart: true,
        files: {'new.txt': 'new', 'data/default.json': 'default'},
      );
      final runningMetadata = first.read(pluginManagerProvider)['example'];

      expect(await manager.install(v2.path), isTrue);
      expect(
        first.read(pluginManagerProvider)['example']?.status,
        PluginStatus.usable,
      );
      await manager.persist();
      expect(
        (await PluginPersistence().load())?.single.status,
        PluginStatus.usable.name,
      );
      expect(firstStarts.map((plugin) => plugin.version), ['1.0.0', '2.0.0']);
      expect(runManager.stopped.map((plugin) => plugin.version), ['1.0.0']);
      expect(
        File(path.join(active.path, '__main__.py')).readAsStringSync(),
        '1.0.0',
      );
      expect(first.read(pluginManagerProvider)['example']?.version, '2.0.0');
      expect(
        File(
          path.join(_replacement(root, 'example').path, '__main__.py'),
        ).readAsStringSync(),
        '2.0.0',
      );
      expect(await _pendingDeletion(root, 'example').exists(), isTrue);
      expect(
        identical(
          first.read(pluginManagerProvider)['example'],
          runningMetadata,
        ),
        isFalse,
      );
      closeContainer(first);

      final secondStarts = <Plugin>[];
      final second = await coldStart(startedPlugins: secondStarts);
      await second.read(pluginManagerProvider.notifier).autoStart();

      expect(secondStarts.map((plugin) => plugin.version), ['2.0.0']);
      expect(
        File(path.join(active.path, '__main__.py')).readAsStringSync(),
        '2.0.0',
      );
      expect(File(path.join(active.path, 'stale.txt')).existsSync(), isFalse);
      expect(File(path.join(active.path, 'new.txt')).readAsStringSync(), 'new');
      expect(
        File(
          path.join(active.path, 'data', 'settings.json'),
        ).readAsStringSync(),
        'keep',
      );
      expect(
        File(path.join(active.path, 'data', 'default.json')).readAsStringSync(),
        'default',
      );
      expect(
        File(path.join(active.path, 'cache', 'index.db')).readAsStringSync(),
        'keep',
      );
      expect(await _replacement(root, 'example').exists(), isFalse);
      expect(await _activeBackup(root, 'example').exists(), isFalse);
      expect(second.read(pluginManagerProvider)['example']?.version, '2.0.0');
      closeContainer(second);

      final thirdStarts = <Plugin>[];
      final third = await coldStart(startedPlugins: thirdStarts);
      await third.read(pluginManagerProvider.notifier).autoStart();
      expect(thirdStarts.map((plugin) => plugin.version), ['2.0.0']);
      expect(third.read(pluginManagerProvider)['example']?.version, '2.0.0');
    },
  );

  test(
    'persisted plugin without Manifest v2 is disabled on cold start',
    () async {
      await PluginPersistence().save([
        const Plugin(
          id: 'example',
          name: 'Example',
          version: '1.0.0',
          status: PluginStatus.installing,
        ),
      ]);

      final container = await coldStart();

      expect(
        container.read(pluginManagerProvider)['example']?.status,
        PluginStatus.disabled,
      );
      expect(
        container.read(pluginManagerProvider)['example']?.manifestErrorCode,
        PluginManifestErrorCode.missingVersion,
      );
    },
  );

  test(
    'invalid update preserves active plugin and previous pending update',
    () async {
      final container = createContainer(PluginPersistence());
      final manager = container.read(pluginManagerProvider.notifier);
      await manager.install((await _writePackage(root, version: '1.0.0')).path);
      await manager.install((await _writePackage(root, version: '2.0.0')).path);
      final invalid = await _writePackage(
        root,
        version: '3.0.0',
        includeEntryPoint: false,
      );

      await expectLater(manager.install(invalid.path), throwsFormatException);

      expect(
        File(
          path.join(_active(root, 'example').path, '__main__.py'),
        ).readAsStringSync(),
        '1.0.0',
      );
      expect(
        File(
          path.join(_replacement(root, 'example').path, '__main__.py'),
        ).readAsStringSync(),
        '2.0.0',
      );
      expect(
        Directory(path.join(root.path, 'plugin_updates', 'staging')).listSync(),
        isEmpty,
      );
    },
  );

  test(
    'new valid update completely replaces previous pending update',
    () async {
      final container = createContainer(PluginPersistence());
      final manager = container.read(pluginManagerProvider.notifier);
      await manager.install((await _writePackage(root, version: '1.0.0')).path);
      await manager.install(
        (await _writePackage(
          root,
          version: '2.0.0',
          files: {'v2-only.txt': 'old'},
        )).path,
      );

      await manager.install(
        (await _writePackage(
          root,
          version: '3.0.0',
          files: {'v3-only.txt': 'new'},
        )).path,
      );

      final pending = _replacement(root, 'example');
      expect(
        File(path.join(pending.path, '__main__.py')).readAsStringSync(),
        '3.0.0',
      );
      expect(
        File(path.join(pending.path, 'v2-only.txt')).existsSync(),
        isFalse,
      );
      expect(File(path.join(pending.path, 'v3-only.txt')).existsSync(), isTrue);
    },
  );

  test('failed update staging restores the running plugin status', () async {
    final container = createContainer(PluginPersistence());
    final manager = container.read(pluginManagerProvider.notifier);
    await manager.install((await _writePackage(root, version: '1.0.0')).path);
    final pendingBlocker = File(
      path.join(root.path, 'plugin_updates', 'new', 'example'),
    );
    await pendingBlocker.parent.create(recursive: true);
    await pendingBlocker.writeAsString('block pending directory');

    await expectLater(
      manager.install((await _writePackage(root, version: '2.0.0')).path),
      throwsA(isA<FileSystemException>()),
    );

    expect(
      container.read(pluginManagerProvider)['example']?.status,
      PluginStatus.usable,
    );
    await manager.persist();
    expect(
      (await PluginPersistence().load())?.single.status,
      PluginStatus.usable.name,
    );
  });

  test(
    'metadata failure leaves active and pending packages retryable',
    () async {
      final first = createContainer(PluginPersistence());
      final manager = first.read(pluginManagerProvider.notifier);
      await manager.install((await _writePackage(root, version: '1.0.0')).path);
      await manager.install((await _writePackage(root, version: '2.0.0')).path);
      closeContainer(first);

      final failingPersistence = _FailOncePluginPersistence()
        ..failNextSave = true;
      final second = await coldStart(persistence: failingPersistence);

      expect(
        File(
          path.join(_active(root, 'example').path, '__main__.py'),
        ).readAsStringSync(),
        '1.0.0',
      );
      expect(
        File(
          path.join(_replacement(root, 'example').path, '__main__.py'),
        ).readAsStringSync(),
        '2.0.0',
      );
      expect(second.read(pluginManagerProvider)['example']?.version, '2.0.0');

      failingPersistence.failNextSave = true;
      await expectLater(
        second.read(pluginManagerProvider.notifier).persist(),
        completes,
      );
      closeContainer(second);

      final third = await coldStart();
      expect(third.read(pluginManagerProvider)['example']?.version, '2.0.0');
      expect(await _replacement(root, 'example').exists(), isFalse);
    },
  );

  test('activation failure restores metadata for the active package', () async {
    final first = createContainer(PluginPersistence());
    final manager = first.read(pluginManagerProvider.notifier);
    await manager.install((await _writePackage(root, version: '1.0.0')).path);
    await manager.changeStatus('example', PluginStatus.disabled);
    await manager.persist();
    await manager.install((await _writePackage(root, version: '2.0.0')).path);
    closeContainer(first);

    final trash = File(path.join(root.path, 'plugin_updates', 'trash'));
    await trash.writeAsString('block trash directory');
    final second = await coldStart();

    final plugin = second.read(pluginManagerProvider)['example'];
    expect(plugin?.version, '1.0.0');
    expect(plugin?.status, PluginStatus.disabled);
    await second.read(pluginManagerProvider.notifier).persist();
    final persisted = (await PluginPersistence().load())?.single;
    expect(persisted?.version, '1.0.0');
    expect(persisted?.status, PluginStatus.disabled.name);
    expect(
      File(
        path.join(_active(root, 'example').path, '__main__.py'),
      ).readAsStringSync(),
      '1.0.0',
    );
    expect(
      File(
        path.join(_replacement(root, 'example').path, '__main__.py'),
      ).readAsStringSync(),
      '2.0.0',
    );
    closeContainer(second);

    await trash.delete();
    final third = await coldStart();
    expect(third.read(pluginManagerProvider)['example']?.version, '2.0.0');
    expect(
      third.read(pluginManagerProvider)['example']?.status,
      PluginStatus.disabled,
    );
    expect(await _replacement(root, 'example').exists(), isFalse);
  });

  test('first install rolls back when metadata cannot be saved', () async {
    final persistence = _FailOncePluginPersistence()..failNextSave = true;
    final container = createContainer(persistence);
    final manager = container.read(pluginManagerProvider.notifier);
    final package = await _writePackage(root, version: '1.0.0');

    await expectLater(manager.install(package.path), throwsStateError);

    expect(container.read(pluginManagerProvider), isEmpty);
    expect(await _active(root, 'example').exists(), isFalse);
    expect(await _replacement(root, 'example').exists(), isFalse);
  });

  test('first install activation failure preserves usable metadata', () async {
    final blocker = File(
      path.join(root.path, 'plugin_updates', 'active_backups'),
    );
    await blocker.parent.create(recursive: true);
    await blocker.writeAsString('block backup directory');
    final first = createContainer(PluginPersistence());
    final manager = first.read(pluginManagerProvider.notifier);

    await expectLater(
      manager.install((await _writePackage(root, version: '1.0.0')).path),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      first.read(pluginManagerProvider)['example']?.status,
      PluginStatus.installing,
    );
    await manager.persist();
    expect(
      (await PluginPersistence().load())?.single.status,
      PluginStatus.usable.name,
    );
    expect(await _replacement(root, 'example').exists(), isTrue);
    closeContainer(first);

    await blocker.delete();
    final second = await coldStart();
    expect(
      second.read(pluginManagerProvider)['example']?.status,
      PluginStatus.usable,
    );
    expect(await _replacement(root, 'example').exists(), isFalse);
  });

  test(
    'active backup without a swap is completed on the next cold start',
    () async {
      final first = createContainer(PluginPersistence());
      final manager = first.read(pluginManagerProvider.notifier);
      await manager.install(
        (await _writePackage(
          root,
          version: '1.0.0',
          files: {'old-only.txt': 'old'},
        )).path,
      );
      final active = _active(root, 'example');
      await Directory(path.join(active.path, 'data')).create();
      await File(
        path.join(active.path, 'data', 'settings.json'),
      ).writeAsString('keep');
      await manager.install((await _writePackage(root, version: '2.0.0')).path);

      final pending = _replacement(root, 'example');
      final newMetadata = PluginTomlParser.parseFromDirectory(
        pending,
      ).toPlugin();
      await PluginPersistence().save([newMetadata]);
      final backup = _activeBackup(root, 'example');
      await backup.parent.create(recursive: true);
      await active.rename(backup.path);
      closeContainer(first);

      final second = await coldStart();

      expect(second.read(pluginManagerProvider)['example']?.version, '2.0.0');
      expect(
        File(
          path.join(active.path, 'data', 'settings.json'),
        ).readAsStringSync(),
        'keep',
      );
      expect(
        File(path.join(active.path, 'old-only.txt')).existsSync(),
        isFalse,
      );
      expect(await backup.exists(), isFalse);
    },
  );

  test('active recovery refuses an invalid pending manifest', () async {
    final first = createContainer(PluginPersistence());
    final manager = first.read(pluginManagerProvider.notifier);
    await manager.install((await _writePackage(root, version: '1.0.0')).path);
    await manager.install((await _writePackage(root, version: '2.0.0')).path);

    final active = _active(root, 'example');
    final pending = _replacement(root, 'example');
    final manifestFile = File(path.join(pending.path, 'plugin.toml'));
    await manifestFile.writeAsString(
      (await manifestFile.readAsString()).replaceFirst(
        'manifest_version = 2',
        'manifest_version = 1',
      ),
    );
    final backup = _activeBackup(root, 'example');
    await backup.parent.create(recursive: true);
    await active.rename(backup.path);
    closeContainer(first);

    final second = await coldStart();
    final plugin = second.read(pluginManagerProvider)['example'];
    expect(plugin?.status, PluginStatus.disabled);
    expect(
      plugin?.manifestErrorCode,
      PluginManifestErrorCode.unsupportedVersion,
    );
    expect(await active.exists(), isFalse);
    expect(await pending.exists(), isTrue);
    expect(await backup.exists(), isTrue);
  });

  test('install waits for an active backup to be recovered', () async {
    final container = createContainer(PluginPersistence());
    final manager = container.read(pluginManagerProvider.notifier);
    await manager.install((await _writePackage(root, version: '1.0.0')).path);
    await manager.install((await _writePackage(root, version: '2.0.0')).path);

    final active = _active(root, 'example');
    final backup = _activeBackup(root, 'example');
    await backup.parent.create(recursive: true);
    await active.rename(backup.path);
    await _replacement(root, 'example').rename(active.path);

    await expectLater(
      manager.install((await _writePackage(root, version: '3.0.0')).path),
      throwsStateError,
    );

    expect(await backup.exists(), isTrue);
    expect(
      Directory(path.join(root.path, 'plugin_updates', 'staging')).listSync(),
      isEmpty,
    );
  });

  test('active recovery block preserves visible plugin status', () async {
    final first = createContainer(PluginPersistence());
    final manager = first.read(pluginManagerProvider.notifier);
    await manager.install((await _writePackage(root, version: '1.0.0')).path);
    await manager.changeStatus('example', PluginStatus.disabled);
    await manager.persist();
    await manager.install((await _writePackage(root, version: '2.0.0')).path);

    final backup = _activeBackup(root, 'example');
    await backup.create(recursive: true);
    closeContainer(first);

    final second = await coldStart();
    final secondManager = second.read(pluginManagerProvider.notifier);
    expect(
      second.read(pluginManagerProvider)['example']?.status,
      PluginStatus.disabled,
    );
    await secondManager.persist();
    expect(
      (await PluginPersistence().load())?.single.status,
      PluginStatus.disabled.name,
    );

    await backup.delete(recursive: true);
    await secondManager.applyPendingChanges();
    expect(second.read(pluginManagerProvider)['example']?.version, '2.0.0');
    expect(
      second.read(pluginManagerProvider)['example']?.status,
      PluginStatus.disabled,
    );
  });

  test('pending backup is restored after an interrupted replacement', () async {
    final first = createContainer(PluginPersistence());
    final manager = first.read(pluginManagerProvider.notifier);
    await manager.install((await _writePackage(root, version: '1.0.0')).path);
    await manager.install((await _writePackage(root, version: '2.0.0')).path);
    final pending = _replacement(root, 'example');
    final backup = Directory(
      path.join(root.path, 'plugin_updates', 'new_backups', 'example'),
    );
    await backup.parent.create(recursive: true);
    await pending.rename(backup.path);
    closeContainer(first);

    final second = await coldStart();

    expect(second.read(pluginManagerProvider)['example']?.version, '2.0.0');
    expect(
      File(
        path.join(_active(root, 'example').path, '__main__.py'),
      ).readAsStringSync(),
      '2.0.0',
    );
    expect(await pending.exists(), isFalse);
    expect(await backup.exists(), isFalse);
  });

  test(
    'uncommitted replacement restores the version named by the marker',
    () async {
      final first = createContainer(PluginPersistence());
      final manager = first.read(pluginManagerProvider.notifier);
      await manager.install((await _writePackage(root, version: '1.0.0')).path);
      await manager.install((await _writePackage(root, version: '2.0.0')).path);

      final pending = _replacement(root, 'example');
      final backup = Directory(
        path.join(root.path, 'plugin_updates', 'new_backups', 'example'),
      );
      await backup.parent.create(recursive: true);
      await pending.rename(backup.path);
      await pending.create();
      final manifest = await File(
        path.join(backup.path, 'plugin.toml'),
      ).readAsString();
      await File(
        path.join(pending.path, 'plugin.toml'),
      ).writeAsString(manifest.replaceFirst('2.0.0', '3.0.0'));
      await File(path.join(pending.path, '__main__.py')).writeAsString('3.0.0');
      closeContainer(first);

      final second = await coldStart();

      expect(second.read(pluginManagerProvider)['example']?.version, '2.0.0');
      expect(
        File(
          path.join(_active(root, 'example').path, '__main__.py'),
        ).readAsStringSync(),
        '2.0.0',
      );
      expect(await backup.exists(), isFalse);
    },
  );

  test('concurrent installs are serialized without losing state', () async {
    final container = createContainer(PluginPersistence());
    final manager = container.read(pluginManagerProvider.notifier);
    final firstPackage = await _writePackage(
      root,
      id: 'first',
      version: '1.0.0',
    );
    final secondPackage = await _writePackage(
      root,
      id: 'second',
      version: '1.0.0',
    );

    final results = await Future.wait([
      manager.install(firstPackage.path),
      manager.install(secondPackage.path),
    ]);

    expect(results, [isFalse, isFalse]);
    expect(
      container.read(pluginManagerProvider).keys,
      containsAll(['first', 'second']),
    );
    expect(
      (await PluginPersistence().load())?.map((plugin) => plugin.id),
      containsAll(['first', 'second']),
    );
  });

  test(
    'update keeps state and grants only newly declared permissions',
    () async {
      final firstStarts = <Plugin>[];
      final first = createContainer(
        PluginPersistence(),
        startedPlugins: firstStarts,
      );
      final manager = first.read(pluginManagerProvider.notifier);
      await manager.install(
        (await _writePackage(
          root,
          version: '1.0.0',
          type: 'service',
          autoStart: true,
        )).path,
      );
      firstStarts.clear();
      await manager.install(
        (await _writePackage(
          root,
          version: '2.0.0',
          type: 'service',
          autoStart: true,
          permissions: ['ui.view', 'ui.navigate', 'file.read'],
        )).path,
      );
      await manager.changeStatus('example', PluginStatus.disabled);
      manager.updatePermissions('example', {
        'ui': ['view'],
      });
      await manager.persist();
      expect(firstStarts.map((plugin) => plugin.version), ['2.0.0']);
      closeContainer(first);

      final secondStarts = <Plugin>[];
      final second = await coldStart(startedPlugins: secondStarts);
      await second.read(pluginManagerProvider.notifier).autoStart();
      final updated = second.read(pluginManagerProvider)['example']!;

      expect(updated.version, '2.0.0');
      expect(updated.status, PluginStatus.disabled);
      expect(updated.permissions, {
        'ui': ['view'],
        'file': <String>[],
      });
      expect(secondStarts, isEmpty);
    },
  );

  test(
    'data plugin runs once only after an immediate or applied install',
    () async {
      final firstRuns = <Plugin>[];
      final first = createContainer(
        PluginPersistence(),
        startedPlugins: firstRuns,
      );
      final manager = first.read(pluginManagerProvider.notifier);
      await manager.install(
        (await _writePackage(root, version: '1.0.0', type: 'data')).path,
      );
      expect(firstRuns.map((plugin) => plugin.version), ['1.0.0']);
      firstRuns.clear();

      await manager.install(
        (await _writePackage(root, version: '2.0.0', type: 'data')).path,
      );
      expect(firstRuns.map((plugin) => plugin.version), ['2.0.0']);
      closeContainer(first);

      final secondRuns = <Plugin>[];
      final second = await coldStart(startedPlugins: secondRuns);
      await second.read(pluginManagerProvider.notifier).autoStart();
      expect(secondRuns.map((plugin) => plugin.version), ['2.0.0']);
    },
  );

  test(
    'package files win data conflicts while user-only entries survive',
    () async {
      final first = createContainer(PluginPersistence());
      final manager = first.read(pluginManagerProvider.notifier);
      await manager.install((await _writePackage(root, version: '1.0.0')).path);
      final active = _active(root, 'example');
      await Directory(
        path.join(active.path, 'data', 'conflict'),
      ).create(recursive: true);
      await File(
        path.join(active.path, 'data', 'conflict', 'old.txt'),
      ).writeAsString('old');
      await File(
        path.join(active.path, 'data', 'reverse'),
      ).writeAsString('old');
      await Directory(path.join(active.path, 'DATA')).create();
      await File(
        path.join(active.path, 'DATA', 'upper.txt'),
      ).writeAsString('keep');
      await Directory(path.join(active.path, 'Cache')).create();
      await File(
        path.join(active.path, 'Cache', 'upper.txt'),
      ).writeAsString('keep');
      await manager.install(
        (await _writePackage(
          root,
          version: '2.0.0',
          files: {
            'data/conflict': 'new-file',
            'data/reverse/new.txt': 'new-directory',
          },
        )).path,
      );
      closeContainer(first);

      final second = await coldStart();

      expect(second.read(pluginManagerProvider)['example']?.version, '2.0.0');
      expect(
        File(path.join(active.path, 'data', 'conflict')).readAsStringSync(),
        'new-file',
      );
      expect(
        File(
          path.join(active.path, 'data', 'reverse', 'new.txt'),
        ).readAsStringSync(),
        'new-directory',
      );
      expect(
        File(path.join(active.path, 'DATA', 'upper.txt')).readAsStringSync(),
        'keep',
      );
      expect(
        File(path.join(active.path, 'Cache', 'upper.txt')).readAsStringSync(),
        'keep',
      );
    },
  );

  test('unsafe plugin ID is rejected before touching support data', () async {
    final sentinel = File(path.join(root.path, 'sentinel'))
      ..writeAsStringSync('keep');
    final container = createContainer(PluginPersistence());
    final manager = container.read(pluginManagerProvider.notifier);
    final package = await _writePackage(root, id: '..', version: '1.0.0');

    await expectLater(manager.install(package.path), throwsFormatException);

    expect(sentinel.readAsStringSync(), 'keep');
    expect(container.read(pluginManagerProvider), isEmpty);
    expect(await Directory(path.join(root.path, 'plugin')).exists(), isFalse);
  });

  test('uppercase ID remains usable but a case alias is rejected', () async {
    final first = createContainer(PluginPersistence());
    final manager = first.read(pluginManagerProvider.notifier);
    await manager.install(
      (await _writePackage(root, id: 'Example', version: '1.0.0')).path,
    );

    await expectLater(
      manager.install(
        (await _writePackage(root, id: 'example', version: '1.0.0')).path,
      ),
      throwsFormatException,
    );
    expect(first.read(pluginManagerProvider).keys, ['Example']);
    expect(
      Directory(path.join(root.path, 'plugin_updates', 'staging')).listSync(),
      isEmpty,
    );

    expect(
      await manager.install(
        (await _writePackage(root, id: 'Example', version: '2.0.0')).path,
      ),
      isTrue,
    );
    closeContainer(first);

    final second = await coldStart();
    expect(second.read(pluginManagerProvider)['Example']?.version, '2.0.0');
  });

  test('dotted plugin IDs cannot collide with transaction backups', () async {
    final first = createContainer(PluginPersistence());
    final manager = first.read(pluginManagerProvider.notifier);
    await manager.install(
      (await _writePackage(root, id: 'foo.backup', version: '1.0.0')).path,
    );
    await manager.install(
      (await _writePackage(root, id: 'foo', version: '1.0.0')).path,
    );
    await manager.install(
      (await _writePackage(root, id: 'foo', version: '2.0.0')).path,
    );
    closeContainer(first);

    final second = await coldStart();

    expect(
      File(
        path.join(_active(root, 'foo.backup').path, '__main__.py'),
      ).readAsStringSync(),
      '1.0.0',
    );
    expect(
      File(
        path.join(_active(root, 'foo').path, '__main__.py'),
      ).readAsStringSync(),
      '2.0.0',
    );
    expect(
      second.read(pluginManagerProvider).keys,
      containsAll(['foo', 'foo.backup']),
    );
  });

  test(
    'uninstall cancels an update and cleans files and contributions on restart',
    () async {
      final first = createContainer(PluginPersistence());
      final manager = first.read(pluginManagerProvider.notifier);
      await manager.install((await _writePackage(root, version: '1.0.0')).path);
      await manager.install((await _writePackage(root, version: '2.0.0')).path);

      await manager.uninstall('example');

      expect(
        first.read(pluginManagerProvider)['example']?.status,
        PluginStatus.uninstalled,
      );
      expect(await _replacement(root, 'example').exists(), isFalse);
      expect(await _removal(root, 'example').exists(), isTrue);
      expect(await _removal(root, 'example').readAsString(), 'remove');
      expect(await _active(root, 'example').exists(), isTrue);
      closeContainer(first);

      const contribution = DataContributionRecord(
        pluginId: 'example',
        pluginType: 'data',
        kind: DataContributionKeys.theme,
        contributionId: 'stale-theme',
        payload: {},
      );
      final second = createContainer(PluginPersistence());
      second.read(dataContributionsProvider.notifier).state = [contribution];
      second.read(dataRegistryProvider).restoreContributions([contribution]);
      expect(
        second.read(dataRegistryProvider).getThemeById('example::stale-theme'),
        isNotNull,
      );
      final persisted = await PluginPersistence().load();
      second.read(pluginManagerProvider.notifier).loadPersisted(persisted!);
      await second.read(pluginManagerProvider.notifier).applyPendingChanges();

      expect(second.read(pluginManagerProvider), isNot(contains('example')));
      expect(await _active(root, 'example').exists(), isFalse);
      expect(await _removal(root, 'example').exists(), isFalse);
      expect(second.read(dataContributionsProvider), isEmpty);
      expect(
        second.read(dataRegistryProvider).getThemeById('example::stale-theme'),
        isNull,
      );
      closeContainer(second);

      final third = createContainer(PluginPersistence());
      third.read(dataContributionsProvider.notifier).state = [contribution];
      third.read(dataRegistryProvider).restoreContributions([contribution]);
      final current = await PluginPersistence().load();
      third.read(pluginManagerProvider.notifier).loadPersisted(current!);
      await third.read(pluginManagerProvider.notifier).applyPendingChanges();
      expect(third.read(dataContributionsProvider), isEmpty);
      expect(
        third.read(dataRegistryProvider).getThemeById('example::stale-theme'),
        isNull,
      );
    },
  );

  test('uninstall marker survives a metadata save failure', () async {
    final persistence = _FailOncePluginPersistence();
    final first = createContainer(persistence);
    final manager = first.read(pluginManagerProvider.notifier);
    await manager.install((await _writePackage(root, version: '1.0.0')).path);
    persistence.failNextSave = true;

    await manager.uninstall('example');

    expect(
      first.read(pluginManagerProvider)['example']?.status,
      PluginStatus.uninstalled,
    );
    expect(await _removal(root, 'example').readAsString(), 'remove');
    closeContainer(first);

    final secondStarts = <Plugin>[];
    final secondPersistence = _FailOncePluginPersistence()..failNextSave = true;
    final second = await coldStart(
      persistence: secondPersistence,
      startedPlugins: secondStarts,
    );
    await second.read(pluginManagerProvider.notifier).autoStart();

    expect(second.read(pluginManagerProvider), isNot(contains('example')));
    expect(secondStarts, isEmpty);
    expect(await _active(root, 'example').exists(), isTrue);
    expect(await _removal(root, 'example').exists(), isTrue);
    closeContainer(second);

    final third = await coldStart();
    expect(third.read(pluginManagerProvider), isNot(contains('example')));
    expect(await _active(root, 'example').exists(), isFalse);
    expect(await _removal(root, 'example').exists(), isFalse);
  });

  test('reinstall follows a durable removal marker', () async {
    final persistence = PluginPersistence();
    final first = createContainer(persistence);
    final manager = first.read(pluginManagerProvider.notifier);
    await manager.install((await _writePackage(root, version: '1.0.0')).path);
    await manager.uninstall('example');

    manager.loadPersisted([]);
    await persistence.save([]);
    await _active(root, 'example').delete(recursive: true);
    expect(
      await manager.install((await _writePackage(root, version: '2.0.0')).path),
      isTrue,
    );
    expect(await _removal(root, 'example').readAsString(), 'reinstall');
    closeContainer(first);

    final second = await coldStart();
    expect(second.read(pluginManagerProvider)['example']?.version, '2.0.0');
    expect(
      File(
        path.join(_active(root, 'example').path, '__main__.py'),
      ).readAsStringSync(),
      '2.0.0',
    );
    expect(await _removal(root, 'example').exists(), isFalse);
  });

  test('blocked reinstall keeps every transaction artifact', () async {
    final first = createContainer(PluginPersistence());
    final manager = first.read(pluginManagerProvider.notifier);
    await manager.install((await _writePackage(root, version: '1.0.0')).path);
    await manager.uninstall('example');
    await manager.install((await _writePackage(root, version: '2.0.0')).path);

    final backup = _activeBackup(root, 'example');
    await Directory(path.join(backup.path, 'data')).create(recursive: true);
    final userData = File(path.join(backup.path, 'data', 'settings.json'));
    await userData.writeAsString('keep');
    closeContainer(first);

    final starts = <Plugin>[];
    final second = await coldStart(startedPlugins: starts);
    await second.read(pluginManagerProvider.notifier).autoStart();

    expect(second.read(pluginManagerProvider), isNot(contains('example')));
    expect(starts, isEmpty);
    expect(await _active(root, 'example').exists(), isTrue);
    expect(await _replacement(root, 'example').exists(), isTrue);
    expect(await backup.exists(), isTrue);
    expect(await userData.readAsString(), 'keep');
    expect(await _removal(root, 'example').readAsString(), 'reinstall');
  });

  test(
    'reinstall after uninstall is visible immediately and applied on next start',
    () async {
      final first = createContainer(PluginPersistence());
      final manager = first.read(pluginManagerProvider.notifier);
      await manager.install((await _writePackage(root, version: '1.0.0')).path);
      await manager.uninstall('example');

      expect(
        await manager.install(
          (await _writePackage(root, version: '2.0.0')).path,
        ),
        isTrue,
      );
      expect(
        first.read(pluginManagerProvider)['example']?.status,
        PluginStatus.usable,
      );
      expect(
        first.read(contributionRegistryProvider).pluginIds,
        contains('example'),
      );
      expect(await _removal(root, 'example').readAsString(), 'reinstall');
      expect(await _replacement(root, 'example').exists(), isTrue);
      expect(await _pendingDeletion(root, 'example').exists(), isTrue);
      closeContainer(first);

      final second = await coldStart();

      expect(
        File(
          path.join(_active(root, 'example').path, '__main__.py'),
        ).readAsStringSync(),
        '2.0.0',
      );
      expect(
        second.read(pluginManagerProvider)['example']?.status,
        PluginStatus.usable,
      );
      expect(await _removal(root, 'example').exists(), isFalse);
    },
  );

  test(
    'status and uninstall changes remove host contributions immediately',
    () async {
      final container = createContainer(PluginPersistence());
      final manager = container.read(pluginManagerProvider.notifier);
      manager.loadPersisted([
        _persistedPlugin(id: 'example', type: PluginType.ui),
      ]);
      final registry = container.read(contributionRegistryProvider);

      expect(registry.pluginIds, contains('example'));
      await manager.changeStatus('example', PluginStatus.disabled);
      expect(registry.pluginIds, isEmpty);
      await manager.changeStatus('example', PluginStatus.usable);
      expect(registry.pluginIds, contains('example'));
      await manager.uninstall('example');
      expect(registry.pluginIds, isEmpty);
    },
  );
}
