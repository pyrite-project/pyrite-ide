import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_package_compatibility.dart';

const _supportedMetadataPlatforms = {'Windows', 'Linux', 'Darwin', 'Android'};
const _sdkArchitectures = {'x86_64', 'arm64', 'arm64-v8a', 'armeabi-v7a'};

const _manifestTemplate = '''
manifest_version = 2
id = "compat-test-plugin"
name = "Compat Test"
version = "1.0.0"
type = "ui"
platforms = {platforms}
''';

String _manifestWithPlatforms(List<String> platforms) => _manifestTemplate
    .replaceAll('{platforms}', '[${platforms.map((p) => '"$p"').join(', ')}]');

String _runtimeMetadata(String platform, List<String> architectures) =>
    jsonEncode({
      'schema_version': 1,
      'runtime': {'implementation': 'cpython', 'python_version': '3.13'},
      'target': {'platform': platform, 'architectures': architectures},
    });

Future<File> _writePluginZip(
  Directory directory, {
  String? toml,
  String? metadata,
}) async {
  final archive = Archive();
  if (toml != null) {
    archive.addFile(ArchiveFile.string('plugin.toml', toml));
  }
  if (metadata != null) {
    archive.addFile(
      ArchiveFile.string(pluginRuntimeMetadataFilename, metadata),
    );
  }
  final file = File('${directory.path}${Platform.pathSeparator}plugin.pyrix');
  await file.writeAsBytes(ZipEncoder().encode(archive));
  return file;
}

void main() {
  final host = PluginHostTarget.current();

  PluginPackageTarget packageTarget({
    List<String> platforms = const [],
    String? metadataPlatform,
    List<String> metadataArchitectures = const [],
  }) => PluginPackageTarget(
    declaredPlatforms: platforms,
    packagePlatform: metadataPlatform,
    packageArchitectures: metadataArchitectures,
  );

  group('evaluatePluginPackageCompatibility', () {
    test('no declared constraints always matches', () {
      final compatibility = evaluatePluginPackageCompatibility(
        packageTarget(),
        host,
      );
      expect(compatibility.matches, isTrue);
    });

    test('manifest listing the host OS matches', () {
      final compatibility = evaluatePluginPackageCompatibility(
        packageTarget(platforms: [host.os, 'other-os']),
        host,
      );
      expect(compatibility.platformMatches, isTrue);
      expect(compatibility.matches, isTrue);
    });

    test('manifest without the host OS does not match', () {
      final missing = _supportedMetadataPlatforms
          .map(
            (platform) => platform.toLowerCase() == 'darwin'
                ? 'macos'
                : platform.toLowerCase(),
          )
          .where((platform) => platform != host.os)
          .first;
      final compatibility = evaluatePluginPackageCompatibility(
        packageTarget(platforms: [missing]),
        host,
      );
      expect(compatibility.platformMatches, isFalse);
      expect(compatibility.matches, isFalse);
    });

    test('runtime metadata platform must match the host OS', () {
      final otherPlatform = _supportedMetadataPlatforms
          .where((platform) => platform != runtimeMetadataPlatformForOs(host.os))
          .first;
      final compatibility = evaluatePluginPackageCompatibility(
        packageTarget(metadataPlatform: otherPlatform),
        host,
      );
      expect(compatibility.platformMatches, isFalse);
    });

    test('runtime metadata architectures must contain the host arch', () {
      final otherArchitecture = _sdkArchitectures
          .where((architecture) => architecture != host.architecture)
          .first;
      final compatibility = evaluatePluginPackageCompatibility(
        packageTarget(
          metadataPlatform: runtimeMetadataPlatformForOs(host.os),
          metadataArchitectures: [otherArchitecture],
        ),
        host,
      );
      expect(compatibility.architectureMatches, isFalse);
      expect(compatibility.matches, isFalse);
    });

    test('empty metadata architectures impose no arch constraint', () {
      final compatibility = evaluatePluginPackageCompatibility(
        packageTarget(
          metadataPlatform: runtimeMetadataPlatformForOs(host.os),
        ),
        host,
      );
      expect(compatibility.architectureMatches, isTrue);
      expect(compatibility.matches, isTrue);
    });
  });

  group('inspectPluginPackageCompatibility', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pyrite_compat_test');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('reads manifest platforms and runtime metadata from a package', () async {
      final package = await _writePluginZip(
        tempDir,
        toml: _manifestWithPlatforms([host.os, 'linux']),
        metadata: _runtimeMetadata(
          runtimeMetadataPlatformForOs(host.os)!,
          [host.architecture],
        ),
      );

      final compatibility = await inspectPluginPackageCompatibility(
        package.path,
      );

      expect(compatibility, isNotNull);
      expect(compatibility!.matches, isTrue);
      expect(compatibility.target.declaredPlatforms, contains(host.os));
      expect(
        compatibility.targetDescription,
        contains(runtimeMetadataPlatformForOs(host.os)!),
      );
      expect(compatibility.targetDescription, contains(host.architecture));
      expect(compatibility.hostDescription, contains(host.architecture));
    });

    test('flags a package built for another architecture', () async {
      final otherArchitecture = _sdkArchitectures
          .where((architecture) => architecture != host.architecture)
          .first;
      final package = await _writePluginZip(
        tempDir,
        metadata: _runtimeMetadata(
          runtimeMetadataPlatformForOs(host.os)!,
          [otherArchitecture],
        ),
      );

      final compatibility = await inspectPluginPackageCompatibility(
        package.path,
      );

      expect(compatibility, isNotNull);
      expect(compatibility!.matches, isFalse);
      expect(compatibility.architectureMatches, isFalse);
    });

    test('packages without runtime metadata fall back to the manifest', () async {
      final package = await _writePluginZip(
        tempDir,
        toml: _manifestWithPlatforms(['windows', 'linux']),
      );

      final compatibility = await inspectPluginPackageCompatibility(
        package.path,
      );

      expect(compatibility, isNotNull);
      expect(compatibility!.platformMatches, host.os == 'windows');
      expect(compatibility.targetDescription, contains('windows'));
    });

    test('an unreadable package yields null so install reports the error', () async {
      final compatibility = await inspectPluginPackageCompatibility(
        '${tempDir.path}${Platform.pathSeparator}missing.pyrix',
      );
      expect(compatibility, isNull);
    });
  });
}
