import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:toml/toml.dart';

class PluginPersistedData {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String type;
  final Map<String, List<String>> declaredPermissions;
  final Map<String, List<String>> permissions;
  final List<String> platforms;
  final String status;
  final bool autoStart;

  PluginPersistedData({
    required this.id,
    required this.name,
    this.version = '0.0.0',
    this.author = '',
    this.description = '',
    this.type = 'ui',
    this.declaredPermissions = const {},
    this.permissions = const {},
    this.platforms = const [],
    this.status = 'usable',
    this.autoStart = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'author': author,
        'description': description,
        'type': type,
        'declaredPermissions': declaredPermissions,
        'permissions': permissions,
        'platforms': platforms,
        'status': status,
        'autoStart': autoStart,
      };

  factory PluginPersistedData.fromJson(Map<String, dynamic> json) {
    Map<String, List<String>> _parsePerms(dynamic raw) {
      if (raw is Map<String, dynamic>) {
        return raw.map((k, v) => MapEntry(
              k,
              (v as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
            ));
      } else if (raw is List<dynamic>) {
        return {for (final p in raw) p.toString(): ['*']};
      }
      return <String, List<String>>{};
    }

    return PluginPersistedData(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String? ?? '0.0.0',
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'ui',
      declaredPermissions: _parsePerms(json['declaredPermissions']),
      permissions: _parsePerms(json['permissions']),
      platforms: (json['platforms'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      status: json['status'] as String? ?? 'usable',
      autoStart: json['autoStart'] as bool? ?? false,
    );
  }

  Plugin toPlugin() {
    final effectiveDeclared =
        declaredPermissions.isNotEmpty ? declaredPermissions : permissions;
    return Plugin(
      id: id,
      name: name,
      version: version,
      author: author,
      description: description,
      type: PluginType.values.firstWhere(
        (e) => e.name == type,
        orElse: () => PluginType.ui,
      ),
      status: PluginStatus.values.firstWhere(
        (e) => e.name == status,
        orElse: () => PluginStatus.usable,
      ),
      declaredPermissions: effectiveDeclared,
      permissions: permissions,
      platforms: platforms,
      autoStart: autoStart,
    );
  }

  static PluginPersistedData fromPlugin(Plugin plugin) => PluginPersistedData(
        id: plugin.id,
        name: plugin.name,
        version: plugin.version,
        author: plugin.author,
        description: plugin.description,
        type: plugin.type.name,
        declaredPermissions: plugin.declaredPermissions,
        permissions: plugin.permissions,
        platforms: plugin.platforms,
        status: plugin.status.name,
        autoStart: plugin.autoStart,
      );
}

class PluginPersistence {
  static const _fileName = 'plugins.json';

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    final subDir = Directory('${dir.path}/data');
    if (!await subDir.exists()) await subDir.create(recursive: true);
    return File('${subDir.path}/$_fileName');
  }

  Future<List<PluginPersistedData>?> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final list = json['plugins'] as List<dynamic>? ?? [];
      return list
          .map((e) => PluginPersistedData.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('PluginPersistence: Failed to load: $e');
      return null;
    }
  }

  Future<void> save(List<Plugin> plugins) async {
    try {
      final file = await _file;
      final data = plugins.map(PluginPersistedData.fromPlugin).toList();
      await file.writeAsString(jsonEncode({
        'plugins': data.map((e) => e.toJson()).toList(),
      }));
    } catch (e) {
      debugPrint('PluginPersistence: Failed to save: $e');
    }
  }
}

class PluginTomlParser {
  static const Map<String, List<String>> _resourceActions = {
    'ui': ['view', 'navigate'],
    'file': ['read', 'write'],
    'board': ['read', 'write'],
    'serial': ['read', 'write'],
    'editor': ['read', 'write'],
    'persistence': ['read', 'write'],
    'tab': ['create', 'manage'],
    'settings': ['read', 'write'],
    'data': ['read', 'write'],
  };

  static const List<String> _allActions = ['read', 'write'];

  static PluginPersistedData? parseFromZip(String zipPath) {
    try {
      final archive = ZipDecoder().decodeStream(InputFileStream(zipPath));
      for (final file in archive) {
        if (file.isFile && file.name.endsWith('plugin.toml')) {
          final content = String.fromCharCodes(file.content as List<int>);
          return _parseTomlString(content);
        }
      }
      return null;
    } catch (e) {
      debugPrint('PluginTomlParser: Failed to parse zip: $e');
      return null;
    }
  }

  static PluginPersistedData? parseFromDirectory(Directory pluginDir) {
    try {
      final tomlFile = File('${pluginDir.path}/plugin.toml');
      if (!tomlFile.existsSync()) return null;
      return parseFromFileSync(tomlFile);
    } catch (e) {
      debugPrint('PluginTomlParser: Failed to parse directory: $e');
      return null;
    }
  }

  static PluginPersistedData? parseFromFileSync(File tomlFile) {
    try {
      final contents = tomlFile.readAsStringSync();
      return _parseTomlString(contents);
    } catch (e) {
      debugPrint('PluginTomlParser: Failed to parse TOML file: $e');
      return null;
    }
  }

  static PluginPersistedData? _parseTomlString(String contents) {
    try {
      final doc = TomlDocument.parse(contents);
      final map = doc.toMap();

      final general = map['general'] as Map<String, dynamic>? ?? {};
      final permissions =
          map['permissions'] as Map<String, dynamic>? ?? {};
      final platform = map['platform'] as Map<String, dynamic>? ?? {};

      const Map<String, String> permissionNameMap = {
        'workspace': 'file',
        'board_manager': 'board',
      };

      final parsedPermissions = <String, List<String>>{};
      for (final entry in permissions.entries) {
        final value = entry.value;
        final resourceName = permissionNameMap[entry.key] ?? entry.key;
        if (value == true) {
          parsedPermissions[resourceName] =
              List.from(_resourceActions[resourceName] ?? _allActions);
        } else if (value == false) {
          // skip
        } else if (value is List) {
          parsedPermissions[resourceName] =
              value.map((e) => e.toString()).toList();
        }
      }

      return PluginPersistedData(
        id: general['id'] as String? ?? '',
        name: general['name'] as String? ?? '',
        version: general['version'] as String? ?? '0.0.0',
        author: general['author'] as String? ?? '',
        description: general['description'] as String? ?? '',
        type: general['type'] as String? ?? 'ui',
        permissions: parsedPermissions,
        platforms: platform.entries
            .where((e) => e.value == true)
            .map((e) => e.key)
            .toList(),
        autoStart: general['auto_start'] as bool? ?? false,
      );
    } catch (e) {
      debugPrint('PluginTomlParser: Failed to parse TOML: $e');
      return null;
    }
  }
}
