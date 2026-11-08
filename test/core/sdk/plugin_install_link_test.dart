import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_install_link.dart';

void main() {
  group('registry links', () {
    const valid =
        'pyride://plugin/install?id=com.example.hello&version=1.2.0'
        '&origin=https%3A%2F%2Fforum.example';

    test('parses a well formed link', () {
      final intent = parsePluginInstallTarget(valid);

      expect(
        intent,
        const RegistryInstallIntent(
          pluginId: 'com.example.hello',
          version: '1.2.0',
          origin: 'https://forum.example',
        ),
      );
    });

    test('keeps a sub-folder install and drops the trailing slash', () {
      final intent =
          parsePluginInstallTarget(
                'pyride://plugin/install?id=a&version=1.0.0-rc.1'
                '&origin=https%3A%2F%2FForum.Example%3A8443%2Fcommunity%2F',
              )
              as RegistryInstallIntent;

      expect(intent.origin, 'https://forum.example:8443/community');
      expect(intent.version, '1.0.0-rc.1');
    });

    test('allows plain http only for a local server', () {
      String link(String origin) =>
          'pyride://plugin/install?id=a&version=1.0.0'
          '&origin=${Uri.encodeComponent(origin)}';

      expect(
        parsePluginInstallTarget(link('http://localhost:4200')),
        isNotNull,
      );
      expect(
        parsePluginInstallTarget(link('http://127.0.0.1:3000')),
        isNotNull,
      );
      expect(parsePluginInstallTarget(link('http://forum.example')), isNull);
    });

    test('rejects origins carrying credentials, queries or odd schemes', () {
      String link(String origin) =>
          'pyride://plugin/install?id=a&version=1.0.0'
          '&origin=${Uri.encodeComponent(origin)}';

      expect(
        parsePluginInstallTarget(link('https://u:p@forum.example')),
        isNull,
      );
      expect(
        parsePluginInstallTarget(link('https://forum.example/?x=1')),
        isNull,
      );
      expect(
        parsePluginInstallTarget(link('https://forum.example/#f')),
        isNull,
      );
      expect(parsePluginInstallTarget(link('ftp://forum.example')), isNull);
      expect(
        parsePluginInstallTarget(link('https://forum.example/../x')),
        isNull,
      );
      expect(parsePluginInstallTarget(link('forum.example')), isNull);
    });

    test('parses an npm-style scoped id sent percent-encoded', () {
      final intent =
          parsePluginInstallTarget(
                'pyride://plugin/install?id=%40my-org%2Fhello.plugin'
                '&version=1.0.0&origin=https%3A%2F%2Fforum.example',
              )
              as RegistryInstallIntent;

      expect(intent.pluginId, '@my-org/hello.plugin');
      expect(
        intent.tabId,
        'plugin-install:https://forum.example/@my-org/hello.plugin@1.0.0',
      );
    });

    test('rejects malformed scoped ids', () {
      String link(String id) =>
          'pyride://plugin/install?id=${Uri.encodeComponent(id)}'
          '&version=1.0.0&origin=https%3A%2F%2Fforum.example';

      for (final id in [
        '@scope',
        '@/name',
        'scope/name',
        '@Scope/name',
        '@scope/a/b',
        '@scope/Name',
        '.hidden',
        'trailing.',
        'a' * 215,
      ]) {
        expect(parsePluginInstallTarget(link(id)), isNull, reason: id);
      }
    });

    test('accepts semantic versions with pre-release identifiers only', () {
      String link(String version) =>
          'pyride://plugin/install?id=a&version=${Uri.encodeComponent(version)}'
          '&origin=https%3A%2F%2Fforum.example';

      expect(parsePluginInstallTarget(link('1.0.0-beta.2')), isNotNull);
      expect(parsePluginInstallTarget(link('10.20.30')), isNotNull);
      expect(parsePluginInstallTarget(link('1.0.0+build.5')), isNull);
      expect(parsePluginInstallTarget(link('1.0.0-')), isNull);
      expect(parsePluginInstallTarget(link('v1.0.0')), isNull);
      expect(parsePluginInstallTarget(link(' 1.0.0')), isNull);
    });

    test('rejects unsafe or malformed plugin ids', () {
      String link(String id) =>
          'pyride://plugin/install?id=${Uri.encodeComponent(id)}'
          '&version=1.0.0&origin=https%3A%2F%2Fforum.example';

      expect(parsePluginInstallTarget(link('../escape')), isNull);
      expect(parsePluginInstallTarget(link('a/b')), isNull);
      expect(parsePluginInstallTarget(link('Upper.Case')), isNull);
      expect(parsePluginInstallTarget(link('')), isNull);
      expect(parsePluginInstallTarget(link('a' * 215)), isNull);
    });

    test('rejects versions that are not semantic versions', () {
      String link(String version) =>
          'pyride://plugin/install?id=a&version=${Uri.encodeComponent(version)}'
          '&origin=https%3A%2F%2Fforum.example';

      expect(parsePluginInstallTarget(link('latest')), isNull);
      expect(parsePluginInstallTarget(link('1.0')), isNull);
      expect(parsePluginInstallTarget(link('01.0.0')), isNull);
      expect(parsePluginInstallTarget(link('1.02.0')), isNull);
      expect(parsePluginInstallTarget(link('1.0.0-01')), isNull);
      expect(parsePluginInstallTarget(link('1.0.0/../..')), isNull);
    });

    test('rejects unknown, repeated or missing parameters', () {
      const base = 'pyride://plugin/install';
      const origin = 'origin=https%3A%2F%2Fforum.example';

      expect(parsePluginInstallTarget('$base?id=a&$origin'), isNull);
      expect(
        parsePluginInstallTarget('$base?id=a&version=1.0.0&$origin&url=x'),
        isNull,
      );
      expect(
        parsePluginInstallTarget('$base?id=a&id=b&version=1.0.0&$origin'),
        isNull,
      );
    });

    test('rejects other hosts and paths under the scheme', () {
      const tail = '?id=a&version=1.0.0&origin=https%3A%2F%2Fforum.example';

      expect(parsePluginInstallTarget('pyride://other/install$tail'), isNull);
      expect(parsePluginInstallTarget('pyride://plugin/remove$tail'), isNull);
      expect(
        parsePluginInstallTarget('pyride://plugin/install/x$tail'),
        isNull,
      );
    });
  });

  group('package files', () {
    test('accepts .pyrix and .zip paths, case-insensitively', () {
      expect(
        parsePluginInstallTarget('/tmp/hello.pyrix'),
        const LocalInstallIntent('/tmp/hello.pyrix'),
      );
      expect(
        parsePluginInstallTarget('/tmp/Hello.ZIP'),
        const LocalInstallIntent('/tmp/Hello.ZIP'),
      );
    });

    test('accepts file URLs', () {
      expect(
        parsePluginInstallTarget('file:///tmp/my%20plugin.pyrix'),
        const LocalInstallIntent('/tmp/my plugin.pyrix'),
      );
    });

    test('ignores anything else', () {
      expect(parsePluginInstallTarget(''), isNull);
      expect(parsePluginInstallTarget('--flag'), isNull);
      expect(parsePluginInstallTarget('/tmp/script.sh'), isNull);
      expect(parsePluginInstallTarget('https://forum.example/a.pyrix'), isNull);
    });
  });

  test('tab ids separate registry and local installs', () {
    const registry = RegistryInstallIntent(
      pluginId: 'a',
      version: '1.0.0',
      origin: 'https://forum.example',
    );

    expect(registry.tabId, 'plugin-install:https://forum.example/a@1.0.0');
    expect(
      const LocalInstallIntent('/tmp/a.pyrix').tabId,
      'plugin-install:file:/tmp/a.pyrix',
    );
  });
}
