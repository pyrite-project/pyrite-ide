import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/material_icons.g.dart';
import 'package:pyrite_ide/core/sdk/plugin_resources.dart';

void main() {
  test('full Flutter Material icon catalog resolves by explicit name', () {
    final icon = materialIcon('account_tree_outlined');
    expect(icon, isNotNull);
    expect(icon!.fontFamily, 'MaterialIcons');
    expect(materialIcon('not_a_flutter_icon'), isNull);
    expect(materialIconCodePoints.length, greaterThan(8000));
  });

  test('plugin resource URIs stay scoped below assets', () {
    expect(
      pluginResourcePath('plugin-resource:///assets/images/banner.webp'),
      'assets/images/banner.webp',
    );
    for (final invalid in [
      'assets/images/banner.webp',
      'plugin-resource:///images/banner.webp',
      'plugin-resource:///assets/../banner.webp',
      'plugin-resource://other/assets/banner.webp',
    ]) {
      expect(pluginResourcePath(invalid), isNull, reason: invalid);
    }
  });

  test('asset files resolve only inside the plugin root', () async {
    final root = await Directory.systemTemp.createTemp('pyrite-resource-');
    addTearDown(() => root.delete(recursive: true));
    final assets = Directory(path.join(root.path, 'assets'))..createSync();
    final image = File(path.join(assets.path, 'banner.webp'))
      ..writeAsBytesSync([1, 2, 3]);

    expect(
      resolvePluginAssetFile(root.path, 'assets/banner.webp')?.path,
      image.path,
    );
    expect(resolvePluginAssetFile(root.path, '../banner.webp'), isNull);
    expect(resolvePluginAssetFile(root.path, 'assets/missing.webp'), isNull);
  });
}
