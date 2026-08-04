import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/persistence/plugin_persistence.dart';

File _fixture(String name) =>
    File(p.join('test', 'fixtures', 'manifest_v2', '$name.toml'));

void main() {
  test('minimal UI Manifest v2 preserves raw and normalized models', () {
    final file = _fixture('minimal_ui');
    final parsed = PluginTomlParser.parseFromFileSync(file);

    expect(parsed.rawManifest, file.readAsStringSync());
    expect(parsed.id, 'minimal-ui');
    expect(parsed.type, 'ui');
    expect(parsed.permissions, {
      'ui': ['view'],
    });
    expect(parsed.manifest?.manifestVersion, 2);
    expect(
      parsed.manifest?.contributes.navigationContainers.single.id,
      'minimal-ui',
    );
    expect(parsed.manifest?.contributes.views.single.renderer, 'native.tree');
  });

  test('full UI Manifest v2 parses every contribution point', () {
    final manifest = PluginTomlParser.parseFromFileSync(
      _fixture('full_ui'),
    ).manifest!;

    expect(manifest.activationEvents, hasLength(3));
    expect(manifest.permissionsByResource['runtime'], ['inspect']);
    expect(manifest.contributes.navigationContainers, hasLength(1));
    expect(manifest.contributes.views, hasLength(2));
    expect(
      manifest.contributes.commands.single.icon?.kind,
      PluginIconKind.material,
    );
    expect(manifest.contributes.commands.single.icon?.value, 'refresh');
    expect(manifest.contributes.menus.single.location, 'view/title');
    expect(manifest.contributes.configuration.single.defaultValue, isFalse);
    expect(
      manifest.contributes.views.last.when,
      "runtime.language == 'python' && workspace.opened",
    );
  });

  test('data and service manifests have the expected activation policy', () {
    final data = PluginTomlParser.parseFromFileSync(_fixture('data'));
    final service = PluginTomlParser.parseFromFileSync(_fixture('service'));

    expect(data.manifest?.type, PluginType.data);
    expect(data.autoStart, isFalse);
    expect(data.manifest?.contributes.ids, isEmpty);
    expect(service.manifest?.type, PluginType.service);
    expect(service.autoStart, isTrue);
    expect(service.manifest?.activationEvents, ['onStartup']);
  });

  test('declared icon assets must exist below the plugin assets directory', () {
    final root = Directory.systemTemp.createTempSync('pyrite-manifest-icons-');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'assets')).createSync();
    File(p.join(root.path, 'assets', 'full.webp')).writeAsBytesSync([1]);
    File(p.join(root.path, 'plugin.toml')).writeAsStringSync('''
manifest_version = 2
id = "asset-plugin"
name = "Asset Plugin"
version = "1.0.0"
type = "service"
protocol_version = 1

[icons]
full = "assets/full.webp"
monochrome = "assets/mono.png"
''');

    expect(
      () => PluginTomlParser.parseFromDirectory(root),
      throwsA(
        isA<PluginManifestException>().having(
          (error) => error.code,
          'code',
          PluginManifestErrorCode.invalidSchema,
        ),
      ),
    );
    File(p.join(root.path, 'assets', 'mono.png')).writeAsBytesSync([2]);
    final manifest = PluginTomlParser.parseFromDirectory(root).manifest!;
    expect(manifest.icons?.full, 'assets/full.webp');
    expect(manifest.icons?.monochrome, 'assets/mono.png');
  });

  test('normalized manifest and raw TOML survive JSON persistence', () {
    final parsed = PluginTomlParser.parseFromFileSync(_fixture('full_ui'));
    final json =
        jsonDecode(jsonEncode(parsed.toJson())) as Map<String, dynamic>;
    final restored = PluginPersistedData.fromJson(json);

    expect(restored.rawManifest, parsed.rawManifest);
    expect(restored.manifest?.toJson(), parsed.manifest?.toJson());
    expect(
      restored.toPlugin().contributions.toJson(),
      parsed.manifest?.contributes.toJson(),
    );
  });

  test('legacy Manifest v2 metadata initializes grants from declarations', () {
    final parsed = PluginTomlParser.parseFromFileSync(_fixture('full_ui'));
    final json = Map<String, dynamic>.from(parsed.toJson())
      ..['permissions'] = <String, List<String>>{}
      ..remove('permissionGrantsInitialized');

    final restored = PluginPersistedData.fromJson(json).toPlugin();

    expect(restored.permissions, restored.declaredPermissions);
  });

  test('initialized empty grants remain denied', () {
    final parsed = PluginTomlParser.parseFromFileSync(_fixture('full_ui'));
    final json = Map<String, dynamic>.from(parsed.toJson())
      ..['permissions'] = <String, List<String>>{}
      ..['permissionGrantsInitialized'] = true;

    final restored = PluginPersistedData.fromJson(json).toPlugin();

    expect(restored.permissions, {
      for (final resource in restored.declaredPermissions.keys)
        resource: <String>[],
    });
  });

  test('legacy persisted metadata is disabled instead of upgraded', () {
    final plugin = PluginPersistedData.fromJson({
      'id': 'legacy',
      'name': 'Legacy',
      'status': 'usable',
    }).toPlugin();

    expect(plugin.status, PluginStatus.disabled);
    expect(plugin.manifest, isNull);
    expect(plugin.manifestErrorCode, PluginManifestErrorCode.missingVersion);
  });

  test('legacy TOML is rejected as a missing Manifest v2 version', () {
    final legacy = File(
      p.join(
        'test',
        'fixtures',
        'plugins',
        'minimal_legacy_plugin',
        'plugin.toml',
      ),
    );

    expect(
      () => PluginTomlParser.parseFromFileSync(legacy),
      throwsA(
        isA<PluginManifestException>().having(
          (error) => error.code,
          'code',
          PluginManifestErrorCode.missingVersion,
        ),
      ),
    );
  });

  test('empty when expressions use the stable when error code', () {
    final source = _fixture('minimal_ui').readAsStringSync().replaceFirst(
      'renderer = "native.tree"',
      'renderer = "native.tree"\nwhen = ""',
    );
    expect(source, contains('\nwhen = ""'));
    expect(
      () => PluginTomlParser.parse(source),
      throwsA(
        isA<PluginManifestException>().having(
          (error) => error.code,
          'code',
          PluginManifestErrorCode.invalidWhen,
        ),
      ),
    );
  });

  test('invalid UTF-8 uses the stable TOML error code', () {
    final directory = Directory.systemTemp.createTempSync('pyrite-manifest-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File(p.join(directory.path, 'plugin.toml'))
      ..writeAsBytesSync([0xff]);

    expect(
      () => PluginTomlParser.parseFromFileSync(file),
      throwsA(
        isA<PluginManifestException>().having(
          (error) => error.code,
          'code',
          PluginManifestErrorCode.invalidToml,
        ),
      ),
    );
  });

  const rejectedFixtures = {
    'contribution_conflict': PluginManifestErrorCode.contributionConflict,
    'invalid_schema': PluginManifestErrorCode.invalidSchema,
    'invalid_when': PluginManifestErrorCode.invalidWhen,
    'integer_overflow': PluginManifestErrorCode.invalidSchema,
    'manifest_v1': PluginManifestErrorCode.unsupportedVersion,
    'missing_navigation': PluginManifestErrorCode.missingNavigationContainer,
    'missing_version': PluginManifestErrorCode.missingVersion,
    'non_json_configuration': PluginManifestErrorCode.invalidSchema,
    'rfw_renderer': PluginManifestErrorCode.rfwRendererUnsupported,
    'unknown_renderer': PluginManifestErrorCode.unknownRenderer,
  };

  for (final entry in rejectedFixtures.entries) {
    test('${entry.key} is rejected with a stable error code', () {
      expect(
        () => PluginTomlParser.parseFromFileSync(_fixture(entry.key)),
        throwsA(
          isA<PluginManifestException>().having(
            (error) => error.code,
            'code',
            entry.value,
          ),
        ),
      );
    });
  }
}
