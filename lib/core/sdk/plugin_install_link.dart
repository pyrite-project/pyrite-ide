import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:pyrite_ide/core/sdk/plugin_package_paths.dart';

const pluginInstallScheme = 'pyride';

/// npm-style package names as the registry publishes them: a bare name or
/// `@scope/name`, lowercase, starting and ending with a letter or digit.
final _registryIdPattern = RegExp(
  r'^(?:@[a-z0-9](?:[a-z0-9._-]*[a-z0-9])?/)?[a-z0-9](?:[a-z0-9._-]*[a-z0-9])?$',
);
const _maxPluginIdLength = 214;
const _maxVersionLength = 64;
const _packageExtensions = {'.pyrix', '.zip'};

/// What the user asked the IDE to install, before anything is fetched.
sealed class PluginInstallIntent {
  const PluginInstallIntent();

  /// Stable identity used to focus an already open install tab.
  String get tabId;
}

/// A plugin published on a registry site, reached through a `pyride://` link.
final class RegistryInstallIntent extends PluginInstallIntent {
  const RegistryInstallIntent({
    required this.pluginId,
    required this.version,
    required this.origin,
  });

  final String pluginId;
  final String version;

  /// Normalised site origin (scheme, host, optional port and sub-folder), with
  /// no trailing slash.
  final String origin;

  @override
  String get tabId => 'plugin-install:$origin/$pluginId@$version';

  @override
  bool operator ==(Object other) =>
      other is RegistryInstallIntent &&
      other.pluginId == pluginId &&
      other.version == version &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(pluginId, version, origin);
}

/// A package already on disk, opened through the `.pyrix` file association.
final class LocalInstallIntent extends PluginInstallIntent {
  const LocalInstallIntent(this.packagePath);

  final String packagePath;

  @override
  String get tabId => 'plugin-install:file:$packagePath';

  @override
  bool operator ==(Object other) =>
      other is LocalInstallIntent && other.packagePath == packagePath;

  @override
  int get hashCode => packagePath.hashCode;
}

/// Parses a launch argument or incoming URL into an install intent.
///
/// Returns null for anything that is not a well-formed install request: the
/// operating system hands over whatever a web page or another program asked
/// for, so every field is checked rather than trusted.
PluginInstallIntent? parsePluginInstallTarget(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  if (text.toLowerCase().startsWith('$pluginInstallScheme:')) {
    final uri = Uri.tryParse(text);
    return uri == null ? null : _parseRegistryLink(uri);
  }
  if (text.toLowerCase().startsWith('file:')) {
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.isScheme('file')) return null;
    return _localIntent(uri.toFilePath());
  }
  // Any other URL scheme (http, ftp, ...) is not a path; a single letter before
  // the colon is a Windows drive.
  final scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*):').firstMatch(text);
  if (scheme != null && scheme.group(1)!.length > 1) return null;
  return _localIntent(text);
}

PluginInstallIntent? _localIntent(String filePath) {
  if (!_packageExtensions.contains(path.extension(filePath).toLowerCase())) {
    return null;
  }
  return LocalInstallIntent(path.normalize(filePath));
}

RegistryInstallIntent? _parseRegistryLink(Uri uri) {
  if (uri.host != 'plugin' || uri.path != '/install') return null;

  final params = uri.queryParametersAll;
  if (params.keys.any((key) => !{'id', 'version', 'origin'}.contains(key)) ||
      params.values.any((values) => values.length != 1)) {
    return null;
  }

  final id = params['id']?.single;
  final version = params['version']?.single;
  final origin = normalizeRegistryOrigin(params['origin']?.single);
  if (id == null || version == null || origin == null) return null;
  if (!isValidRegistryPluginId(id) || !isValidRegistryVersion(version)) {
    return null;
  }
  return RegistryInstallIntent(pluginId: id, version: version, origin: origin);
}

bool isValidRegistryPluginId(String id) =>
    id.length <= _maxPluginIdLength &&
    _registryIdPattern.hasMatch(id) &&
    isSafePluginId(id);

/// Whether [version] is a semantic version in its canonical form.
///
/// Only the canonical spelling is accepted: build metadata never changes
/// precedence, and "01.0.0" would otherwise alias "1.0.0".
bool isValidRegistryVersion(String version) {
  if (version.length > _maxVersionLength) return false;
  try {
    final parsed = Version.parse(version);
    // Version.toString() echoes the input, so the canonical spelling is rebuilt
    // from the parsed numbers: leading zeros do not survive.
    final canonical =
        '${parsed.major}.${parsed.minor}.${parsed.patch}'
        '${parsed.isPreRelease ? '-${parsed.preRelease.join('.')}' : ''}';
    return parsed.build.isEmpty && canonical == version;
  } on FormatException {
    return false;
  }
}

/// The canonical form of a registry site origin, or null when it is not an
/// acceptable one: https only, except plain http for a local development
/// server; no credentials, query or fragment.
String? normalizeRegistryOrigin(String? raw) {
  // Uri.parse collapses dot segments, so a traversal attempt must be caught on
  // the raw text.
  if (raw == null || raw.contains('..') || raw.toLowerCase().contains('%2e')) {
    return null;
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;

  final isLoopback =
      uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
  final schemeAllowed =
      uri.isScheme('https') || (uri.isScheme('http') && isLoopback);
  if (!schemeAllowed) return null;

  final folder = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (folder.contains('//')) return null;

  final port = uri.hasPort ? ':${uri.port}' : '';
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  return '${uri.scheme}://${host.toLowerCase()}$port$folder';
}
