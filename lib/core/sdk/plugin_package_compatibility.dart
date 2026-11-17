import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:toml/toml.dart';

/// The file the pyrite-sdk packager writes into every plugin archive with the
/// platform/architecture its Python dependencies were built for.
const pluginRuntimeMetadataFilename = '.pyrite-runtime.json';

/// Target metadata read from a packaged plugin (.pyrix).
class PluginPackageTarget {
  const PluginPackageTarget({
    this.declaredPlatforms = const [],
    this.packagePlatform,
    this.packageArchitectures = const [],
  });

  /// Platforms declared in plugin.toml (`windows`, `linux`, `macos`,
  /// `android`). An empty list means the plugin declares no restriction.
  final List<String> declaredPlatforms;

  /// Target platform from the packaged runtime metadata (`Windows`, `Linux`,
  /// `Darwin`, `Android`), or null when the package carries no runtime
  /// metadata (older packages or `package --skip-site-packages`).
  final String? packagePlatform;

  /// Target architectures from the packaged runtime metadata (`x86_64`,
  /// `arm64`, `arm64-v8a`, `armeabi-v7a`). An empty list means the package was
  /// built for the packager host's default architecture (Windows/Linux
  /// desktop), which runs on any matching OS build.
  final List<String> packageArchitectures;
}

/// The OS + architecture the IDE is currently running on.
class PluginHostTarget {
  const PluginHostTarget({required this.os, required this.architecture});

  factory PluginHostTarget.current() => PluginHostTarget(
    os: Platform.operatingSystem,
    architecture: currentArchitecture(),
  );

  final String os;
  final String architecture;

  /// Architecture of the running Dart VM, mapped to the identifiers the
  /// pyrite-sdk packager uses (`x86_64`, `arm64`, `arm64-v8a`, ...).
  static String currentArchitecture() {
    switch (Abi.current().toString()) {
      case 'windows_x64':
      case 'macos_x64':
      case 'linux_x64':
      case 'android_x64':
        return 'x86_64';
      case 'windows_arm64':
      case 'macos_arm64':
      case 'linux_arm64':
        return 'arm64';
      case 'android_arm64':
        return 'arm64-v8a';
      case 'android_arm':
        return 'armeabi-v7a';
      case 'android_ia32':
        return 'x86';
      case 'linux_arm':
        return 'armv7';
      default:
        return Abi.current().toString();
    }
  }

  String get _osDisplayName => switch (os) {
    'windows' => 'Windows',
    'macos' => 'macOS',
    'linux' => 'Linux',
    'android' => 'Android',
    _ => os,
  };

  String get displayName => '$_osDisplayName ($architecture)';
}

/// Result of comparing a plugin package's target against the running host.
class PluginPackageCompatibility {
  const PluginPackageCompatibility({
    required this.target,
    required this.host,
    required this.platformMatches,
    required this.architectureMatches,
  });

  final PluginPackageTarget target;
  final PluginHostTarget host;
  final bool platformMatches;
  final bool architectureMatches;

  bool get matches => platformMatches && architectureMatches;

  /// Human-readable description of what the package was built for, preferring
  /// the runtime metadata (which reflects how dependencies were compiled) over
  /// the manifest's declared platform list.
  String get targetDescription {
    final platform = target.packagePlatform;
    if (platform != null) {
      final architectures = target.packageArchitectures;
      return architectures.isEmpty
          ? platform
          : '$platform (${architectures.join(', ')})';
    }
    return target.declaredPlatforms.isEmpty
        ? host._osDisplayName
        : target.declaredPlatforms.join(', ');
  }

  String get hostDescription => host.displayName;
}

/// Maps a host OS (`Platform.operatingSystem`) to the platform name the
/// packager stores in `.pyrite-runtime.json`.
String? runtimeMetadataPlatformForOs(String os) => switch (os) {
  'windows' => 'Windows',
  'linux' => 'Linux',
  'macos' => 'Darwin',
  'android' => 'Android',
  _ => null,
};

PluginPackageCompatibility evaluatePluginPackageCompatibility(
  PluginPackageTarget target,
  PluginHostTarget host,
) {
  // Manifest check: an empty platforms list declares no restriction.
  final manifestMatches =
      target.declaredPlatforms.isEmpty ||
      target.declaredPlatforms.contains(host.os);

  // Runtime metadata check: `Darwin` vs `macos` naming etc.
  final metadataPlatform = runtimeMetadataPlatformForOs(host.os);
  final metadataMatches =
      metadataPlatform == null ||
      target.packagePlatform == null ||
      target.packagePlatform == metadataPlatform;

  // Architecture check: empty means the package was built for the packager
  // host's default and does not constrain the consumer architecture.
  final architectureMatches =
      target.packageArchitectures.isEmpty ||
      target.packageArchitectures.contains(host.architecture);

  return PluginPackageCompatibility(
    target: target,
    host: host,
    platformMatches: manifestMatches && metadataMatches,
    architectureMatches: architectureMatches,
  );
}

/// Reads the target metadata of a packaged plugin without extracting it.
///
/// Returns null when the package cannot be read as a zip, so the caller falls
/// back to the real install flow which surfaces the actual packaging error.
Future<PluginPackageCompatibility?> inspectPluginPackageCompatibility(
  String packagePath,
) async {
  try {
    final target = await _readPluginPackageTarget(packagePath);
    return evaluatePluginPackageCompatibility(
      target,
      PluginHostTarget.current(),
    );
  } catch (_) {
    // An unreadable package is rejected by the installer with the real error;
    // skipping the prompt here keeps that message authoritative.
    return null;
  }
}

Future<PluginPackageTarget> _readPluginPackageTarget(String packagePath) async {
  final stream = InputFileStream(packagePath);
  try {
    final archive = ZipDecoder().decodeStream(stream);
    List<String>? declaredPlatforms;
    String? packagePlatform;
    var packageArchitectures = const <String>[];

    for (final entry in archive.files) {
      final name = entry.name;
      if (name == 'plugin.toml') {
        declaredPlatforms = _parseDeclaredPlatforms(entry.content);
      } else if (name == pluginRuntimeMetadataFilename) {
        final metadata = _parseRuntimeMetadata(entry.content);
        packagePlatform = metadata.$1;
        packageArchitectures = metadata.$2;
      }
    }
    return PluginPackageTarget(
      declaredPlatforms: declaredPlatforms ?? const [],
      packagePlatform: packagePlatform,
      packageArchitectures: packageArchitectures,
    );
  } finally {
    stream.close();
  }
}

List<String> _parseDeclaredPlatforms(List<int> bytes) {
  try {
    final map = TomlDocument.parse(utf8.decode(bytes)).toMap();
    final platforms = map['platforms'];
    if (platforms is List) {
      return platforms.whereType<String>().toList();
    }
  } catch (_) {
    // Invalid manifests are reported by the installer.
  }
  return const [];
}

(String?, List<String>) _parseRuntimeMetadata(List<int> bytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) return (null, const []);
    final target = decoded['target'];
    if (target is! Map) return (null, const []);
    final platform = target['platform'];
    final architectures = target['architectures'];
    return (
      platform is String ? platform : null,
      architectures is List
          ? architectures.whereType<String>().toList()
          : const <String>[],
    );
  } catch (_) {
    // Malformed metadata does not block installation.
  }
  return (null, const []);
}
