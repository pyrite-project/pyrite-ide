import 'dart:io';

import 'package:path/path.dart' as path;

const pluginDirectoryName = 'plugin';
const pluginUpdatesDirectoryName = 'plugin_updates';
const pluginNewDirectoryName = 'new';
const pluginPendingDeletionsDirectoryName = 'pending_deletions';

/// The directory name a plugin id is stored under, or null for an unusable id.
///
/// An id is a bare name or an npm-style `@scope/name`. A scoped id is stored as
/// `@scope+name`: `+` cannot occur in a scope or a name, so the mapping can be
/// reversed by [pluginIdFromDirectoryName].
String? pluginDirectoryNameOrNull(String pluginId) {
  final String name;
  if (pluginId.startsWith('@')) {
    final parts = pluginId.split('/');
    if (parts.length != 2) return null;
    final scope = parts[0];
    final bare = parts[1];
    if (scope.length < 2 || bare.isEmpty) return null;
    if (scope.contains('+') || bare.contains('+')) return null;
    name = '$scope+$bare';
  } else {
    name = pluginId;
  }
  return _isSafeDirectoryName(name) ? name : null;
}

bool _isSafeDirectoryName(String name) {
  if (name.isEmpty ||
      name.trim() != name ||
      path.isAbsolute(name) ||
      path.basename(name) != name) {
    return false;
  }
  final parent = path.normalize(path.join(path.separator, 'plugin-root'));
  final child = path.normalize(path.join(parent, name));
  return path.equals(path.dirname(child), parent);
}

bool isSafePluginId(String pluginId) =>
    pluginDirectoryNameOrNull(pluginId) != null;

String pluginDirectoryFor(String pluginId) =>
    pluginDirectoryNameOrNull(pluginId) ??
    (throw FormatException('Invalid plugin ID: $pluginId'));

/// The plugin id stored under [directoryName], or null when the name is not one
/// this IDE would have written.
String? pluginIdFromDirectoryName(String directoryName) {
  final pluginId = directoryName.startsWith('@')
      ? directoryName.replaceFirst('+', '/')
      : directoryName;
  return pluginDirectoryNameOrNull(pluginId) == directoryName ? pluginId : null;
}

Directory installedPluginDirectory(Directory support, String pluginId) {
  return Directory(
    path.normalize(
      path.join(
        support.path,
        pluginDirectoryName,
        pluginDirectoryFor(pluginId),
      ),
    ),
  );
}

Directory newPluginDirectory(Directory support, String pluginId) {
  return Directory(
    path.normalize(
      path.join(
        support.path,
        pluginUpdatesDirectoryName,
        pluginNewDirectoryName,
        pluginDirectoryFor(pluginId),
      ),
    ),
  );
}

File pendingPluginDeletionMarker(Directory support, String pluginId) {
  return File(
    path.normalize(
      path.join(
        support.path,
        pluginUpdatesDirectoryName,
        pluginPendingDeletionsDirectoryName,
        '${pluginDirectoryFor(pluginId)}.json',
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
