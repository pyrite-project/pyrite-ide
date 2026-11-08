import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_install_link.dart';
import 'package:pyrite_ide/core/sdk/plugin_install_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_client.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_ledger.dart';
import 'package:pyrite_ide/core/sdk/trusted_plugin_origins.dart';

const _intent = RegistryInstallIntent(
  pluginId: 'com.example.hello',
  version: '1.2.0',
  origin: 'https://forum.example',
);

PluginRegistryRelease _release({
  bool installable = true,
  PluginModeration moderation = const PluginModeration(level: 'none'),
}) => PluginRegistryRelease(
  pluginId: 'com.example.hello',
  name: 'Hello',
  version: '1.2.0',
  sha256: 'a' * 64,
  size: 4,
  type: 'ui',
  platforms: const ['windows'],
  permissions: const ['editor.read'],
  installable: installable,
  moderation: moderation,
);

class _FakeClient extends PluginRegistryClient {
  _FakeClient(this.release, {this.fetchError, this.downloadError});

  final PluginRegistryRelease release;
  final Object? fetchError;
  final Object? downloadError;
  int downloads = 0;

  @override
  Future<PluginRegistryRelease> fetchRelease(
    RegistryInstallIntent intent,
  ) async {
    if (fetchError != null) throw fetchError!;
    return release;
  }

  @override
  Future<File> downloadPackage(
    RegistryInstallIntent intent,
    PluginRegistryRelease release,
    Directory directory,
  ) async {
    downloads++;
    if (downloadError != null) throw downloadError!;
    await directory.create(recursive: true);
    return File('${directory.path}/package.pyrix')..writeAsStringSync('zip');
  }
}

class _FakeTrusted extends TrustedPluginOrigins {
  _FakeTrusted([Set<String> initial = const {}]) : origins = {...initial};

  final Set<String> origins;

  @override
  Future<Set<String>> load() async => {...origins};

  @override
  Future<void> trust(String origin) async => origins.add(origin);
}

void main() {
  late Directory temp;
  late Directory support;
  late List<String> installed;
  var ledgerCallbacks = 0;
  var installResult = false;
  Object? installError;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('install_controller_test');
    support = await Directory.systemTemp.createTemp('install_ledger_test');
    ledgerCallbacks = 0;
    installed = [];
    installResult = false;
    installError = null;
  });

  tearDown(() async {
    await temp.delete(recursive: true);
    await support.delete(recursive: true);
  });

  PluginInstallController build(
    _FakeClient client, {
    PluginInstallIntent intent = _intent,
    Set<String> trusted = const {'https://forum.example'},
    _FakeTrusted? store,
    PluginRegistryLedger? ledger,
  }) {
    return PluginInstallController(
      intent: intent,
      client: client,
      trustedOrigins: store ?? _FakeTrusted(trusted),
      installPackage: (packagePath) async {
        if (installError != null) throw installError!;
        installed.add(packagePath);
        return installResult;
      },
      ledger:
          ledger ?? PluginRegistryLedger(supportDirectory: () async => support),
      onRegistryInstalled: () => ledgerCallbacks++,
      downloadRoot: () async => temp,
    );
  }

  group('loading', () {
    test('becomes ready with the release and its trust state', () async {
      final controller = build(_FakeClient(_release()));

      await controller.load();

      expect(controller.state.phase, PluginInstallPhase.ready);
      expect(controller.state.release?.name, 'Hello');
      expect(controller.state.sourceTrusted, isTrue);
    });

    test('flags a site the user has not installed from before', () async {
      final controller = build(_FakeClient(_release()), trusted: {});

      await controller.load();

      expect(controller.state.sourceTrusted, isFalse);
    });

    test('fails with the registry error', () async {
      const error = PluginRegistryException(
        PluginRegistryErrorCode.unreachable,
        'offline',
      );
      final controller = build(_FakeClient(_release(), fetchError: error));

      await controller.load();

      expect(controller.state.phase, PluginInstallPhase.failed);
      expect(controller.state.error, error);
    });

    test('a local file is ready at once, with nothing to fetch', () async {
      final controller = build(
        _FakeClient(_release()),
        intent: const LocalInstallIntent('/tmp/a.pyrix'),
      );

      await controller.load();

      expect(controller.state.phase, PluginInstallPhase.ready);
      expect(controller.state.release, isNull);
    });
  });

  group('installing from a registry', () {
    test('downloads, installs the verified file and cleans up', () async {
      installResult = true;
      final client = _FakeClient(_release());
      final controller = build(client);
      await controller.load();

      await controller.install();

      expect(controller.state.phase, PluginInstallPhase.installed);
      expect(controller.state.updated, isTrue);
      expect(installed.single, endsWith('package.pyrix'));
      expect(temp.listSync(), isEmpty);
    });

    test('refuses a release the registry marks as not installable', () async {
      final client = _FakeClient(
        _release(
          installable: false,
          moderation: const PluginModeration(level: 'withdrawn'),
        ),
      );
      final controller = build(client);
      await controller.load();

      await controller.install();

      expect(controller.canInstall, isFalse);
      expect(client.downloads, 0);
      expect(installed, isEmpty);
      expect(controller.state.phase, PluginInstallPhase.ready);
    });

    test('waits for acknowledgement of a high severity advisory', () async {
      final client = _FakeClient(
        _release(
          moderation: const PluginModeration(
            level: 'advisory',
            severity: 'high',
            message: 'Reads files',
          ),
        ),
      );
      final controller = build(client);
      await controller.load();

      await controller.install();
      expect(client.downloads, 0);

      await controller.install(acknowledged: true);
      expect(controller.state.phase, PluginInstallPhase.installed);
    });

    test('a moderate advisory needs no acknowledgement', () async {
      final controller = build(
        _FakeClient(
          _release(
            moderation: const PluginModeration(
              level: 'advisory',
              severity: 'moderate',
            ),
          ),
        ),
      );
      await controller.load();

      await controller.install();

      expect(controller.state.phase, PluginInstallPhase.installed);
    });

    test('needs explicit trust for a new site, then remembers it', () async {
      final store = _FakeTrusted();
      final client = _FakeClient(_release());
      final controller = build(client, store: store);
      await controller.load();

      await controller.install();
      expect(client.downloads, 0);
      expect(store.origins, isEmpty);

      await controller.install(trustSource: true);
      expect(controller.state.phase, PluginInstallPhase.installed);
      expect(store.origins, {'https://forum.example'});
    });

    test('fails on a checksum mismatch without installing anything', () async {
      const error = PluginRegistryException(
        PluginRegistryErrorCode.hashMismatch,
        'bad checksum',
      );
      final controller = build(_FakeClient(_release(), downloadError: error));
      await controller.load();

      await controller.install();

      expect(controller.state.phase, PluginInstallPhase.failed);
      expect(controller.state.error, error);
      expect(installed, isEmpty);
      expect(temp.listSync(), isEmpty);
    });

    test('fails when the plugin manager rejects the package', () async {
      installError = StateError('invalid manifest');
      final controller = build(_FakeClient(_release()));
      await controller.load();

      await controller.install();

      expect(controller.state.phase, PluginInstallPhase.failed);
      expect(controller.state.error, isA<StateError>());
      expect(temp.listSync(), isEmpty);
    });

    test('ignores a second install while one is running', () async {
      final controller = build(_FakeClient(_release()));
      await controller.load();

      await Future.wait([controller.install(), controller.install()]);

      expect(installed, hasLength(1));
    });
  });

  group('installing a local file', () {
    test('hands the path to the plugin manager', () async {
      final controller = build(
        _FakeClient(_release()),
        intent: const LocalInstallIntent('/tmp/a.pyrix'),
      );
      await controller.load();

      await controller.install();

      expect(installed, ['/tmp/a.pyrix']);
      expect(controller.state.phase, PluginInstallPhase.installed);
    });
  });

  group('provenance', () {
    test(
      'records where a registry install came from, with its standing',
      () async {
        final controller = build(
          _FakeClient(
            _release(
              moderation: const PluginModeration(
                level: 'deprecated',
                message: 'Use Hello 2',
              ),
            ),
          ),
        );
        await controller.load();

        await controller.install();

        final snapshot = await PluginRegistryLedger(
          supportDirectory: () async => support,
        ).read();
        expect(
          snapshot.sources['com.example.hello'],
          const RegistrySource(
            pluginId: 'com.example.hello',
            origin: 'https://forum.example',
            version: '1.2.0',
          ),
        );
        expect(
          snapshot.advisories['com.example.hello']?.moderation.level,
          'deprecated',
        );
        expect(ledgerCallbacks, 1);
      },
    );

    test('a local file install records nothing', () async {
      final controller = build(
        _FakeClient(_release()),
        intent: const LocalInstallIntent('/tmp/a.pyrix'),
      );
      await controller.load();

      await controller.install();

      final snapshot = await PluginRegistryLedger(
        supportDirectory: () async => support,
      ).read();
      expect(snapshot.sources, isEmpty);
      expect(ledgerCallbacks, 0);
    });

    test('a failed install records nothing', () async {
      installError = StateError('invalid manifest');
      final controller = build(_FakeClient(_release()));
      await controller.load();

      await controller.install();

      final snapshot = await PluginRegistryLedger(
        supportDirectory: () async => support,
      ).read();
      expect(snapshot.sources, isEmpty);
    });

    test('an unwritable ledger does not fail a successful install', () async {
      final controller = build(
        _FakeClient(_release()),
        ledger: PluginRegistryLedger(
          supportDirectory: () async =>
              throw const FileSystemException('denied'),
        ),
      );
      await controller.load();

      await controller.install();

      expect(controller.state.phase, PluginInstallPhase.installed);
    });
  });

  test('retry loads again after a failure', () async {
    final controller = build(
      _FakeClient(
        _release(),
        fetchError: const PluginRegistryException(
          PluginRegistryErrorCode.unreachable,
          'offline',
        ),
      ),
    );
    await controller.load();
    expect(controller.state.phase, PluginInstallPhase.failed);

    await controller.retry();

    expect(controller.state.phase, PluginInstallPhase.failed);
  });
}
