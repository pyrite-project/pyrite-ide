enum LifecycleHooks {
  onInstall("LifecycleHooks.OnInstall"),
  onStart("LifecycleHooks.OnStart"),
  onPause("LifecycleHooks.OnPause"),
  onResume("LifecycleHooks.OnResume"),
  onDispose("LifecycleHooks.OnDispose"),
  onUninstall("LifecycleHooks.OnUninstall");

  const LifecycleHooks(this.value);
  final String value;

  @override
  String toString() => value;
}

enum PluginStatus { usable, installing, disabled, uninstalled }

enum PluginPermission { ui }

class Plugin {
  const Plugin({
    required this.id,
    required this.name,
    this.status = PluginStatus.installing,
    this.permissions = const [],
    this.keepAlive = true,
  });

  final String id;
  final String name;
  final PluginStatus status;
  final List<PluginPermission> permissions;
  final bool keepAlive;

  Plugin copyWith({
    String? id,
    String? name,
    PluginStatus? status,
    List<PluginPermission>? permissions,
    bool? keepAlive,
  }) {
    return Plugin(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      permissions: permissions ?? this.permissions,
      keepAlive: keepAlive ?? this.keepAlive,
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
