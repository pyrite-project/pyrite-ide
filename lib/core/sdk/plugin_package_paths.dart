import 'dart:io';

import 'package:path/path.dart' as path;

const pluginDirectoryName = 'plugin';
const pluginUpdatesDirectoryName = 'plugin_updates';
const pluginNewDirectoryName = 'new';
const pluginPendingDeletionsDirectoryName = 'pending_deletions';

bool isSafePluginId(String pluginId) {
  if (pluginId.isEmpty ||
      pluginId.trim() != pluginId ||
      path.isAbsolute(pluginId) ||
      path.basename(pluginId) != pluginId) {
    return false;
  }
  final parent = path.normalize(path.join(path.separator, 'plugin-root'));
  final child = path.normalize(path.join(parent, pluginId));
  return path.equals(path.dirname(child), parent);
}

Directory installedPluginDirectory(Directory support, String pluginId) {
  if (!isSafePluginId(pluginId)) {
    throw FormatException('Invalid plugin ID: $pluginId');
  }
  return Directory(
    path.normalize(path.join(support.path, pluginDirectoryName, pluginId)),
  );
}

Directory newPluginDirectory(Directory support, String pluginId) {
  if (!isSafePluginId(pluginId)) {
    throw FormatException('Invalid plugin ID: $pluginId');
  }
  return Directory(
    path.normalize(
      path.join(
        support.path,
        pluginUpdatesDirectoryName,
        pluginNewDirectoryName,
        pluginId,
      ),
    ),
  );
}

File pendingPluginDeletionMarker(Directory support, String pluginId) {
  if (!isSafePluginId(pluginId)) {
    throw FormatException('Invalid plugin ID: $pluginId');
  }
  return File(
    path.normalize(
      path.join(
        support.path,
        pluginUpdatesDirectoryName,
        pluginPendingDeletionsDirectoryName,
        '$pluginId.json',
      ),
    ),
  );
}

Future<Directory> resolvePluginPackageDirectory(
  Directory support,
  String pluginId,
) async {
  final replacement = newPluginDirectory(support, pluginId);
  final marker = pendingPluginDeletionMarker(support, pluginId);
  if (await marker.exists() && await replacement.exists()) return replacement;
  return installedPluginDirectory(support, pluginId);
}
