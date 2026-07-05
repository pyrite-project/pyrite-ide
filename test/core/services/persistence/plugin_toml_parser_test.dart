import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/persistence/plugin_persistence.dart';

void main() {
  test('dialog=true expands to show permission', () {
    final tempDir = Directory.systemTemp.createTempSync('pyrite_plugin_toml_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final tomlFile = File(p.join(tempDir.path, 'plugin.toml'))
      ..writeAsStringSync('''
[general]
name = "Debugger"
id = "debugger"
type = "ui"

[permissions]
dialog = true
''');

    final parsed = PluginTomlParser.parseFromFileSync(tomlFile);

    expect(parsed?.permissions['dialog'], ['show']);
  });

  test('persisted old dialog read/write permissions migrate to show', () {
    final plugin = PluginPersistedData.fromJson({
      'id': 'debugger',
      'name': 'Debugger',
      'permissions': {
        'dialog': ['read', 'write'],
      },
    }).toPlugin();

    expect(plugin.permissions['dialog'], ['show']);
    expect(plugin.declaredPermissions['dialog'], ['show']);
  });
}
