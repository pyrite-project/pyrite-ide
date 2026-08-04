import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
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
  final bool permissionGrantsInitialized;
  final List<String> platforms;
  final String status;
  final bool autoStart;
  final PluginManifestV2? manifest;
  final String rawManifest;
  final String? manifestErrorCode;

  PluginPersistedData({
    required this.id,
    required this.name,
    this.version = '0.0.0',
    this.author = '',
    this.description = '',
    this.type = 'ui',
    this.declaredPermissions = const {},
    this.permissions = const {},
    this.permissionGrantsInitialized = true,
    this.platforms = const [],
    this.status = 'usable',
    this.autoStart = false,
    this.manifest,
    this.rawManifest = '',
    this.manifestErrorCode,
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
    'permissionGrantsInitialized': permissionGrantsInitialized,
    'platforms': platforms,
    'status': status,
    'autoStart': autoStart,
    'rawManifest': rawManifest,
    if (manifest != null) 'normalizedManifest': manifest!.toJson(),
    if (manifestErrorCode != null) 'manifestErrorCode': manifestErrorCode,
  };

  factory PluginPersistedData.fromJson(Map<String, dynamic> json) {
    Map<String, List<String>> parsePerms(dynamic raw) {
      if (raw is Map<String, dynamic>) {
        return raw.map((k, v) {
          final actions =
              (v as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          return MapEntry(
            k,
            k == 'dialog' && actions.isNotEmpty ? ['show'] : actions,
          );
        });
      } else if (raw is List<dynamic>) {
        return {
          for (final p in raw) p.toString(): ['*'],
        };
      }
      return <String, List<String>>{};
    }

    PluginManifestV2? manifest;
    String? manifestErrorCode = json['manifestErrorCode'] as String?;
    final normalizedManifest = json['normalizedManifest'];
    if (normalizedManifest is Map) {
      try {
        manifest = PluginManifestV2.fromJson(
          Map<String, dynamic>.from(normalizedManifest),
        );
        manifestErrorCode = null;
      } on PluginManifestException catch (error) {
        manifestErrorCode = error.code;
      } catch (_) {
        manifestErrorCode = PluginManifestErrorCode.invalidSchema;
      }
    } else {
      manifestErrorCode ??= PluginManifestErrorCode.missingVersion;
    }

    return PluginPersistedData(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String? ?? '0.0.0',
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'ui',
      declaredPermissions: parsePerms(json['declaredPermissions']),
      permissions: parsePerms(json['permissions']),
      permissionGrantsInitialized: json['permissionGrantsInitialized'] == true,
      platforms:
          (json['platforms'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      status: manifest == null
          ? PluginStatus.disabled.name
          : json['status'] as String? ?? 'usable',
      autoStart: json['autoStart'] as bool? ?? false,
      manifest: manifest,
      rawManifest: json['rawManifest'] as String? ?? '',
      manifestErrorCode: manifestErrorCode,
    );
  }

  Plugin toPlugin() {
    final normalized = manifest;
    final effectiveDeclared =
        normalized?.permissionsByResource ??
        (declaredPermissions.isNotEmpty ? declaredPermissions : permissions);
    final effectivePermissions = normalized == null
        ? <String, List<String>>{}
        : permissionGrantsInitialized
        ? restrictPluginPermissions(permissions, effectiveDeclared)
        : effectiveDeclared;
    return Plugin(
      id: normalized?.id ?? id,
      name: normalized?.name ?? name,
      version: normalized?.version ?? version,
      author: normalized?.author ?? author,
      description: normalized?.description ?? description,
      type:
          normalized?.type ??
          PluginType.values.firstWhere(
            (e) => e.name == type,
            orElse: () => PluginType.ui,
          ),
      status: PluginStatus.values.firstWhere(
        (e) => e.name == (normalized == null ? 'disabled' : status),
        orElse: () => PluginStatus.usable,
      ),
      declaredPermissions: effectiveDeclared,
      permissions: effectivePermissions,
      platforms: normalized?.platforms ?? platforms,
      autoStart: normalized?.autoStart ?? autoStart,
      manifest: normalized,
      rawManifest: rawManifest,
      manifestErrorCode: manifestErrorCode,
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
    manifest: plugin.manifest,
    rawManifest: plugin.rawManifest,
    manifestErrorCode: plugin.manifestErrorCode,
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
    final file = await _file;
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final list = json['plugins'] as List<dynamic>? ?? [];
    return list
        .map((e) => PluginPersistedData.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<Plugin> plugins) async {
    final file = await _file;
    final temp = File('${file.path}.tmp');
    final data = plugins.map(PluginPersistedData.fromPlugin).toList();
    await temp.writeAsString(
      jsonEncode({'plugins': data.map((e) => e.toJson()).toList()}),
      flush: true,
    );
    await temp.rename(file.path);
  }
}

class PluginTomlParser {
  static const _topLevelFields = {
    'manifest_version',
    'id',
    'name',
    'version',
    'type',
    'protocol_version',
    'python_version',
    'author',
    'description',
    'icons',
    'activation_events',
    'permissions',
    'platforms',
    'contributes',
  };

  static PluginPersistedData parseFromDirectory(Directory pluginDir) {
    final parsed = parseFromFileSync(File('${pluginDir.path}/plugin.toml'));
    final manifest = parsed.manifest;
    if (manifest != null) _validateAssetFiles(pluginDir, manifest);
    return parsed;
  }

  static void _validateAssetFiles(
    Directory pluginDir,
    PluginManifestV2 manifest,
  ) {
    final assets = <String>[
      if (manifest.icons case final icons?) ...[icons.full, icons.monochrome],
      for (final icon in [
        ...manifest.contributes.navigationContainers.map((item) => item.icon),
        ...manifest.contributes.views.map((item) => item.icon),
        ...manifest.contributes.commands.map((item) => item.icon),
      ])
        if (icon?.kind == PluginIconKind.asset) icon!.value,
    ];
    final root = path.normalize(path.absolute(pluginDir.path));
    for (final asset in assets) {
      final candidate = path.normalize(path.absolute(path.join(root, asset)));
      final relative = path.relative(candidate, from: root);
      final contained =
          relative != '..' &&
          !relative.startsWith('..${path.separator}') &&
          !path.isAbsolute(relative);
      if (!contained ||
          FileSystemEntity.typeSync(candidate, followLinks: false) !=
              FileSystemEntityType.file) {
        throw PluginManifestException(
          PluginManifestErrorCode.invalidSchema,
          'Declared plugin asset is missing or invalid: $asset',
        );
      }
    }
  }

  static PluginPersistedData parseFromFileSync(File tomlFile) {
    if (!tomlFile.existsSync()) {
      throw const PluginManifestException(
        PluginManifestErrorCode.missingManifest,
        'plugin.toml is missing',
      );
    }
    try {
      return parse(tomlFile.readAsStringSync());
    } on PluginManifestException {
      rethrow;
    } catch (error) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidToml,
        'Unable to read plugin.toml: $error',
      );
    }
  }

  static PluginPersistedData parse(String contents) {
    late final Map<String, dynamic> map;
    try {
      map = TomlDocument.parse(contents).toMap();
    } catch (error) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidToml,
        'Invalid plugin.toml: $error',
      );
    }

    if (!map.containsKey('manifest_version')) {
      throw const PluginManifestException(
        PluginManifestErrorCode.missingVersion,
        'manifest_version is required',
      );
    }
    final manifestVersion = _requiredInt(map, 'manifest_version', 'manifest');
    if (manifestVersion != 2) {
      throw PluginManifestException(
        PluginManifestErrorCode.unsupportedVersion,
        'Unsupported manifest version: $manifestVersion',
      );
    }
    _rejectUnknownFields(map, _topLevelFields, 'manifest');

    final typeName = _requiredString(map, 'type', 'manifest');
    final type = PluginType.values.where((value) => value.name == typeName);
    if (type.isEmpty) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        'Unsupported plugin type: $typeName',
      );
    }

    final contributesMap = _optionalTable(map, 'contributes', 'manifest');
    _rejectUnknownFields(contributesMap, const {
      'navigation_containers',
      'views',
      'commands',
      'menus',
      'configuration',
    }, 'contributes');
    final contributes = PluginContributions(
      navigationContainers: _tableList(
        contributesMap,
        'navigation_containers',
        'contributes',
      ).map(_parseNavigationContainer).toList(),
      views: _tableList(
        contributesMap,
        'views',
        'contributes',
      ).map(_parseView).toList(),
      commands: _tableList(
        contributesMap,
        'commands',
        'contributes',
      ).map(_parseCommand).toList(),
      menus: _tableList(
        contributesMap,
        'menus',
        'contributes',
      ).map(_parseMenu).toList(),
      configuration: _tableList(
        contributesMap,
        'configuration',
        'contributes',
      ).map(_parseConfiguration).toList(),
    );

    final manifest = PluginManifestV2(
      manifestVersion: manifestVersion,
      id: _requiredString(map, 'id', 'manifest'),
      name: _requiredString(map, 'name', 'manifest'),
      version: _requiredString(map, 'version', 'manifest'),
      type: type.single,
      protocolVersion: _requiredInt(map, 'protocol_version', 'manifest'),
      pythonVersion: _optionalString(map, 'python_version', 'manifest'),
      author: _optionalString(map, 'author', 'manifest') ?? '',
      description: _optionalString(map, 'description', 'manifest') ?? '',
      icons: _parseIcons(map),
      activationEvents: _stringList(map, 'activation_events', 'manifest'),
      permissions: _stringList(map, 'permissions', 'manifest'),
      platforms: _stringList(map, 'platforms', 'manifest'),
      contributes: contributes,
    );
    PluginManifestValidator().validate(manifest);
    final permissions = manifest.permissionsByResource;
    return PluginPersistedData(
      id: manifest.id,
      name: manifest.name,
      version: manifest.version,
      author: manifest.author,
      description: manifest.description,
      type: manifest.type.name,
      declaredPermissions: permissions,
      permissions: permissions,
      platforms: manifest.platforms,
      autoStart: manifest.autoStart,
      manifest: manifest,
      rawManifest: contents,
    );
  }

  static PluginNavigationContainerContribution _parseNavigationContainer(
    Map<String, dynamic> table,
  ) {
    const path = 'contributes.navigation_containers[]';
    _rejectUnknownFields(table, const {
      'id',
      'title',
      'icon',
      'location',
      'order',
      'when',
    }, path);
    return PluginNavigationContainerContribution(
      id: _requiredString(table, 'id', path),
      title: _requiredString(table, 'title', path),
      icon: _parseIcon(table['icon'], '$path.icon'),
      location: _optionalString(table, 'location', path) ?? 'primary',
      order: _optionalInt(table, 'order', path) ?? 0,
      when: _optionalExpression(table, 'when', path),
    );
  }

  static PluginViewContribution _parseView(Map<String, dynamic> table) {
    const path = 'contributes.views[]';
    _rejectUnknownFields(table, const {
      'id',
      'container',
      'title',
      'renderer',
      'icon',
      'order',
      'when',
    }, path);
    return PluginViewContribution(
      id: _requiredString(table, 'id', path),
      container: _requiredString(table, 'container', path),
      title: _requiredString(table, 'title', path),
      renderer: _requiredString(table, 'renderer', path),
      icon: _parseIcon(table['icon'], '$path.icon'),
      order: _optionalInt(table, 'order', path) ?? 0,
      when: _optionalExpression(table, 'when', path),
    );
  }

  static PluginCommandContribution _parseCommand(Map<String, dynamic> table) {
    const path = 'contributes.commands[]';
    _rejectUnknownFields(table, const {
      'id',
      'title',
      'icon',
      'order',
      'when',
    }, path);
    return PluginCommandContribution(
      id: _requiredString(table, 'id', path),
      title: _requiredString(table, 'title', path),
      icon: _parseIcon(table['icon'], '$path.icon'),
      order: _optionalInt(table, 'order', path) ?? 0,
      when: _optionalExpression(table, 'when', path),
    );
  }

  static PluginMenuContribution _parseMenu(Map<String, dynamic> table) {
    const path = 'contributes.menus[]';
    _rejectUnknownFields(table, const {
      'location',
      'command',
      'view',
      'group',
      'order',
      'when',
    }, path);
    return PluginMenuContribution(
      location: _requiredString(table, 'location', path),
      command: _requiredString(table, 'command', path),
      view: _optionalString(table, 'view', path),
      group: _optionalString(table, 'group', path),
      order: _optionalInt(table, 'order', path) ?? 0,
      when: _optionalExpression(table, 'when', path),
    );
  }

  static PluginConfigurationContribution _parseConfiguration(
    Map<String, dynamic> table,
  ) {
    const path = 'contributes.configuration[]';
    _rejectUnknownFields(table, const {
      'id',
      'title',
      'type',
      'description',
      'default',
      'enum',
      'order',
      'when',
    }, path);
    final enumValue = table['enum'];
    if (enumValue != null && enumValue is! List) {
      _schemaError('$path.enum must be an array');
    }
    return PluginConfigurationContribution(
      id: _requiredString(table, 'id', path),
      title: _requiredString(table, 'title', path),
      type: _requiredString(table, 'type', path),
      description: _optionalString(table, 'description', path) ?? '',
      defaultValue: table['default'],
      enumValues: (enumValue as List<dynamic>? ?? const []).cast<Object?>(),
      order: _optionalInt(table, 'order', path) ?? 0,
      when: _optionalExpression(table, 'when', path),
    );
  }

  static PluginIconSet? _parseIcons(Map<String, dynamic> map) {
    final table = map['icons'];
    if (table == null) return null;
    if (table is! Map) {
      throw const PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        'manifest.icons must be a table',
      );
    }
    final icons = Map<String, dynamic>.from(table);
    _rejectUnknownFields(icons, const {'full', 'monochrome'}, 'icons');
    return PluginIconSet(
      full: _requiredString(icons, 'full', 'icons'),
      monochrome: _requiredString(icons, 'monochrome', 'icons'),
    );
  }

  static PluginIconReference? _parseIcon(Object? value, String field) {
    if (value == null) return null;
    if (value is! Map) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        '$field must be a table containing material or asset',
      );
    }
    final table = Map<String, dynamic>.from(value);
    _rejectUnknownFields(table, const {'material', 'asset'}, field);
    if (table.length != 1) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        '$field must contain exactly one source',
      );
    }
    if (table.containsKey('material')) {
      return PluginIconReference.material(
        _requiredString(table, 'material', field),
      );
    }
    return PluginIconReference.asset(_requiredString(table, 'asset', field));
  }

  static List<Map<String, dynamic>> _tableList(
    Map<String, dynamic> table,
    String key,
    String path,
  ) {
    final value = table[key];
    if (value == null) return const [];
    if (value is! List) _schemaError('$path.$key must be an array of tables');
    final result = <Map<String, dynamic>>[];
    for (var index = 0; index < value.length; index++) {
      final entry = value[index];
      if (entry is! Map) {
        _schemaError('$path.$key[$index] must be a table');
      }
      result.add(Map<String, dynamic>.from(entry));
    }
    return result;
  }

  static Map<String, dynamic> _optionalTable(
    Map<String, dynamic> table,
    String key,
    String path,
  ) {
    final value = table[key];
    if (value == null) return const {};
    if (value is! Map) _schemaError('$path.$key must be a table');
    return Map<String, dynamic>.from(value);
  }

  static String _requiredString(
    Map<String, dynamic> table,
    String key,
    String path,
  ) {
    final value = table[key];
    if (value is! String || value.trim().isEmpty) {
      _schemaError('$path.$key must be a non-empty string');
    }
    return value;
  }

  static String? _optionalString(
    Map<String, dynamic> table,
    String key,
    String path,
  ) {
    final value = table[key];
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      _schemaError('$path.$key must be a non-empty string');
    }
    return value;
  }

  static String? _optionalExpression(
    Map<String, dynamic> table,
    String key,
    String path,
  ) {
    final value = table[key];
    if (value == null) return null;
    if (value is! String) _schemaError('$path.$key must be a string');
    return value;
  }

  static int _requiredInt(Map<String, dynamic> table, String key, String path) {
    final value = table[key];
    if (value is! int) _schemaError('$path.$key must be an integer');
    return value;
  }

  static int? _optionalInt(
    Map<String, dynamic> table,
    String key,
    String path,
  ) {
    final value = table[key];
    if (value == null) return null;
    if (value is! int) _schemaError('$path.$key must be an integer');
    return value;
  }

  static List<String> _stringList(
    Map<String, dynamic> table,
    String key,
    String path,
  ) {
    final value = table[key];
    if (value == null) return const [];
    if (value is! List || value.any((entry) => entry is! String)) {
      _schemaError('$path.$key must be an array of strings');
    }
    return value.cast<String>();
  }

  static void _rejectUnknownFields(
    Map<String, dynamic> table,
    Set<String> fields,
    String path,
  ) {
    for (final key in table.keys) {
      if (!fields.contains(key)) _schemaError('Unknown field: $path.$key');
    }
  }

  static Never _schemaError(String message) {
    throw PluginManifestException(
      PluginManifestErrorCode.invalidSchema,
      message,
    );
  }
}
