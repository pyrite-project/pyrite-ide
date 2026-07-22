import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:pyrite_ide/core/services/persistence/plugin_persistence.dart';

const _pluginDirectoryName = 'plugin';
const _pluginUpdatesDirectoryName = 'plugin_updates';
const _pendingDirectoryName = 'pending';
const _pendingBackupsDirectoryName = 'pending_backups';
const _activeBackupsDirectoryName = 'active_backups';
const _removalsDirectoryName = 'removals';
const _stagingDirectoryName = 'staging';
const _trashDirectoryName = 'trash';
const _userDirectoryNames = ['data', 'cache'];

final _invalidPluginIdCharacters = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
final _windowsReservedPluginId = RegExp(
  r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
  caseSensitive: false,
);

var _transactionSequence = 0;

Directory _pluginChild(Directory parent, String pluginId) {
  final parentPath = path.normalize(path.absolute(parent.path));
  final childPath = path.normalize(
    path.absolute(path.join(parentPath, pluginId)),
  );
  if (pluginId.isEmpty ||
      pluginId.trim() != pluginId ||
      path.isAbsolute(pluginId) ||
      path.basename(pluginId) != pluginId ||
      pluginId.endsWith('.') ||
      _invalidPluginIdCharacters.hasMatch(pluginId) ||
      _windowsReservedPluginId.hasMatch(pluginId) ||
      !path.equals(path.dirname(childPath), parentPath)) {
    throw const FormatException('Invalid plugin ID');
  }
  return Directory(childPath);
}

Future<void> _deleteDirectory(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } catch (error) {
    debugPrint('PluginManager: Failed to clean ${directory.path}: $error');
  }
}

Future<void> _copyMissingFile(
  File source,
  String destination,
  Directory temporaryRoot,
) async {
  if (await FileSystemEntity.type(destination, followLinks: false) !=
      FileSystemEntityType.notFound) {
    return;
  }
  await Directory(path.dirname(destination)).create(recursive: true);
  await temporaryRoot.create(recursive: true);
  final temporary = File(
    path.join(
      temporaryRoot.path,
      '${DateTime.now().microsecondsSinceEpoch}-${_transactionSequence++}',
    ),
  );
  await source.copy(temporary.path);
  await temporary.rename(destination);
}

Future<void> _copyMissingDirectory(
  Directory source,
  Directory target,
  Directory temporaryRoot,
) async {
  final targetType = await FileSystemEntity.type(
    target.path,
    followLinks: false,
  );
  if (targetType != FileSystemEntityType.notFound &&
      targetType != FileSystemEntityType.directory) {
    return;
  }
  await target.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final destination = path.join(target.path, path.basename(entity.path));
    if (entity is Directory) {
      await _copyMissingDirectory(
        entity,
        Directory(destination),
        temporaryRoot,
      );
    } else if (entity is File) {
      await _copyMissingFile(entity, destination, temporaryRoot);
    } else if (entity is Link &&
        await FileSystemEntity.type(destination, followLinks: false) ==
            FileSystemEntityType.notFound) {
      await Directory(path.dirname(destination)).create(recursive: true);
      await Link(destination).create(await entity.target());
    }
  }
}

Future<void> _restoreUserDirectories(
  Directory backup,
  Directory active,
  Directory temporaryRoot,
) async {
  await for (final entity in backup.list(followLinks: false)) {
    final name = path.basename(entity.path);
    if (!_userDirectoryNames.contains(name.toLowerCase())) continue;
    final destination = path.join(active.path, name);
    if (entity is Directory) {
      await _copyMissingDirectory(
        entity,
        Directory(destination),
        temporaryRoot,
      );
    } else if (entity is File) {
      await _copyMissingFile(entity, destination, temporaryRoot);
    } else if (entity is Link &&
        await FileSystemEntity.type(destination, followLinks: false) ==
            FileSystemEntityType.notFound) {
      await Link(destination).create(await entity.target());
    }
  }
}

Future<void> _trashDirectory(Directory directory, Directory trashRoot) async {
  if (!await directory.exists()) return;
  await trashRoot.create(recursive: true);
  final trash = Directory(
    path.join(
      trashRoot.path,
      '${DateTime.now().microsecondsSinceEpoch}-${_transactionSequence++}',
    ),
  );
  await directory.rename(trash.path);
  await _deleteDirectory(trash);
}

Future<PluginPersistedData> _extractPluginPackage(
  String packagePath,
  Directory destination,
) async {
  if (await destination.exists()) await destination.delete(recursive: true);
  await destination.create(recursive: true);

  final stream = InputFileStream(packagePath);
  try {
    final archive = ZipDecoder().decodeStream(stream);
    await extractArchiveToDisk(archive, destination.path);
    final manifest = PluginTomlParser.parseFromDirectory(destination);
    final entryPoint = File(path.join(destination.path, '__main__.py'));
    if (manifest == null || !await entryPoint.exists()) {
      throw const FormatException('Invalid plugin package');
    }
    _pluginChild(destination, manifest.id);
    return manifest;
  } catch (_) {
    await destination.delete(recursive: true);
    rethrow;
  } finally {
    stream.close();
  }
}

Plugin _mergePluginUpdate(PluginPersistedData manifest, Plugin? current) {
  final updated = manifest.toPlugin();
  if (current == null) return updated;

  final permissions = <String, List<String>>{};
  for (final entry in updated.declaredPermissions.entries) {
    final previous = current.declaredPermissions[entry.key];
    final granted = current.permissions[entry.key] ?? const [];
    permissions[entry.key] = [
      for (final action in entry.value)
        if (granted.contains('*') ||
            granted.contains(action) ||
            previous == null ||
            (!previous.contains('*') && !previous.contains(action)))
          action,
    ];
  }
  return updated.copyWith(
    status: current.status == PluginStatus.installing
        ? PluginStatus.usable
        : current.status,
    permissions: permissions,
  );
}

Future<Set<String>> _recoverPendingBackups(Directory updatesRoot) async {
  final backupsRoot = Directory(
    path.join(updatesRoot.path, _pendingBackupsDirectoryName),
  );
  if (!await backupsRoot.exists()) return {};

  final pendingRoot = await Directory(
    path.join(updatesRoot.path, _pendingDirectoryName),
  ).create(recursive: true);
  final trashRoot = Directory(path.join(updatesRoot.path, _trashDirectoryName));
  final failed = <String>{};
  await for (final backup in backupsRoot.list(followLinks: false)) {
    if (backup is! Directory) continue;
    final pluginId = path.basename(backup.path);
    try {
      final pending = _pluginChild(pendingRoot, pluginId);
      if (await pending.exists()) {
        await _trashDirectory(backup, trashRoot);
      } else {
        await backup.rename(pending.path);
      }
    } catch (error) {
      failed.add(pluginId);
      debugPrint('PluginManager: Failed to recover pending $pluginId: $error');
    }
  }
  return failed;
}

Future<Set<String>> _recoverActiveBackups(
  Directory root,
  Directory updatesRoot,
) async {
  final backupsRoot = Directory(
    path.join(updatesRoot.path, _activeBackupsDirectoryName),
  );
  if (!await backupsRoot.exists()) return {};

  final activeRoot = await Directory(
    path.join(root.path, _pluginDirectoryName),
  ).create(recursive: true);
  final pendingRoot = await Directory(
    path.join(updatesRoot.path, _pendingDirectoryName),
  ).create(recursive: true);
  final trashRoot = Directory(path.join(updatesRoot.path, _trashDirectoryName));
  final failed = <String>{};
  await for (final backup in backupsRoot.list(followLinks: false)) {
    if (backup is! Directory) continue;
    final pluginId = path.basename(backup.path);
    try {
      final active = _pluginChild(activeRoot, pluginId);
      final pending = _pluginChild(pendingRoot, pluginId);
      if (!await active.exists()) {
        if (!await pending.exists()) {
          throw StateError(
            'Plugin transaction has no active or pending package',
          );
        }
        await pending.rename(active.path);
      } else if (await pending.exists()) {
        throw StateError('Plugin transaction has two candidate packages');
      }
      await _restoreUserDirectories(backup, active, trashRoot);
      await _trashDirectory(backup, trashRoot);
    } catch (error) {
      failed.add(pluginId);
      debugPrint('PluginManager: Failed to recover $pluginId: $error');
    }
  }
  return failed;
}

Future<void> _replacePendingPackage(
  Directory updatesRoot,
  String pluginId,
  Directory staged,
) async {
  final pendingRoot = await Directory(
    path.join(updatesRoot.path, _pendingDirectoryName),
  ).create(recursive: true);
  final backupsRoot = await Directory(
    path.join(updatesRoot.path, _pendingBackupsDirectoryName),
  ).create(recursive: true);
  final trashRoot = Directory(path.join(updatesRoot.path, _trashDirectoryName));
  final pending = _pluginChild(pendingRoot, pluginId);
  final backup = _pluginChild(backupsRoot, pluginId);

  if (await pending.exists()) await pending.rename(backup.path);
  try {
    await staged.rename(pending.path);
  } catch (_) {
    if (await backup.exists() && !await pending.exists()) {
      await backup.rename(pending.path);
    }
    rethrow;
  }
  await _trashDirectory(backup, trashRoot);
}

Future<void> _activatePendingPackage(
  Directory root,
  Directory updatesRoot,
  String pluginId,
) async {
  final activeRoot = await Directory(
    path.join(root.path, _pluginDirectoryName),
  ).create(recursive: true);
  final pendingRoot = Directory(
    path.join(updatesRoot.path, _pendingDirectoryName),
  );
  final backupsRoot = await Directory(
    path.join(updatesRoot.path, _activeBackupsDirectoryName),
  ).create(recursive: true);
  final trashRoot = Directory(path.join(updatesRoot.path, _trashDirectoryName));
  final active = _pluginChild(activeRoot, pluginId);
  final pending = _pluginChild(pendingRoot, pluginId);
  final backup = _pluginChild(backupsRoot, pluginId);

  if (await active.exists()) await active.rename(backup.path);
  try {
    await pending.rename(active.path);
    if (await backup.exists()) {
      await _restoreUserDirectories(backup, active, trashRoot);
      await _trashDirectory(backup, trashRoot);
    }
  } catch (_) {
    if (await active.exists() && !await pending.exists()) {
      await active.rename(pending.path);
    }
    if (await backup.exists() && !await active.exists()) {
      await backup.rename(active.path);
    }
    rethrow;
  }
}

class PluginManagerNotifier extends StateNotifier<Map<String, Plugin>> {
  final Ref ref;
  final PluginPersistence _persistence;
  final Future<Directory> Function() _supportDirectory;
  void Function()? _onChanged;
  Future<void> _operation = Future<void>.value();
  final Map<String, PluginStatus> _intendedStatuses = {};
  bool _metadataAvailable = true;

  PluginManagerNotifier(
    this.ref, {
    PluginPersistence? persistence,
    Future<Directory> Function()? supportDirectory,
  }) : _persistence = persistence ?? PluginPersistence(),
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       super({});

  Future<T> _runExclusive<T>(Future<T> Function() operation) async {
    final previous = _operation;
    final completed = Completer<void>();
    _operation = completed.future;
    await previous;
    try {
      return await operation();
    } finally {
      completed.complete();
    }
  }

  void setOnChanged(void Function()? callback) {
    _onChanged = callback;
  }

  void markMetadataUnavailable() {
    _metadataAvailable = false;
  }

  void _requireMetadata() {
    if (!_metadataAvailable) {
      throw StateError('Plugin metadata is unavailable');
    }
  }

  Future<void> _save(Iterable<Plugin> plugins) => _persistence.save([
    for (final plugin in plugins)
      plugin.copyWith(status: _intendedStatuses[plugin.id] ?? plugin.status),
  ]);

  void loadPersisted(List<PluginPersistedData> plugins) {
    _intendedStatuses.clear();
    state = {for (final plugin in plugins) plugin.id: plugin.toPlugin()};
  }

  Future<void> applyPendingChanges() => _runExclusive(_applyPendingChanges);

  Future<void> _applyPendingChanges() async {
    if (!_metadataAvailable) return;
    if (_intendedStatuses.isNotEmpty) {
      state = {
        for (final entry in state.entries)
          entry.key: entry.value.copyWith(
            status: _intendedStatuses[entry.key] ?? entry.value.status,
          ),
      };
      _intendedStatuses.clear();
    }
    final root = await _supportDirectory();
    final updatesRoot = Directory(
      path.join(root.path, _pluginUpdatesDirectoryName),
    );
    if (!await updatesRoot.exists()) {
      _removeOrphanContributions();
      return;
    }

    final trashRoot = Directory(
      path.join(updatesRoot.path, _trashDirectoryName),
    );
    await _deleteDirectory(trashRoot);
    final pendingBlocked = await _recoverPendingBackups(updatesRoot);
    final activeBlocked = await _recoverActiveBackups(root, updatesRoot);
    final blocked = {...pendingBlocked, ...activeBlocked};
    for (final pluginId in activeBlocked) {
      final plugin = state[pluginId];
      if (plugin != null) {
        _intendedStatuses[pluginId] = plugin.status;
        state = {
          ...state,
          pluginId: plugin.copyWith(status: PluginStatus.installing),
        };
      }
    }
    await _deleteDirectory(
      Directory(path.join(updatesRoot.path, _stagingDirectoryName)),
    );

    final removalsRoot = Directory(
      path.join(updatesRoot.path, _removalsDirectoryName),
    );
    if (await removalsRoot.exists()) {
      final markers = await removalsRoot.list(followLinks: false).toList();
      for (final marker in markers.whereType<File>()) {
        final pluginId = path.basename(marker.path);
        _intendedStatuses.remove(pluginId);
        final next = {...state}..remove(pluginId);
        final metadataChanged = next.length != state.length;
        state = next;
        _removeContributions(pluginId);
        try {
          final reinstall = await marker.readAsString() == 'reinstall';
          if (reinstall && blocked.contains(pluginId)) continue;
          if (!reinstall) {
            final pending = _pluginChild(
              Directory(path.join(updatesRoot.path, _pendingDirectoryName)),
              pluginId,
            );
            final pendingBackup = _pluginChild(
              Directory(
                path.join(updatesRoot.path, _pendingBackupsDirectoryName),
              ),
              pluginId,
            );
            await _trashDirectory(pending, trashRoot);
            await _trashDirectory(pendingBackup, trashRoot);
          }
          if (metadataChanged) {
            await _save(next.values);
          }

          final active = _pluginChild(
            Directory(path.join(root.path, _pluginDirectoryName)),
            pluginId,
          );
          final backup = _pluginChild(
            Directory(path.join(updatesRoot.path, _activeBackupsDirectoryName)),
            pluginId,
          );
          if (await active.exists()) await active.delete(recursive: true);
          await _trashDirectory(backup, trashRoot);
          await marker.delete();
          blocked.remove(pluginId);
        } catch (error) {
          blocked.add(pluginId);
          debugPrint('PluginManager: Failed to remove $pluginId: $error');
        }
      }
    }

    final pendingRoot = Directory(
      path.join(updatesRoot.path, _pendingDirectoryName),
    );
    if (await pendingRoot.exists()) {
      final packages = await pendingRoot.list(followLinks: false).toList();
      for (final pending in packages.whereType<Directory>()) {
        final pluginId = path.basename(pending.path);
        if (blocked.contains(pluginId)) continue;
        final manifest = PluginTomlParser.parseFromDirectory(pending);
        final entryPoint = File(path.join(pending.path, '__main__.py'));
        if (manifest == null ||
            manifest.id != pluginId ||
            !await entryPoint.exists()) {
          debugPrint('PluginManager: Invalid pending package $pluginId');
          continue;
        }

        final updated = _mergePluginUpdate(manifest, state[pluginId]);
        final next = {...state, pluginId: updated};
        var metadataSaved = false;
        try {
          await _save(next.values);
          metadataSaved = true;
          await _activatePendingPackage(root, updatesRoot, pluginId);
          _intendedStatuses.remove(pluginId);
          state = next;
        } catch (error) {
          if (metadataSaved) {
            _intendedStatuses[pluginId] = updated.status;
            state = {
              ...state,
              pluginId: updated.copyWith(status: PluginStatus.installing),
            };
          }
          debugPrint('PluginManager: Failed to apply $pluginId: $error');
        }
      }
    }
    _removeOrphanContributions();
  }

  Future<void> autoStart() async {
    for (final plugin in state.values) {
      if (plugin.status != PluginStatus.usable) continue;
      if (plugin.type == PluginType.data) {
        await ref.read(pluginRunManagerProvider.notifier).runOnce(plugin);
      } else if (plugin.autoStart) {
        await ref.read(pluginRunManagerProvider.notifier).start(plugin);
      }
    }
  }

  Future<void> changeStatus(String id, PluginStatus status) async {
    final plugin = state[id];
    if (plugin == null) return;
    if (status == PluginStatus.disabled) {
      unawaited(ref.read(pluginRunManagerProvider.notifier).stop(plugin));
      _disableContributions(id);
    }
    final updated = plugin.copyWith(status: status);
    _intendedStatuses.remove(id);
    state = {...state, id: updated};
    if (status == PluginStatus.usable && updated.type == PluginType.data) {
      await ref.read(pluginRunManagerProvider.notifier).runOnce(updated);
    }
    _onChanged?.call();
  }

  void _disableContributions(String pluginId) {
    ref.read(dataContributionsProvider.notifier).state = [
      for (final record in ref.read(dataContributionsProvider))
        if (record.pluginId == pluginId)
          DataContributionRecord(
            pluginId: record.pluginId,
            pluginType: record.pluginType,
            kind: record.kind,
            contributionId: record.contributionId,
            payload: record.payload,
            enabled: false,
          )
        else
          record,
    ];
    ref.read(dataRegistryProvider).removePlugin(pluginId);
  }

  void _removeContributions(String pluginId) {
    ref.read(dataContributionsProvider.notifier).state = [
      for (final record in ref.read(dataContributionsProvider))
        if (record.pluginId != pluginId) record,
    ];
    ref.read(dataRegistryProvider).removePlugin(pluginId);
  }

  void _removeOrphanContributions() {
    final orphanIds = ref
        .read(dataContributionsProvider)
        .map((record) => record.pluginId)
        .where((pluginId) => !state.containsKey(pluginId))
        .toSet();
    for (final pluginId in orphanIds) {
      _removeContributions(pluginId);
    }
  }

  void updatePermissions(String id, Map<String, List<String>> permissions) {
    if (state[id] != null) {
      state = {...state, id: state[id]!.copyWith(permissions: permissions)};
      _onChanged?.call();
    }
  }

  /// Returns whether the package was staged for the next IDE start.
  Future<bool> install(String packagePath) =>
      _runExclusive(() => _install(packagePath));

  Future<bool> _install(String packagePath) async {
    _requireMetadata();
    final root = await _supportDirectory();
    final updatesRoot = await Directory(
      path.join(root.path, _pluginUpdatesDirectoryName),
    ).create(recursive: true);
    final blocked = await _recoverPendingBackups(updatesRoot);
    final stagingRoot = await Directory(
      path.join(updatesRoot.path, _stagingDirectoryName),
    ).create(recursive: true);
    final staged = Directory(
      path.join(
        stagingRoot.path,
        '${DateTime.now().microsecondsSinceEpoch}-${_transactionSequence++}',
      ),
    );
    final manifest = await _extractPluginPackage(packagePath, staged);
    try {
      final active = _pluginChild(
        Directory(path.join(root.path, _pluginDirectoryName)),
        manifest.id,
      );
      final pendingRoot = await Directory(
        path.join(updatesRoot.path, _pendingDirectoryName),
      ).create(recursive: true);
      final activeBackupsRoot = Directory(
        path.join(updatesRoot.path, _activeBackupsDirectoryName),
      );
      if (blocked.contains(manifest.id) ||
          await _pluginChild(activeBackupsRoot, manifest.id).exists()) {
        throw StateError('Plugin update recovery is incomplete');
      }
      if (state.keys.any(
        (id) =>
            id != manifest.id && id.toLowerCase() == manifest.id.toLowerCase(),
      )) {
        throw const FormatException(
          'Plugin ID conflicts with an installed plugin',
        );
      }
      for (final directory in [
        Directory(path.join(root.path, _pluginDirectoryName)),
        pendingRoot,
        activeBackupsRoot,
      ]) {
        if (!await directory.exists()) continue;
        await for (final entity in directory.list(followLinks: false)) {
          final name = path.basename(entity.path);
          if (name != manifest.id &&
              name.toLowerCase() == manifest.id.toLowerCase()) {
            throw const FormatException(
              'Plugin ID conflicts with an installed plugin',
            );
          }
        }
      }
      final pending = _pluginChild(pendingRoot, manifest.id);
      final existingPlugin = state[manifest.id];
      final removal = File(
        _pluginChild(
          Directory(path.join(updatesRoot.path, _removalsDirectoryName)),
          manifest.id,
        ).path,
      );
      final removalPending = await removal.exists();
      final updatePending =
          existingPlugin != null ||
          await active.exists() ||
          await pending.exists() ||
          removalPending;

      await _replacePendingPackage(updatesRoot, manifest.id, staged);
      if (removalPending) {
        await removal.writeAsString('reinstall', flush: true);
      }
      if (updatePending) {
        if (existingPlugin == null) {
          final next = {
            ...state,
            manifest.id: manifest.toPlugin().copyWith(
              status: PluginStatus.installing,
            ),
          };
          await _save(next.values);
          state = next;
        }
        return true;
      }

      final previous = state;
      final installed = manifest.toPlugin();
      state = {
        ...previous,
        manifest.id: installed.copyWith(status: PluginStatus.installing),
      };
      var metadataSaved = false;

      try {
        final next = {...state, manifest.id: installed};
        await _save(next.values);
        metadataSaved = true;
        await _activatePendingPackage(root, updatesRoot, manifest.id);
        state = {...state, manifest.id: installed};

        if (installed.type == PluginType.data) {
          await ref.read(pluginRunManagerProvider.notifier).runOnce(installed);
        } else if (installed.autoStart) {
          await ref.read(pluginRunManagerProvider.notifier).start(installed);
        }
        return false;
      } catch (_) {
        if (!metadataSaved) {
          state = {...state}..remove(manifest.id);
          await _trashDirectory(
            pending,
            Directory(path.join(updatesRoot.path, _trashDirectoryName)),
          );
        } else {
          _intendedStatuses[manifest.id] = installed.status;
        }
        rethrow;
      }
    } finally {
      await _deleteDirectory(staged);
    }
  }

  Future<void> uninstall(String pluginId) =>
      _runExclusive(() => _uninstall(pluginId));

  Future<void> _uninstall(String pluginId) async {
    _requireMetadata();
    final plugin = state[pluginId];
    if (plugin == null) return;

    final root = await _supportDirectory();
    final updatesRoot = await Directory(
      path.join(root.path, _pluginUpdatesDirectoryName),
    ).create(recursive: true);
    final blocked = await _recoverPendingBackups(updatesRoot);
    if (blocked.contains(pluginId)) {
      throw StateError('Plugin update recovery is incomplete');
    }
    final removalsRoot = await Directory(
      path.join(updatesRoot.path, _removalsDirectoryName),
    ).create(recursive: true);
    await File(
      _pluginChild(removalsRoot, pluginId).path,
    ).writeAsString('remove', flush: true);

    final next = {
      ...state,
      pluginId: plugin.copyWith(status: PluginStatus.uninstalled),
    };
    _intendedStatuses.remove(pluginId);
    state = next;
    _removeContributions(pluginId);
    unawaited(ref.read(pluginRunManagerProvider.notifier).stop(plugin));

    final pending = _pluginChild(
      Directory(path.join(updatesRoot.path, _pendingDirectoryName)),
      pluginId,
    );
    final trashRoot = Directory(
      path.join(updatesRoot.path, _trashDirectoryName),
    );
    try {
      await _trashDirectory(pending, trashRoot);
      await _save(next.values);
    } catch (error) {
      debugPrint('PluginManager: Uninstall queued for $pluginId: $error');
    }
  }

  Future<void> persist() => _runExclusive(_persist);

  Future<void> _persist() async {
    if (!_metadataAvailable) return;
    try {
      await _save(state.values);
    } catch (error) {
      debugPrint('PluginManager: Failed to persist plugins: $error');
    }
  }

  void restart(Plugin plugin) {
    unawaited(ref.read(pluginRunManagerProvider.notifier).stop(plugin));
  }
}

final StateNotifierProvider<PluginManagerNotifier, Map<String, Plugin>>
pluginManagerProvider = StateNotifierProvider(
  (ref) => PluginManagerNotifier(ref),
);
