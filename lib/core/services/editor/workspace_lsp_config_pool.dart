/// Owns one LSP configuration per workspace root and hands it to every editor
/// controller opened under that root.
///
/// Starting a language server per open file multiplied memory and startup cost
/// by the tab count; a server is per-workspace by design, and `LspConfig`
/// tracks open documents by path, so one instance serves every controller at
/// once. Each controller filters server messages (diagnostics, applyEdit) by
/// its own `openedFile`, and `CodeForgeController.dispose()` does not touch
/// the config, so sharing needs no changes on the editor side.
///
/// [T] is the config type. The class is generic only so tests can drive the
/// ref-counting with plain placeholders: `LspConfig` is sealed and cannot be
/// subclassed or faked outside code_forge.
class WorkspaceLspConfigPool<T> {
  WorkspaceLspConfigPool({
    required Future<T?> Function(String workspacePath) create,
    void Function(T config)? onEvict,
  }) : _create = create,
       _onEvict = onEvict;

  final Future<T?> Function(String workspacePath) _create;
  final void Function(T config)? _onEvict;

  final Map<String, T> _configs = {};
  final Map<String, int> _users = {};

  /// In-flight creations keyed by workspace. A second file opened while the
  /// first server is still starting awaits the same future instead of
  /// spawning a duplicate process.
  final Map<String, Future<T?>> _bootstraps = {};

  /// Returns the pooled config for [workspacePath], creating it on first use.
  ///
  /// `created` marks the call that started the config, so the caller can run
  /// once-per-server work — such as sending the workspace configuration
  /// notification — exactly once.
  Future<({T? config, bool created})> acquire(String workspacePath) async {
    final existing = _configs[workspacePath];
    if (existing != null) {
      _users[workspacePath] = (_users[workspacePath] ?? 0) + 1;
      return (config: existing, created: false);
    }
    final pending = _bootstraps[workspacePath];
    if (pending != null) {
      final config = await pending;
      if (config != null) {
        _users[workspacePath] = (_users[workspacePath] ?? 0) + 1;
      }
      return (config: config, created: false);
    }
    final bootstrap = _create(workspacePath);
    _bootstraps[workspacePath] = bootstrap;
    final config = await bootstrap;
    _bootstraps.remove(workspacePath);
    if (config == null) {
      // A failed start leaves no pooled entry, so the next file opens can
      // retry — potentially with different settings.
      return (config: null, created: false);
    }
    _configs[workspacePath] = config;
    _users[workspacePath] = 1;
    return (config: config, created: true);
  }

  /// Drops one user's claim on [config]; a `null` or unknown config is a
  /// no-op. The config is evicted and passed to `onEvict` when the last user
  /// releases it, which for a real `LspConfig` stops the server process.
  void release(T? config) {
    if (config == null) return;
    for (final entry in _configs.entries) {
      if (!identical(entry.value, config)) continue;
      final remaining = (_users[entry.key] ?? 1) - 1;
      if (remaining > 0) {
        _users[entry.key] = remaining;
      } else {
        _configs.remove(entry.key);
        _users.remove(entry.key);
        _onEvict?.call(config);
      }
      return;
    }
  }
}
