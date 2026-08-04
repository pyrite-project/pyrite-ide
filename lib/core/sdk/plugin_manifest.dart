import 'context_key_service.dart';
import 'material_icons.g.dart';

enum PluginType { ui, service, data }

enum PluginIconKind { material, asset }

class PluginIconReference {
  const PluginIconReference.material(this.value)
    : kind = PluginIconKind.material;

  const PluginIconReference.asset(this.value) : kind = PluginIconKind.asset;

  final PluginIconKind kind;
  final String value;

  Map<String, dynamic> toJson() => {kind.name: value};

  factory PluginIconReference.fromJson(Object? json) {
    if (json is! Map) {
      throw const PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        'Icon references must be tables',
      );
    }
    final map = Map<String, dynamic>.from(json);
    if (map.length != 1) {
      throw const PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        'Icon references must contain exactly one source',
      );
    }
    if (map['material'] case final String value) {
      return PluginIconReference.material(value);
    }
    if (map['asset'] case final String value) {
      return PluginIconReference.asset(value);
    }
    throw const PluginManifestException(
      PluginManifestErrorCode.invalidSchema,
      'Icon references must contain material or asset',
    );
  }
}

class PluginIconSet {
  const PluginIconSet({required this.full, required this.monochrome});

  final String full;
  final String monochrome;

  Map<String, dynamic> toJson() => {'full': full, 'monochrome': monochrome};

  factory PluginIconSet.fromJson(Map<String, dynamic> json) => PluginIconSet(
    full: json['full'] as String,
    monochrome: json['monochrome'] as String,
  );
}

abstract final class PluginManifestErrorCode {
  static const missingManifest = 'manifest_missing';
  static const invalidToml = 'manifest_invalid_toml';
  static const missingVersion = 'manifest_missing_version';
  static const unsupportedVersion = 'manifest_unsupported_version';
  static const invalidSchema = 'manifest_invalid_schema';
  static const invalidPluginId = 'manifest_invalid_plugin_id';
  static const invalidPermission = 'manifest_invalid_permission';
  static const invalidContributionId = 'manifest_invalid_contribution_id';
  static const contributionConflict = 'manifest_contribution_conflict';
  static const missingNavigationContainer =
      'manifest_missing_navigation_container';
  static const unknownRenderer = 'manifest_unknown_renderer';
  static const rfwRendererUnsupported = 'manifest_rfw_renderer_unsupported';
  static const invalidWhen = 'manifest_invalid_when';
  static const unknownIcon = 'manifest_unknown_icon';
  static const invalidActivationEvent = 'manifest_invalid_activation_event';
}

class PluginManifestException extends FormatException {
  const PluginManifestException(this.code, String message) : super(message);

  final String code;

  @override
  String toString() => 'PluginManifestException($code): $message';
}

class PluginNavigationContainerContribution {
  const PluginNavigationContainerContribution({
    required this.id,
    required this.title,
    this.icon,
    this.location = 'primary',
    this.order = 0,
    this.when,
  });

  final String id;
  final String title;
  final PluginIconReference? icon;
  final String location;
  final int order;
  final String? when;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (icon != null) 'icon': icon!.toJson(),
    'location': location,
    'order': order,
    if (when != null) 'when': when,
  };

  factory PluginNavigationContainerContribution.fromJson(
    Map<String, dynamic> json,
  ) => PluginNavigationContainerContribution(
    id: json['id'] as String,
    title: json['title'] as String,
    icon: json['icon'] == null
        ? null
        : PluginIconReference.fromJson(json['icon']),
    location: json['location'] as String? ?? 'primary',
    order: json['order'] as int? ?? 0,
    when: json['when'] as String?,
  );
}

class PluginViewContribution {
  const PluginViewContribution({
    required this.id,
    required this.container,
    required this.title,
    required this.renderer,
    this.icon,
    this.order = 0,
    this.when,
  });

  final String id;
  final String container;
  final String title;
  final String renderer;
  final PluginIconReference? icon;
  final int order;
  final String? when;

  Map<String, dynamic> toJson() => {
    'id': id,
    'container': container,
    'title': title,
    'renderer': renderer,
    if (icon != null) 'icon': icon!.toJson(),
    'order': order,
    if (when != null) 'when': when,
  };

  factory PluginViewContribution.fromJson(Map<String, dynamic> json) =>
      PluginViewContribution(
        id: json['id'] as String,
        container: json['container'] as String,
        title: json['title'] as String,
        renderer: json['renderer'] as String,
        icon: json['icon'] == null
            ? null
            : PluginIconReference.fromJson(json['icon']),
        order: json['order'] as int? ?? 0,
        when: json['when'] as String?,
      );
}

class PluginCommandContribution {
  const PluginCommandContribution({
    required this.id,
    required this.title,
    this.icon,
    this.order = 0,
    this.when,
  });

  final String id;
  final String title;
  final PluginIconReference? icon;
  final int order;
  final String? when;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (icon != null) 'icon': icon!.toJson(),
    'order': order,
    if (when != null) 'when': when,
  };

  factory PluginCommandContribution.fromJson(Map<String, dynamic> json) =>
      PluginCommandContribution(
        id: json['id'] as String,
        title: json['title'] as String,
        icon: json['icon'] == null
            ? null
            : PluginIconReference.fromJson(json['icon']),
        order: json['order'] as int? ?? 0,
        when: json['when'] as String?,
      );
}

class PluginMenuContribution {
  const PluginMenuContribution({
    required this.location,
    required this.command,
    this.view,
    this.group,
    this.order = 0,
    this.when,
  });

  final String location;
  final String command;
  final String? view;
  final String? group;
  final int order;
  final String? when;

  Map<String, dynamic> toJson() => {
    'location': location,
    'command': command,
    if (view != null) 'view': view,
    if (group != null) 'group': group,
    'order': order,
    if (when != null) 'when': when,
  };

  factory PluginMenuContribution.fromJson(Map<String, dynamic> json) =>
      PluginMenuContribution(
        location: json['location'] as String,
        command: json['command'] as String,
        view: json['view'] as String?,
        group: json['group'] as String?,
        order: json['order'] as int? ?? 0,
        when: json['when'] as String?,
      );
}

class PluginConfigurationContribution {
  const PluginConfigurationContribution({
    required this.id,
    required this.title,
    required this.type,
    this.description = '',
    this.defaultValue,
    this.enumValues = const [],
    this.order = 0,
    this.when,
  });

  final String id;
  final String title;
  final String type;
  final String description;
  final Object? defaultValue;
  final List<Object?> enumValues;
  final int order;
  final String? when;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type,
    if (description.isNotEmpty) 'description': description,
    if (defaultValue != null) 'default': defaultValue,
    if (enumValues.isNotEmpty) 'enum': enumValues,
    'order': order,
    if (when != null) 'when': when,
  };

  factory PluginConfigurationContribution.fromJson(Map<String, dynamic> json) =>
      PluginConfigurationContribution(
        id: json['id'] as String,
        title: json['title'] as String,
        type: json['type'] as String,
        description: json['description'] as String? ?? '',
        defaultValue: json['default'],
        enumValues: (json['enum'] as List<dynamic>? ?? const [])
            .cast<Object?>(),
        order: json['order'] as int? ?? 0,
        when: json['when'] as String?,
      );
}

class PluginContributions {
  const PluginContributions({
    this.navigationContainers = const [],
    this.views = const [],
    this.commands = const [],
    this.menus = const [],
    this.configuration = const [],
  });

  final List<PluginNavigationContainerContribution> navigationContainers;
  final List<PluginViewContribution> views;
  final List<PluginCommandContribution> commands;
  final List<PluginMenuContribution> menus;
  final List<PluginConfigurationContribution> configuration;

  Iterable<String> get ids sync* {
    yield* navigationContainers.map((value) => value.id);
    yield* views.map((value) => value.id);
    yield* commands.map((value) => value.id);
    yield* configuration.map((value) => value.id);
  }

  Map<String, dynamic> toJson() => {
    'navigationContainers': navigationContainers
        .map((value) => value.toJson())
        .toList(),
    'views': views.map((value) => value.toJson()).toList(),
    'commands': commands.map((value) => value.toJson()).toList(),
    'menus': menus.map((value) => value.toJson()).toList(),
    'configuration': configuration.map((value) => value.toJson()).toList(),
  };

  factory PluginContributions.fromJson(Map<String, dynamic> json) =>
      PluginContributions(
        navigationContainers:
            (json['navigationContainers'] as List<dynamic>? ?? const [])
                .map(
                  (value) => PluginNavigationContainerContribution.fromJson(
                    Map<String, dynamic>.from(value as Map),
                  ),
                )
                .toList(),
        views: (json['views'] as List<dynamic>? ?? const [])
            .map(
              (value) => PluginViewContribution.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(),
        commands: (json['commands'] as List<dynamic>? ?? const [])
            .map(
              (value) => PluginCommandContribution.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(),
        menus: (json['menus'] as List<dynamic>? ?? const [])
            .map(
              (value) => PluginMenuContribution.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(),
        configuration: (json['configuration'] as List<dynamic>? ?? const [])
            .map(
              (value) => PluginConfigurationContribution.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(),
      );
}

class PluginManifestV2 {
  const PluginManifestV2({
    this.manifestVersion = 2,
    required this.id,
    required this.name,
    required this.version,
    required this.type,
    this.protocolVersion = 1,
    this.pythonVersion,
    this.author = '',
    this.description = '',
    this.icons,
    this.activationEvents = const [],
    this.permissions = const [],
    this.platforms = const [],
    this.contributes = const PluginContributions(),
  });

  final int manifestVersion;
  final String id;
  final String name;
  final String version;
  final PluginType type;
  final int protocolVersion;
  final String? pythonVersion;
  final String author;
  final String description;
  final PluginIconSet? icons;
  final List<String> activationEvents;
  final List<String> permissions;
  final List<String> platforms;
  final PluginContributions contributes;

  Map<String, List<String>> get permissionsByResource {
    final result = <String, List<String>>{};
    for (final permission in permissions) {
      final separator = permission.indexOf('.');
      if (separator <= 0 || separator == permission.length - 1) continue;
      final resource = permission.substring(0, separator);
      final action = permission.substring(separator + 1);
      result.putIfAbsent(resource, () => <String>[]).add(action);
    }
    return result;
  }

  bool get autoStart => activationEvents.contains('onStartup');

  Map<String, dynamic> toJson() => {
    'manifestVersion': manifestVersion,
    'id': id,
    'name': name,
    'version': version,
    'type': type.name,
    'protocolVersion': protocolVersion,
    if (pythonVersion != null) 'pythonVersion': pythonVersion,
    'author': author,
    'description': description,
    if (icons != null) 'icons': icons!.toJson(),
    'activationEvents': activationEvents,
    'permissions': permissions,
    'platforms': platforms,
    'contributes': contributes.toJson(),
  };

  factory PluginManifestV2.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String;
    final manifest = PluginManifestV2(
      manifestVersion: json['manifestVersion'] as int,
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      type: PluginType.values.firstWhere(
        (value) => value.name == typeName,
        orElse: () => throw PluginManifestException(
          PluginManifestErrorCode.invalidSchema,
          'Unsupported plugin type: $typeName',
        ),
      ),
      protocolVersion: json['protocolVersion'] as int,
      pythonVersion: json['pythonVersion'] as String?,
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      icons: json['icons'] == null
          ? null
          : PluginIconSet.fromJson(
              Map<String, dynamic>.from(json['icons'] as Map),
            ),
      activationEvents: (json['activationEvents'] as List<dynamic>? ?? const [])
          .cast<String>(),
      permissions: (json['permissions'] as List<dynamic>? ?? const [])
          .cast<String>(),
      platforms: (json['platforms'] as List<dynamic>? ?? const [])
          .cast<String>(),
      contributes: PluginContributions.fromJson(
        Map<String, dynamic>.from(json['contributes'] as Map? ?? const {}),
      ),
    );
    PluginManifestValidator().validate(manifest);
    return manifest;
  }
}

class PluginManifestValidator {
  PluginManifestValidator({
    Set<String>? supportedRenderers,
    Set<String>? supportedIcons,
    Set<String>? contextKeys,
  }) : supportedRenderers = Set<String>.unmodifiable(
         supportedRenderers ?? defaultRenderers,
       ),
       supportedIcons = Set<String>.unmodifiable(
         supportedIcons ?? defaultIcons,
       ),
       contextKeys = Set<String>.unmodifiable(
         contextKeys ?? defaultContextKeys,
       );

  static const defaultRenderers = {
    'native.tree',
    'native.virtualList',
    'native.table',
    'native.form',
    'native.markdown',
    'native.log',
    'native.outline',
    'native.variableInspector',
  };

  static final defaultIcons = Set<String>.unmodifiable(
    materialIconCodePoints.keys,
  );

  static const defaultContextKeys = ContextKeyService.defaultKeys;

  static const supportedPermissions = {
    'ui.view',
    'ui.navigate',
    'ui.notify',
    'file.read',
    'file.write',
    'board.read',
    'board.write',
    'editor.read',
    'editor.write',
    'persistence.read',
    'persistence.write',
    'tab.create',
    'tab.manage',
    'settings.read',
    'settings.write',
    'serial.read',
    'serial.write',
    'data.read',
    'data.write',
    'dialog.show',
    'runtime.inspect',
  };

  static const supportedPlatforms = {'windows', 'linux', 'macos', 'android'};
  static const navigationLocations = {'primary', 'secondary'};
  static const menuLocations = {
    'view/title',
    'view/context',
    'navigation/context',
    'commandPalette',
  };
  static const configurationTypes = {
    'string',
    'integer',
    'number',
    'boolean',
    'array',
  };

  static final _pluginIdPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9_-]*(?:\.[A-Za-z0-9][A-Za-z0-9_-]*)*$',
  );
  static final _contributionIdPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9_-]*(?:\.[A-Za-z0-9][A-Za-z0-9_-]*)+$',
  );
  static final _languagePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_+.-]*$');
  static final _windowsReservedPluginId = RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
    caseSensitive: false,
  );

  final Set<String> supportedRenderers;
  final Set<String> supportedIcons;
  final Set<String> contextKeys;

  void validate(PluginManifestV2 manifest) {
    if (manifest.manifestVersion != 2) {
      throw PluginManifestException(
        PluginManifestErrorCode.unsupportedVersion,
        'Unsupported manifest version: ${manifest.manifestVersion}',
      );
    }
    if (!_pluginIdPattern.hasMatch(manifest.id) ||
        _windowsReservedPluginId.hasMatch(manifest.id)) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidPluginId,
        'Invalid plugin ID: ${manifest.id}',
      );
    }
    if (_isBlank(manifest.name) || _isBlank(manifest.version)) {
      throw const PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        'Plugin name and version must not be empty',
      );
    }
    if (manifest.protocolVersion != 1) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        'Unsupported plugin protocol version: ${manifest.protocolVersion}',
      );
    }
    final icons = manifest.icons;
    if (icons != null) {
      _validateAssetPath(icons.full, 'icons.full');
      _validateAssetPath(icons.monochrome, 'icons.monochrome');
    }

    _validateUniqueStrings(
      manifest.permissions,
      PluginManifestErrorCode.invalidPermission,
      'permission',
    );
    for (final permission in manifest.permissions) {
      if (!supportedPermissions.contains(permission)) {
        throw PluginManifestException(
          PluginManifestErrorCode.invalidPermission,
          'Unsupported permission: $permission',
        );
      }
    }
    _validateUniqueStrings(
      manifest.platforms,
      PluginManifestErrorCode.invalidSchema,
      'platform',
    );
    for (final platform in manifest.platforms) {
      if (!supportedPlatforms.contains(platform)) {
        throw PluginManifestException(
          PluginManifestErrorCode.invalidSchema,
          'Unsupported platform: $platform',
        );
      }
    }

    final contributions = manifest.contributes;
    if (manifest.type == PluginType.ui &&
        contributions.navigationContainers.isEmpty) {
      throw const PluginManifestException(
        PluginManifestErrorCode.missingNavigationContainer,
        'UI plugins must declare a navigation container',
      );
    }

    final ids = <String, String>{};
    void registerId(String id, String kind, {bool allowPluginId = false}) {
      final validPrefix =
          id.startsWith('${manifest.id}.') ||
          (allowPluginId && id == manifest.id);
      if (!validPrefix ||
          (id != manifest.id && !_contributionIdPattern.hasMatch(id))) {
        throw PluginManifestException(
          PluginManifestErrorCode.invalidContributionId,
          '$kind ID must use the ${manifest.id} namespace: $id',
        );
      }
      final normalized = id.toLowerCase();
      final previous = ids[normalized];
      if (previous != null) {
        throw PluginManifestException(
          PluginManifestErrorCode.contributionConflict,
          'Contribution ID $id conflicts with $previous',
        );
      }
      ids[normalized] = '$kind $id';
    }

    for (final container in contributions.navigationContainers) {
      registerId(container.id, 'navigation container', allowPluginId: true);
      _requireText(container.title, 'navigation container title');
      if (!navigationLocations.contains(container.location)) {
        throw PluginManifestException(
          PluginManifestErrorCode.invalidSchema,
          'Unsupported navigation location: ${container.location}',
        );
      }
      _validateIcon(container.icon);
      _validateWhen(container.when);
    }
    for (final view in contributions.views) {
      registerId(view.id, 'view');
      _requireText(view.title, 'view title');
      _validateRenderer(view.renderer);
      _validateIcon(view.icon);
      _validateWhen(view.when);
    }
    for (final command in contributions.commands) {
      registerId(command.id, 'command');
      _requireText(command.title, 'command title');
      _validateIcon(command.icon);
      _validateWhen(command.when);
    }
    for (final configuration in contributions.configuration) {
      registerId(configuration.id, 'configuration');
      _requireText(configuration.title, 'configuration title');
      _validateConfiguration(configuration);
      _validateWhen(configuration.when);
    }

    final navigationIds = contributions.navigationContainers
        .map((value) => value.id)
        .toSet();
    final viewIds = contributions.views.map((value) => value.id).toSet();
    final commandIds = contributions.commands.map((value) => value.id).toSet();
    for (final view in contributions.views) {
      if (!navigationIds.contains(view.container)) {
        throw PluginManifestException(
          PluginManifestErrorCode.invalidSchema,
          'View ${view.id} references an unknown container: ${view.container}',
        );
      }
    }
    for (final menu in contributions.menus) {
      if (!menuLocations.contains(menu.location)) {
        throw PluginManifestException(
          PluginManifestErrorCode.invalidSchema,
          'Unsupported menu location: ${menu.location}',
        );
      }
      if (!commandIds.contains(menu.command)) {
        throw PluginManifestException(
          PluginManifestErrorCode.invalidSchema,
          'Menu references an unknown command: ${menu.command}',
        );
      }
      if (menu.view != null && !viewIds.contains(menu.view)) {
        throw PluginManifestException(
          PluginManifestErrorCode.invalidSchema,
          'Menu references an unknown view: ${menu.view}',
        );
      }
      _validateWhen(menu.when);
    }

    _validateActivationEvents(manifest, viewIds, commandIds);
  }

  void validateNoConflicts(
    PluginManifestV2 candidate,
    Iterable<PluginManifestV2> installed,
  ) {
    final candidateIds = {
      for (final id in candidate.contributes.ids) id.toLowerCase(): id,
    };
    for (final manifest in installed) {
      if (manifest.id == candidate.id) continue;
      if (manifest.id.toLowerCase() == candidate.id.toLowerCase()) {
        throw PluginManifestException(
          PluginManifestErrorCode.contributionConflict,
          'Plugin ID ${candidate.id} conflicts with plugin ${manifest.id}',
        );
      }
      for (final id in manifest.contributes.ids) {
        final candidateId = candidateIds[id.toLowerCase()];
        if (candidateId != null) {
          throw PluginManifestException(
            PluginManifestErrorCode.contributionConflict,
            'Contribution ID $candidateId conflicts with plugin ${manifest.id}',
          );
        }
      }
    }
  }

  void _validateRenderer(String renderer) {
    final normalized = renderer.toLowerCase();
    if (normalized == 'rfw' || normalized.startsWith('rfw.')) {
      throw PluginManifestException(
        PluginManifestErrorCode.rfwRendererUnsupported,
        'RFW renderer is not supported: $renderer',
      );
    }
    if (!supportedRenderers.contains(renderer)) {
      throw PluginManifestException(
        PluginManifestErrorCode.unknownRenderer,
        'Unsupported renderer: $renderer',
      );
    }
  }

  void _validateIcon(PluginIconReference? icon) {
    if (icon == null) return;
    switch (icon.kind) {
      case PluginIconKind.material:
        if (!supportedIcons.contains(icon.value)) {
          throw PluginManifestException(
            PluginManifestErrorCode.unknownIcon,
            'Unsupported Material icon: ${icon.value}',
          );
        }
      case PluginIconKind.asset:
        _validateAssetPath(icon.value, 'icon.asset');
    }
  }

  void _validateAssetPath(String value, String field) {
    final normalized = value.replaceAll('\\', '/');
    if (value.isEmpty ||
        value != normalized ||
        !normalized.startsWith('assets/') ||
        normalized.startsWith('/') ||
        normalized.contains(RegExp(r'(^|/)\.\.(/|$)')) ||
        normalized.contains('\u0000') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        '$field must be a relative path below assets/',
      );
    }
  }

  void _validateWhen(String? expression) {
    if (expression == null) return;
    try {
      WhenExpression.parse(expression, allowedKeys: contextKeys);
    } on FormatException catch (error) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidWhen,
        'Invalid when expression: ${error.message}',
      );
    }
  }

  void _validateActivationEvents(
    PluginManifestV2 manifest,
    Set<String> viewIds,
    Set<String> commandIds,
  ) {
    _validateUniqueStrings(
      manifest.activationEvents,
      PluginManifestErrorCode.invalidActivationEvent,
      'activation event',
    );
    for (final event in manifest.activationEvents) {
      if (event == 'onStartup') continue;
      final separator = event.indexOf(':');
      if (separator <= 0 || separator == event.length - 1) {
        throw PluginManifestException(
          PluginManifestErrorCode.invalidActivationEvent,
          'Unsupported activation event: $event',
        );
      }
      final kind = event.substring(0, separator);
      final target = event.substring(separator + 1);
      final valid = switch (kind) {
        'onView' => viewIds.contains(target),
        'onCommand' => commandIds.contains(target),
        'onLanguage' => _languagePattern.hasMatch(target),
        _ => false,
      };
      if (!valid) {
        throw PluginManifestException(
          PluginManifestErrorCode.invalidActivationEvent,
          'Invalid activation event: $event',
        );
      }
    }
  }

  void _validateConfiguration(PluginConfigurationContribution configuration) {
    if (!configurationTypes.contains(configuration.type)) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        'Unsupported configuration type: ${configuration.type}',
      );
    }
    if (!_isJsonValue(configuration.defaultValue)) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        'Configuration ${configuration.id} has a non-JSON default value',
      );
    }
    if (!_matchesConfigurationType(
      configuration.type,
      configuration.defaultValue,
    )) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        'Configuration ${configuration.id} has an invalid default value',
      );
    }
    for (final value in configuration.enumValues) {
      if (!_isJsonValue(value)) {
        throw PluginManifestException(
          PluginManifestErrorCode.invalidSchema,
          'Configuration ${configuration.id} has a non-JSON enum value',
        );
      }
      if (value == null ||
          !_matchesConfigurationType(configuration.type, value)) {
        throw PluginManifestException(
          PluginManifestErrorCode.invalidSchema,
          'Configuration ${configuration.id} has an invalid enum value',
        );
      }
    }
    if (configuration.defaultValue != null &&
        configuration.enumValues.isNotEmpty &&
        !configuration.enumValues.any(
          (value) => _jsonValuesEqual(value, configuration.defaultValue),
        )) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        'Configuration ${configuration.id} default is not in its enum',
      );
    }
  }

  bool _matchesConfigurationType(String type, Object? value) {
    if (value == null) return true;
    return switch (type) {
      'string' => value is String,
      'integer' => value is int,
      'number' => value is num && value.isFinite,
      'boolean' => value is bool,
      'array' => value is List && value.every(_isJsonValue),
      _ => false,
    };
  }

  bool _isJsonValue(Object? value) {
    if (value == null || value is String || value is bool || value is int) {
      return true;
    }
    if (value is double) return value.isFinite;
    if (value is List) return value.every(_isJsonValue);
    if (value is Map) {
      return value.entries.every(
        (entry) => entry.key is String && _isJsonValue(entry.value),
      );
    }
    return false;
  }

  bool _jsonValuesEqual(Object? left, Object? right) {
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_jsonValuesEqual(left[index], right[index])) return false;
      }
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !_jsonValuesEqual(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }
    return left == right;
  }

  void _requireText(String value, String field) {
    if (_isBlank(value)) {
      throw PluginManifestException(
        PluginManifestErrorCode.invalidSchema,
        '$field must not be empty',
      );
    }
  }

  bool _isBlank(String value) => value.replaceAll('\uFEFF', '').trim().isEmpty;

  void _validateUniqueStrings(List<String> values, String code, String label) {
    final seen = <String>{};
    for (final value in values) {
      if (!seen.add(value)) {
        throw PluginManifestException(code, 'Duplicate $label: $value');
      }
    }
  }
}
