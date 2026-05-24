class LifecycleHooks {
  static String get onInstall => "LifecycleHooks.OnInstall";
  static String get onStart => "LifecycleHooks.OnStart";
  static String get onPause => "LifecycleHooks.OnPause";
  static String get onResume => "LifecycleHooks.OnResume";
  static String get onDispose => "LifecycleHooks.OnDispose";
  static String get onUninstall => "LifecycleHooks.OnUninstall";
}

enum PluginStatus { usable, installing, disusable, uninstall }

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
  final List permissions;
  final bool keepAlive;

  Plugin copyWith({
    String? id,
    String? name,
    PluginStatus? status,
    List? permissions,
  }) {
    return Plugin(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      permissions: permissions ?? this.permissions,
    );
  }
}
