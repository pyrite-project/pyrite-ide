enum LifecycleHook {
  install("install"),
  start("start"),
  pause("pause"),
  resume("resume"),
  dispose("dispose"),
  uninstall("uninstall");

  const LifecycleHook(this.value);
  final String value;

  @override
  String toString() => value;
}

enum PluginType { ui, service, data }

enum PluginStatus { usable, installing, disabled, uninstalled }

class Plugin {
  const Plugin({
    required this.id,
    required this.name,
    this.version = '0.0.0',
    this.author = '',
    this.description = '',
    this.type = PluginType.ui,
    this.status = PluginStatus.installing,
    this.declaredPermissions = const {},
    this.permissions = const {},
    this.platforms = const [],
    this.keepAlive = true,
    this.autoStart = false,
  });

  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final PluginType type;
  final PluginStatus status;
  final Map<String, List<String>> declaredPermissions;
  final Map<String, List<String>> permissions;
  final List<String> platforms;
  final bool keepAlive;
  final bool autoStart;

  Plugin copyWith({
    String? id,
    String? name,
    String? version,
    String? author,
    String? description,
    PluginType? type,
    PluginStatus? status,
    Map<String, List<String>>? declaredPermissions,
    Map<String, List<String>>? permissions,
    List<String>? platforms,
    bool? keepAlive,
    bool? autoStart,
  }) {
    return Plugin(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      author: author ?? this.author,
      description: description ?? this.description,
      type: type ?? this.type,
      status: status ?? this.status,
      declaredPermissions: declaredPermissions ?? this.declaredPermissions,
      permissions: permissions ?? this.permissions,
      platforms: platforms ?? this.platforms,
      keepAlive: keepAlive ?? this.keepAlive,
      autoStart: autoStart ?? this.autoStart,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Plugin &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          status == other.status;

  @override
  int get hashCode => Object.hash(id, name, status);
}
