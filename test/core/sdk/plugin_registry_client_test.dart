import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_install_link.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_client.dart';

void main() {
  late HttpServer server;
  late Directory temp;
  late RegistryInstallIntent intent;
  late List<int> packageBytes;
  late Map<String, Object?> metadata;
  var metadataStatus = 200;
  var packageStatus = 200;
  var servedPackage = <int>[];
  var requestedPaths = <String>[];
  var requestedQueries = <Map<String, String>>[];
  Object advisoryBody = <String, Object?>{};

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('registry_client_test');
    packageBytes = utf8.encode('pretend this is a zip archive');
    servedPackage = packageBytes;
    metadataStatus = 200;
    packageStatus = 200;
    requestedPaths = [];
    requestedQueries = [];
    advisoryBody = {'advisories': <Object>[]};

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    intent = RegistryInstallIntent(
      pluginId: 'com.example.hello',
      version: '1.2.0',
      origin: 'http://127.0.0.1:${server.port}',
    );
    metadata = {
      'ext_id': 'com.example.hello',
      'name': 'Hello',
      'version': '1.2.0',
      'sha256': sha256.convert(packageBytes).toString(),
      'size': packageBytes.length,
      'type': 'ui',
      'platforms': ['windows', 'macos'],
      'permissions': ['editor.read'],
      'author': 'Ann',
      'installable': true,
      'moderation': {'level': 'none'},
      // A hostile registry cannot redirect the download through this field.
      'download_url': 'https://evil.example/steal.pyrix',
    };

    server.listen((request) async {
      requestedPaths.add(request.uri.path);
      requestedQueries.add(request.uri.queryParameters);
      final response = request.response;
      if (request.uri.path.endsWith('/advisories')) {
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(advisoryBody));
      } else if (request.uri.path.endsWith('/package.pyrix')) {
        response.statusCode = packageStatus;
        response.add(servedPackage);
      } else {
        response.statusCode = metadataStatus;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(metadata));
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  PluginRegistryClient client() => PluginRegistryClient();

  group('fetchRelease', () {
    test('reads the release description', () async {
      final release = await client().fetchRelease(intent);

      expect(release.name, 'Hello');
      expect(release.permissions, ['editor.read']);
      expect(release.platforms, ['windows', 'macos']);
      expect(release.installable, isTrue);
      expect(release.moderation.isFlagged, isFalse);
      expect(
        requestedPaths.single,
        '/pyrite/api/v1/extensions/com.example.hello/versions/1.2.0',
      );
    });

    test('carries moderation details', () async {
      metadata['installable'] = false;
      metadata['moderation'] = {
        'level': 'advisory',
        'severity': 'critical',
        'message': 'Exfiltrates files',
        'scope': 'release',
      };

      final release = await client().fetchRelease(intent);

      expect(release.installable, isFalse);
      expect(release.moderation.level, 'advisory');
      expect(release.moderation.requiresAcknowledgement, isTrue);
      expect(release.moderation.message, 'Exfiltrates files');
    });

    test('only high and critical advisories need acknowledgement', () {
      bool needs(String level, [String? severity]) => PluginModeration(
        level: level,
        severity: severity,
      ).requiresAcknowledgement;

      expect(needs('advisory', 'high'), isTrue);
      expect(needs('advisory', 'moderate'), isFalse);
      expect(needs('deprecated'), isFalse);
    });

    test('refuses a description of another release', () async {
      metadata['version'] = '9.9.9';

      expect(
        client().fetchRelease(intent),
        throwsA(
          isA<PluginRegistryException>().having(
            (e) => e.code,
            'code',
            PluginRegistryErrorCode.badResponse,
          ),
        ),
      );
    });

    test('refuses a malformed checksum', () async {
      metadata['sha256'] = 'not-a-hash';

      expect(
        client().fetchRelease(intent),
        throwsA(isA<PluginRegistryException>()),
      );
    });

    test('maps missing releases to notFound', () async {
      metadataStatus = 404;

      expect(
        client().fetchRelease(intent),
        throwsA(
          isA<PluginRegistryException>().having(
            (e) => e.code,
            'code',
            PluginRegistryErrorCode.notFound,
          ),
        ),
      );
    });

    test('reports an unreachable registry', () async {
      await server.close(force: true);

      expect(
        client().fetchRelease(intent),
        throwsA(
          isA<PluginRegistryException>().having(
            (e) => e.code,
            'code',
            PluginRegistryErrorCode.unreachable,
          ),
        ),
      );
    });
  });

  group('fetchAdvisories', () {
    Map<String, Object?> entry(
      String id,
      String version, {
      String level = 'none',
    }) => {
      'ext_id': id,
      'version': version,
      'installable': level != 'withdrawn',
      'moderation': {
        'level': level,
        'severity': null,
        'message': 'm',
        'scope': 'release',
      },
    };

    test('sends scoped ids intact, comma separated', () async {
      await client().fetchAdvisories(intent.origin, [
        (pluginId: '@my-org/tool', version: '2.0.0'),
        (pluginId: 'com.example.hello', version: '1.2.0-rc.1'),
      ]);

      expect(requestedPaths.single, '/pyrite/api/v1/advisories');
      expect(
        requestedQueries.single['releases'],
        '@my-org/tool@2.0.0,com.example.hello@1.2.0-rc.1',
      );
    });

    test('reads each advisory, flagged or not', () async {
      advisoryBody = {
        'advisories': [
          entry('a', '1.0.0'),
          entry('b', '2.0.0', level: 'withdrawn'),
        ],
      };

      final result = await client().fetchAdvisories(intent.origin, [
        (pluginId: 'a', version: '1.0.0'),
        (pluginId: 'b', version: '2.0.0'),
      ]);

      expect(result.map((a) => a.pluginId), ['a', 'b']);
      expect(result[0].isFlagged, isFalse);
      expect(result[1].isFlagged, isTrue);
      expect(result[1].installable, isFalse);
    });

    test('refuses an answer that is not a list of advisories', () async {
      advisoryBody = {'advisories': 'nope'};

      await expectLater(
        client().fetchAdvisories(intent.origin, [
          (pluginId: 'a', version: '1.0.0'),
        ]),
        throwsA(
          isA<PluginRegistryException>().having(
            (e) => e.code,
            'code',
            PluginRegistryErrorCode.badResponse,
          ),
        ),
      );
    });

    test('refuses an advisory without an id', () async {
      advisoryBody = {
        'advisories': [
          {'version': '1.0.0'},
        ],
      };

      await expectLater(
        client().fetchAdvisories(intent.origin, [
          (pluginId: 'a', version: '1.0.0'),
        ]),
        throwsA(isA<PluginRegistryException>()),
      );
    });

    test('reports an unreachable registry', () async {
      await server.close(force: true);

      await expectLater(
        client().fetchAdvisories(intent.origin, [
          (pluginId: 'a', version: '1.0.0'),
        ]),
        throwsA(
          isA<PluginRegistryException>().having(
            (e) => e.code,
            'code',
            PluginRegistryErrorCode.unreachable,
          ),
        ),
      );
    });
  });

  group('downloadPackage', () {
    Future<PluginRegistryRelease> release() => client().fetchRelease(intent);

    test('saves a package whose checksum matches', () async {
      final file = await client().downloadPackage(
        intent,
        await release(),
        temp,
      );

      expect(await file.readAsBytes(), packageBytes);
      expect(file.path, endsWith('com.example.hello-1.2.0.pyrix'));
      expect(
        requestedPaths.last,
        '/pyrite/api/v1/extensions/com.example.hello/versions/1.2.0'
        '/package.pyrix',
      );
    });

    test('never downloads from the address the server names', () async {
      await client().downloadPackage(intent, await release(), temp);

      expect(requestedPaths.every((p) => p.startsWith('/pyrite/')), isTrue);
    });

    test('rejects and deletes tampered bytes of the announced size', () async {
      final resolved = await release();
      servedPackage = utf8.encode('tampered package contents!!!!');
      expect(servedPackage.length, packageBytes.length);

      await expectLater(
        client().downloadPackage(intent, resolved, temp),
        throwsA(
          isA<PluginRegistryException>().having(
            (e) => e.code,
            'code',
            PluginRegistryErrorCode.hashMismatch,
          ),
        ),
      );
      expect(temp.listSync(), isEmpty);
    });

    test('rejects and deletes a package larger than announced', () async {
      final resolved = await release();
      servedPackage = [...packageBytes, ...packageBytes];

      await expectLater(
        client().downloadPackage(intent, resolved, temp),
        throwsA(
          isA<PluginRegistryException>().having(
            (e) => e.code,
            'code',
            PluginRegistryErrorCode.tooLarge,
          ),
        ),
      );
      expect(temp.listSync(), isEmpty);
    });

    test('rejects and deletes a truncated package', () async {
      final resolved = await release();
      servedPackage = packageBytes.sublist(0, 5);

      await expectLater(
        client().downloadPackage(intent, resolved, temp),
        throwsA(isA<PluginRegistryException>()),
      );
      expect(temp.listSync(), isEmpty);
    });

    test('reports a withdrawn package as unavailable', () async {
      final resolved = await release();
      packageStatus = 410;

      await expectLater(
        client().downloadPackage(intent, resolved, temp),
        throwsA(
          isA<PluginRegistryException>().having(
            (e) => e.code,
            'code',
            PluginRegistryErrorCode.unavailable,
          ),
        ),
      );
      expect(temp.listSync(), isEmpty);
    });
  });
}
