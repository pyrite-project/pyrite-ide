import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';

void main() {
  test('plugin install cleanup removes old package files', () async {
    final target = await Directory.systemTemp.createTemp('pyrite-plugin-');
    try {
      await File('${target.path}/__main__.py').writeAsString('old');
      await Directory('${target.path}/site-packages').create();
      await File('${target.path}/site-packages/stale.py').writeAsString('old');
      await Directory('${target.path}/data').create();
      await File('${target.path}/data/settings.json').writeAsString('keep');
      await Directory('${target.path}/cache').create();
      await File('${target.path}/cache/index.db').writeAsString('keep');

      await preparePluginInstallDirectory(target);

      expect(File('${target.path}/__main__.py').existsSync(), isFalse);
      expect(Directory('${target.path}/site-packages').existsSync(), isFalse);
      expect(
        File('${target.path}/data/settings.json').readAsStringSync(),
        'keep',
      );
      expect(File('${target.path}/cache/index.db').readAsStringSync(), 'keep');
    } finally {
      await target.delete(recursive: true);
    }
  });

  test(
    'plugin install cleanup treats data and cache case-insensitively',
    () async {
      final target = await Directory.systemTemp.createTemp('pyrite-plugin-');
      try {
        await Directory('${target.path}/DATA').create();
        await File('${target.path}/DATA/state').writeAsString('keep');
        await Directory('${target.path}/Cache').create();
        await File('${target.path}/Cache/state').writeAsString('keep');
        await File('${target.path}/stale.txt').writeAsString('remove');

        await preparePluginInstallDirectory(target);

        expect(File('${target.path}/DATA/state').readAsStringSync(), 'keep');
        expect(File('${target.path}/Cache/state').readAsStringSync(), 'keep');
        expect(File('${target.path}/stale.txt').existsSync(), isFalse);
      } finally {
        await target.delete(recursive: true);
      }
    },
  );
}
