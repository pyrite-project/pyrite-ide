import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';
import 'package:pyrite_ide/core/services/persistence/plugin_persistence.dart';

String _manifest({
  String id = '@my-org/hello',
  String container = 'my-org.hello',
  String view = 'my-org.hello.main',
}) =>
    '''
manifest_version = 2
id = "$id"
name = "Hello"
version = "1.0.0"
type = "ui"
protocol_version = 1
activation_events = ["onView:$view"]
permissions = ["ui.view"]
platforms = ["windows"]

[[contributes.navigation_containers]]
id = "$container"
title = "Hello"

[[contributes.views]]
id = "$view"
container = "$container"
title = "Hello"
renderer = "native.tree"
''';

Matcher _failsWith(String code) =>
    throwsA(isA<PluginManifestException>().having((e) => e.code, 'code', code));

void main() {
  test('a scoped plugin contributes under the scope.name namespace', () {
    final manifest = PluginTomlParser.parse(_manifest()).manifest!;

    expect(manifest.id, '@my-org/hello');
    expect(manifest.contributes.views.single.id, 'my-org.hello.main');
    expect(contributionNamespaceOf(manifest.id), 'my-org.hello');
  });

  test('a bare plugin keeps its own id as the namespace', () {
    expect(contributionNamespaceOf('com.example.hello'), 'com.example.hello');
  });

  test('contributions must use the namespace, not the raw scoped id', () {
    expect(
      () => PluginTomlParser.parse(
        _manifest(container: '@my-org/hello', view: '@my-org/hello.main'),
      ),
      _failsWith(PluginManifestErrorCode.invalidContributionId),
    );
    expect(
      () => PluginTomlParser.parse(
        _manifest(container: 'other.ns', view: 'other.ns.main'),
      ),
      _failsWith(PluginManifestErrorCode.invalidContributionId),
    );
  });

  test('malformed scoped ids are rejected', () {
    for (final id in [
      '@my-org',
      'my-org/hello',
      '@/hello',
      '@a/b/c',
      '@a/b.',
    ]) {
      expect(
        () => PluginTomlParser.parse(_manifest(id: id)),
        _failsWith(PluginManifestErrorCode.invalidPluginId),
        reason: id,
      );
    }
  });
}
