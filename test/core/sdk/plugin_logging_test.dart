import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source files that carry plugin diagnostics.
///
/// Listed explicitly rather than scanning the whole tree: other subsystems
/// still use `debugPrint` outside this boundary, and a repository-wide text
/// scan would fail for reasons that do not belong to the plugin system.
const _pluginSourceFiles = <String>[
  'core/sdk/plugin_manager_provider.dart',
  'core/sdk/python_runtime_host.dart',
  'core/sdk/api/file.dart',
  'core/sdk/permission_log.dart',
  'features/plugin_view/plugin_view_surface.dart',
];

void main() {
  test('plugin diagnostics are written through AppLog', () async {
    final offenders = <String>[];
    for (final relativePath in _pluginSourceFiles) {
      final file = File('${Directory.current.path}/lib/$relativePath');
      expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
      final lines = await file.readAsLines();
      if (!lines.any((line) => line.contains('AppLog.'))) {
        offenders.add('$relativePath: no AppLog call');
      }
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('debugPrint(')) {
          offenders.add('$relativePath:${index + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Plugin diagnostics must use AppLog so warnings and errors reach '
          'app.log instead of only the debug console.',
    );
  });
}
