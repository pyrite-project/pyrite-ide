import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/plugin_install_link.dart';
import 'package:pyrite_ide/core/sdk/plugin_package_paths.dart';

const _requestTimeout = Duration(seconds: 20);
const _maxMetadataBytes = 1024 * 1024;
const _maxPackageBytes = 200 * 1024 * 1024;
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

enum PluginRegistryErrorCode {
  unreachable,
  notFound,
  unavailable,
  badResponse,
  tooLarge,
  hashMismatch,
}

class PluginRegistryException implements Exception {
  const PluginRegistryException(this.code, this.message);

  final PluginRegistryErrorCode code;
  final String message;

  @override
  String toString() => 'PluginRegistryException(${code.name}): $message';
}

/// The registry's standing for a release: what the site operators have said
/// about it (deprecation, advisories, withdrawal).
class PluginModeration {
  const PluginModeration({
    required this.level,
    this.severity,
    this.message,
    this.scope,
  });

  factory PluginModeration.fromJson(Object? json) {
    if (json is! Map<String, dynamic> || json['level'] is! String) {
      return const PluginModeration(level: 'none');
    }
    return PluginModeration(
      level: json['level'] as String,
      severity: json['severity'] as String?,
      message: json['message'] as String?,
      scope: json['scope'] as String?,
    );
  }

  /// none, notice, deprecated, advisory, withdrawn, delisted or takedown.
  final String level;
  final String? severity;
  final String? message;
  final String? scope;

  bool get isFlagged => level != 'none';

  Map<String, Object?> toJson() => {
    'level': level,
    'severity': severity,
    'message': message,
    'scope': scope,
  };

  @override
  bool operator ==(Object other) =>
      other is PluginModeration &&
      other.level == level &&
      other.severity == severity &&
      other.message == message &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(level, severity, message, scope);

  /// High and critical advisories must be read and confirmed before install.
  bool get requiresAcknowledgement =>
      level == 'advisory' && (severity == 'high' || severity == 'critical');
}

/// The registry's current standing for one release a user has installed.
class PluginAdvisory {
  const PluginAdvisory({
    required this.pluginId,
    required this.version,
    required this.installable,
    required this.moderation,
  });

  factory PluginAdvisory.fromJson(Map<String, dynamic> json) {
    final pluginId = json['ext_id'];
    final version = json['version'];
    if (pluginId is! String || version is! String) {
      throw const PluginRegistryException(
        PluginRegistryErrorCode.badResponse,
        'An advisory is incomplete',
      );
    }
    return PluginAdvisory(
      pluginId: pluginId,
      version: version,
      installable: json['installable'] != false,
      moderation: PluginModeration.fromJson(json['moderation']),
    );
  }

  final String pluginId;
  final String version;

  /// False once the release was withdrawn, delisted or taken down.
  final bool installable;
  final PluginModeration moderation;

  /// Whether the user should be told about it.
  bool get isFlagged => moderation.isFlagged || !installable;

  Map<String, Object?> toJson() => {
    'ext_id': pluginId,
    'version': version,
    'installable': installable,
    'moderation': moderation.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is PluginAdvisory &&
      other.pluginId == pluginId &&
      other.version == version &&
      other.installable == installable &&
      other.moderation == moderation;

  @override
  int get hashCode => Object.hash(pluginId, version, installable, moderation);
}

class PluginRegistryRelease {
  const PluginRegistryRelease({
    required this.pluginId,
    required this.name,
    required this.version,
    required this.sha256,
    required this.size,
    required this.type,
    required this.platforms,
    required this.permissions,
    required this.installable,
    required this.moderation,
    this.author,
  });

  factory PluginRegistryRelease.fromJson(Map<String, dynamic> json) {
    final sha256 = json['sha256'];
    final size = json['size'];
    final pluginId = json['ext_id'];
    final version = json['version'];
    if (pluginId is! String ||
        version is! String ||
        sha256 is! String ||
        !_sha256Pattern.hasMatch(sha256) ||
        size is! int ||
        size <= 0) {
      throw const PluginRegistryException(
        PluginRegistryErrorCode.badResponse,
        'The release description is incomplete',
      );
    }
    List<String> strings(Object? value) =>
        value is List ? value.whereType<String>().toList() : const [];

    return PluginRegistryRelease(
      pluginId: pluginId,
      name: json['name'] is String ? json['name'] as String : pluginId,
      version: version,
      sha256: sha256,
      size: size,
      type: json['type'] as String?,
      platforms: strings(json['platforms']),
      permissions: strings(json['permissions']),
      author: json['author'] as String?,
      installable: json['installable'] == true,
      moderation: PluginModeration.fromJson(json['moderation']),
    );
  }

  final String pluginId;
  final String name;
  final String version;
  final String sha256;
  final int size;
  final String? type;
  final String? author;
  final List<String> platforms;
  final List<String> permissions;
  final bool installable;
  final PluginModeration moderation;
}

/// Talks to a registry site. Every URL is built here from the validated intent;
/// nothing the server returns is ever followed as a download address.
class PluginRegistryClient {
  PluginRegistryClient({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  Uri _releaseUri(RegistryInstallIntent intent) => Uri.parse(
    '${intent.origin}/pyrite/api/v1/extensions/${intent.pluginId}'
    '/versions/${intent.version}',
  );

  Future<PluginRegistryRelease> fetchRelease(
    RegistryInstallIntent intent,
  ) async {
    final json = await _getJson(_releaseUri(intent));
    final release = PluginRegistryRelease.fromJson(json);
    if (release.pluginId != intent.pluginId ||
        release.version != intent.version) {
      throw const PluginRegistryException(
        PluginRegistryErrorCode.badResponse,
        'The registry described a different release',
      );
    }
    return release;
  }

  /// Asks [origin] for the current standing of the given releases. Releases the
  /// registry does not know are simply absent from the answer.
  Future<List<PluginAdvisory>> fetchAdvisories(
    String origin,
    List<({String pluginId, String version})> releases,
  ) async {
    final uri = Uri.parse('$origin/pyrite/api/v1/advisories').replace(
      queryParameters: {
        'releases': releases.map((r) => '${r.pluginId}@${r.version}').join(','),
      },
    );
    final json = await _getJson(uri);
    final entries = json['advisories'];
    if (entries is! List) {
      throw const PluginRegistryException(
        PluginRegistryErrorCode.badResponse,
        'The registry returned an unexpected document',
      );
    }
    return [
      for (final entry in entries.whereType<Map<String, dynamic>>())
        PluginAdvisory.fromJson(entry),
    ];
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = _clientFactory()..connectionTimeout = _requestTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_requestTimeout);
      _checkStatus(response.statusCode);

      final body = await _readBounded(response, _maxMetadataBytes);
      final Object? json;
      try {
        json = jsonDecode(utf8.decode(body));
      } on FormatException {
        throw const PluginRegistryException(
          PluginRegistryErrorCode.badResponse,
          'The registry did not return JSON',
        );
      }
      if (json is! Map<String, dynamic>) {
        throw const PluginRegistryException(
          PluginRegistryErrorCode.badResponse,
          'The registry returned an unexpected document',
        );
      }
      return json;
    } on SocketException catch (error) {
      throw PluginRegistryException(
        PluginRegistryErrorCode.unreachable,
        error.message,
      );
    } on TimeoutException {
      throw const PluginRegistryException(
        PluginRegistryErrorCode.unreachable,
        'The registry did not answer in time',
      );
    } on HandshakeException catch (error) {
      throw PluginRegistryException(
        PluginRegistryErrorCode.unreachable,
        error.message,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads the release into [directory] and returns the verified file.
  ///
  /// The file is deleted again if it is larger than announced or does not match
  /// the SHA-256 the registry published.
  Future<File> downloadPackage(
    RegistryInstallIntent intent,
    PluginRegistryRelease release,
    Directory directory,
  ) async {
    if (release.size > _maxPackageBytes) {
      throw const PluginRegistryException(
        PluginRegistryErrorCode.tooLarge,
        'The package is larger than the IDE accepts',
      );
    }
    await directory.create(recursive: true);
    final target = File(
      path.join(
        directory.path,
        '${pluginDirectoryFor(intent.pluginId)}-${intent.version}.pyrix',
      ),
    );
    final client = _clientFactory()..connectionTimeout = _requestTimeout;
    try {
      final request = await client
          .getUrl(Uri.parse('${_releaseUri(intent)}/package.pyrix'))
          .timeout(_requestTimeout);
      final response = await request.close().timeout(_requestTimeout);
      _checkStatus(response.statusCode);

      final sink = target.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          if (received > release.size) {
            throw const PluginRegistryException(
              PluginRegistryErrorCode.tooLarge,
              'The package is larger than announced',
            );
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }

      final digest = (await sha256.bind(target.openRead()).first).toString();
      if (received != release.size || digest != release.sha256) {
        throw const PluginRegistryException(
          PluginRegistryErrorCode.hashMismatch,
          'The downloaded package does not match its published checksum',
        );
      }
      return target;
    } on SocketException catch (error) {
      await _discard(target);
      throw PluginRegistryException(
        PluginRegistryErrorCode.unreachable,
        error.message,
      );
    } on TimeoutException {
      await _discard(target);
      throw const PluginRegistryException(
        PluginRegistryErrorCode.unreachable,
        'The registry did not answer in time',
      );
    } on PluginRegistryException {
      await _discard(target);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  void _checkStatus(int status) {
    if (status == HttpStatus.ok) return;
    if (status == HttpStatus.notFound) {
      throw const PluginRegistryException(
        PluginRegistryErrorCode.notFound,
        'The registry has no such release',
      );
    }
    if (status == HttpStatus.gone) {
      throw const PluginRegistryException(
        PluginRegistryErrorCode.unavailable,
        'The release is no longer available',
      );
    }
    throw PluginRegistryException(
      PluginRegistryErrorCode.badResponse,
      'The registry answered with status $status',
    );
  }

  Future<List<int>> _readBounded(Stream<List<int>> stream, int limit) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (bytes.length > limit) {
        throw const PluginRegistryException(
          PluginRegistryErrorCode.badResponse,
          'The registry response is too large',
        );
      }
    }
    return bytes;
  }

  Future<void> _discard(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Leftover temp files are cleared with the staging directory.
    }
  }
}
