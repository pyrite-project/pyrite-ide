import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/plugin_package_paths.dart';

void main() {
  test(
    'replacement is selected only while its deletion marker exists',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'pyrite-package-paths-',
      );
      addTearDown(() => root.delete(recursive: true));
      const pluginId = 'example';
      final installed = installedPluginDirectory(root, pluginId);
      final replacement = newPluginDirectory(root, pluginId);
      await installed.create(recursive: true);
      await replacement.create(recursive: true);

      expect(
        (await resolvePluginPackageDirectory(root, pluginId)).path,
        installed.path,
      );

      final marker = pendingPluginDeletionMarker(root, pluginId);
      await marker.parent.create(recursive: true);
      await marker.writeAsString('{}');
      expect(
        (await resolvePluginPackageDirectory(root, pluginId)).path,
        replacement.path,
      );

      await replacement.delete(recursive: true);
      expect(
        (await resolvePluginPackageDirectory(root, pluginId)).path,
        installed.path,
      );
    },
  );

  test('plugin paths remain scoped to their designated roots', () {
    final root = Directory(path.join(path.separator, 'support'));
    expect(
      () => installedPluginDirectory(root, '../escape'),
      throwsFormatException,
    );
    expect(
      newPluginDirectory(root, 'example').path,
      path.join(root.path, 'plugin_updates', 'new', 'example'),
    );
  });
}
