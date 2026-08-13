import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_package_paths.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/activation_manager.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:pyrite_ide/core/services/persistence/plugin_persistence.dart';

const _pluginDirectoryName = pluginDirectoryName;
const _pluginUpdatesDirectoryName = pluginUpdatesDirectoryName;
const _newDirectoryName = pluginNewDirectoryName;
const _newBackupsDirectoryName = 'new_backups';
const _pendingDeletionsDirectoryName = pluginPendingDeletionsDirectoryName;
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
    if (!await entryPoint.exists()) {
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

Plugin _readActivePluginMetadata(
  Directory root,
  String pluginId,
  Plugin? current,
  PluginStatus? intendedStatus,
) {
  final active = _pluginChild(
    Directory(path.join(root.path, _pluginDirectoryName)),
    pluginId,
  );
  final parsed = PluginTomlParser.parseFromDirectory(active);
  if (parsed.id != pluginId ||
      !File(path.join(active.path, '__main__.py')).existsSync()) {
    throw const PluginManifestException(
      PluginManifestErrorCode.invalidSchema,
      'Active package identity or entry point is invalid',
    );
  }
  final plugin = parsed.toPlugin();
  return plugin.copyWith(
    status: _persistablePluginStatus(
      intendedStatus ?? current?.status ?? plugin.status,
    ),
    permissions: restrictPluginPermissions(
      current?.permissions ?? plugin.permissions,
      plugin.declaredPermissions,
    ),
  );
}

PluginStatus _persistablePluginStatus(PluginStatus status) {
  return status == PluginStatus.installing ? PluginStatus.usable : status;
}

Future<Set<String>> _recoverNewBackups(
  Directory root,
  Directory updatesRoot,
  Map<String, Plugin> plugins,
) async {
  final backupsRoot = Directory(
    path.join(updatesRoot.path, _newBackupsDirectoryName),
  );
  if (!await backupsRoot.exists()) return {};

  final newRoot = await Directory(
    path.join(updatesRoot.path, _newDirectoryName),
  ).create(recursive: true);
  final trashRoot = Directory(path.join(updatesRoot.path, _trashDirectoryName));
  final failed = <String>{};
  await for (final backup in backupsRoot.list(followLinks: false)) {
    if (backup is! Directory) continue;
    final pluginId = path.basename(backup.path);
    try {
      final replacement = _pluginChild(newRoot, pluginId);
      final marker = pendingPluginDeletionMarker(root, pluginId);
      final expectedVersion = await marker.exists()
          ? await _pendingDeletionTargetVersion(marker)
          : plugins[pluginId]?.version;
      final replacementVersion = await replacement.exists()
          ? PluginTomlParser.parseFromDirectory(replacement).version
          : null;
      if (replacementVersion == expectedVersion) {
        await _trashDirectory(backup, trashRoot);
      } else {
        final backupVersion = PluginTomlParser.parseFromDirectory(
          backup,
        ).version;
        if (backupVersion != expectedVersion) {
          throw StateError('No replacement package matches committed metadata');
        }
        await _trashDirectory(replacement, trashRoot);
        await backup.rename(replacement.path);
      }
    } catch (error) {
      failed.add(pluginId);
      debugPrint(
        'PluginManager: Failed to recover replacement $pluginId: $error',
      );
    }
  }
  return failed;
}

Future<Set<String>> _recoverUnmarkedNewPackages(
  Directory root,
  Directory updatesRoot,
  Map<String, Plugin> plugins,
) async {
  final newRoot = Directory(path.join(updatesRoot.path, _newDirectoryName));
  if (!await newRoot.exists()) return {};
  final trashRoot = Directory(path.join(updatesRoot.path, _trashDirectoryName));
  final failed = <String>{};
  await for (final entity in newRoot.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final pluginId = path.basename(entity.path);
    try {
      final marker = pendingPluginDeletionMarker(root, pluginId);
      if (await marker.exists()) continue;
      final manifest = PluginTomlParser.parseFromDirectory(entity);
      if (manifest.id == pluginId &&
          plugins[pluginId]?.version == manifest.version) {
        await _writePendingDeletionMarker(root, pluginId, manifest.version);
      } else {
        await _trashDirectory(entity, trashRoot);
      }
    } catch (error) {
      failed.add(pluginId);
      debugPrint(
        'PluginManager: Failed to recover unmarked replacement '
        '$pluginId: $error',
      );
    }
  }
  return failed;
}

class _ActiveRecoveryResult {
  const _ActiveRecoveryResult(this.blocked, this.manifestErrors);

  final Set<String> blocked;
  final Map<String, String> manifestErrors;
}

Future<_ActiveRecoveryResult> _recoverActiveBackups(
  Directory root,
  Directory updatesRoot,
  Iterable<PluginManifestV2> installedManifests,
) async {
  final backupsRoot = Directory(
    path.join(updatesRoot.path, _activeBackupsDirectoryName),
  );
  if (!await backupsRoot.exists()) {
    return const _ActiveRecoveryResult(<String>{}, <String, String>{});
  }

  final activeRoot = await Directory(
    path.join(root.path, _pluginDirectoryName),
  ).create(recursive: true);
  final newRoot = await Directory(
    path.join(updatesRoot.path, _newDirectoryName),
  ).create(recursive: true);
  final trashRoot = Directory(path.join(updatesRoot.path, _trashDirectoryName));
  final failed = <String>{};
  final manifestErrors = <String, String>{};
  final recoveredManifests = <PluginManifestV2>[];
  await for (final backup in backupsRoot.list(followLinks: false)) {
    if (backup is! Directory) continue;
    final pluginId = path.basename(backup.path);
    try {
      final active = _pluginChild(activeRoot, pluginId);
      final replacement = _pluginChild(newRoot, pluginId);
      late final Directory candidate;
      if (!await active.exists()) {
        if (!await replacement.exists()) {
          throw StateError(
            'Plugin transaction has no active or replacement package',
          );
        }
        candidate = replacement;
      } else if (await replacement.exists()) {
        throw StateError('Plugin transaction has two candidate packages');
      } else {
        candidate = active;
      }
      final parsed = PluginTomlParser.parseFromDirectory(candidate);
      if (parsed.id != pluginId ||
          !await File(path.join(candidate.path, '__main__.py')).exists()) {
        throw const PluginManifestException(
          PluginManifestErrorCode.invalidSchema,
          'Recovered package identity or entry point is invalid',
        );
      }
      final manifest = parsed.manifest!;
      final otherManifests = [
        ...installedManifests.where((value) => value.id != pluginId),
        ...recoveredManifests.where((value) => value.id != pluginId),
      ];
      if (otherManifests.any(
        (value) =>
            value.id != manifest.id &&
            value.id.toLowerCase() == manifest.id.toLowerCase(),
      )) {
        throw const PluginManifestException(
          PluginManifestErrorCode.contributionConflict,
          'Recovered plugin ID conflicts with an installed plugin',
        );
      }
      PluginManifestValidator().validateNoConflicts(manifest, otherManifests);
      if (!await active.exists()) await replacement.rename(active.path);
      await _restoreUserDirectories(backup, active, trashRoot);
      await _trashDirectory(backup, trashRoot);
      recoveredManifests.add(manifest);
    } on PluginManifestException catch (error) {
      failed.add(pluginId);
      manifestErrors[pluginId] = error.code;
      debugPrint(
        'PluginManager: Failed to recover $pluginId '
        '[${error.code}]: ${error.message}',
      );
    } catch (error) {
      failed.add(pluginId);
      debugPrint('PluginManager: Failed to recover $pluginId: $error');
    }
  }
  return _ActiveRecoveryResult(failed, manifestErrors);
}

Future<void> _replaceNewPackage(
  Directory updatesRoot,
  String pluginId,
  Directory staged,
) async {
  final newRoot = await Directory(
    path.join(updatesRoot.path, _newDirectoryName),
  ).create(recursive: true);
  final backupsRoot = await Directory(
    path.join(updatesRoot.path, _newBackupsDirectoryName),
  ).create(recursive: true);
  final trashRoot = Directory(path.join(updatesRoot.path, _trashDirectoryName));
  final replacement = _pluginChild(newRoot, pluginId);
  final backup = _pluginChild(backupsRoot, pluginId);

  if (await backup.exists()) await _trashDirectory(backup, trashRoot);
  if (await replacement.exists()) await replacement.rename(backup.path);
  try {
    await staged.rename(replacement.path);
  } catch (_) {
    if (await backup.exists() && !await replacement.exists()) {
      await backup.rename(replacement.path);
    }
    rethrow;
  }
}

Future<void> _writePendingDeletionMarker(
  Directory root,
  String pluginId,
  String version,
) async {
  final marker = pendingPluginDeletionMarker(root, pluginId);
  await marker.parent.create(recursive: true);
  final temporary = File('${marker.path}.tmp');
  final backup = File('${marker.path}.bak');
  if (await temporary.exists()) await temporary.delete();
  if (await backup.exists()) await backup.delete();
  await temporary.writeAsString(
    jsonEncode({
      'schemaVersion': 1,
      'pluginId': pluginId,
      'targetVersion': version,
    }),
    flush: true,
  );
  if (await marker.exists()) await marker.rename(backup.path);
  try {
    await temporary.rename(marker.path);
  } catch (_) {
    if (await backup.exists() && !await marker.exists()) {
      await backup.rename(marker.path);
    }
    rethrow;
  }
  if (await backup.exists()) await backup.delete();
}

String? _pluginIdFromPendingDeletionMarker(File marker) {
  final name = path.basename(marker.path);
  if (!name.endsWith('.json')) return null;
  final pluginId = name.substring(0, name.length - '.json'.length);
  return isSafePluginId(pluginId) ? pluginId : null;
}

Future<String?> _pendingDeletionTargetVersion(File marker) async {
  try {
    final decoded = jsonDecode(await marker.readAsString());
    if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
      return null;
    }
    return decoded['targetVersion'] as String?;
  } catch (_) {
    return null;
  }
}

Future<void> _activateNewPackage(
  Directory root,
  Directory updatesRoot,
  String pluginId,
) async {
  final activeRoot = await Directory(
    path.join(root.path, _pluginDirectoryName),
  ).create(recursive: true);
  final newRoot = Directory(path.join(updatesRoot.path, _newDirectoryName));
  final backupsRoot = await Directory(
    path.join(updatesRoot.path, _activeBackupsDirectoryName),
  ).create(recursive: true);
  final trashRoot = Directory(path.join(updatesRoot.path, _trashDirectoryName));
  final active = _pluginChild(activeRoot, pluginId);
  final replacement = _pluginChild(newRoot, pluginId);
  final backup = _pluginChild(backupsRoot, pluginId);

  if (await active.exists()) await active.rename(backup.path);
  try {
    await replacement.rename(active.path);
    if (await backup.exists()) {
      await _restoreUserDirectories(backup, active, trashRoot);
      await _trashDirectory(backup, trashRoot);
    }
  } catch (_) {
    if (await active.exists() && !await replacement.exists()) {
      await active.rename(replacement.path);
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

  void _syncHostContributions([Map<String, Plugin>? plugins]) {
    ref
        .read(contributionRegistryProvider)
        .replaceAll(
          (plugins ?? state).values
              .where((plugin) => plugin.status == PluginStatus.usable)
              .map((plugin) => plugin.manifest)
              .whereType<PluginManifestV2>(),
          deferNotification: true,
        );
  }

  void loadPersisted(List<PluginPersistedData> plugins) {
    _intendedStatuses.clear();
    final candidates = plugins.map((plugin) => plugin.toPlugin()).toList();
    final errors = <int, String>{};
    final pluginIdOwners = <String, List<int>>{};
    final contributionIdOwners = <String, List<int>>{};
    final validator = PluginManifestValidator();

    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      final manifest = candidate.manifest;
      if (manifest == null) {
        errors[index] =
            candidate.manifestErrorCode ??
            PluginManifestErrorCode.missingVersion;
        continue;
      }
      try {
        validator.validate(manifest);
      } on PluginManifestException catch (error) {
        errors[index] = error.code;
        continue;
      }
      pluginIdOwners
          .putIfAbsent(candidate.id.toLowerCase(), () => <int>[])
          .add(index);
      for (final id in manifest.contributes.ids) {
        contributionIdOwners
            .putIfAbsent(id.toLowerCase(), () => <int>[])
            .add(index);
      }
    }

    for (final owners in [
      ...pluginIdOwners.values,
      ...contributionIdOwners.values,
    ]) {
      if (owners.length < 2) continue;
      for (final owner in owners) {
        errors[owner] = PluginManifestErrorCode.contributionConflict;
      }
    }

    final indexes = List<int>.generate(candidates.length, (index) => index)
      ..sort((left, right) {
        final leftId = candidates[left].id;
        final rightId = candidates[right].id;
        final insensitive = leftId.toLowerCase().compareTo(
          rightId.toLowerCase(),
        );
        if (insensitive != 0) return insensitive;
        final sensitive = leftId.compareTo(rightId);
        return sensitive != 0 ? sensitive : left.compareTo(right);
      });
    final restored = <String, Plugin>{};
    for (final index in indexes) {
      final candidate = candidates[index];
      final error = errors[index];
      restored.putIfAbsent(
        candidate.id,
        () => candidate.copyWith(
          status: error == null
              ? _persistablePluginStatus(candidate.status)
              : PluginStatus.disabled,
          manifestErrorCode: error,
        ),
      );
    }
    state = restored;
    _syncHostContributions();
    for (final plugin in state.values) {
      if (plugin.status != PluginStatus.usable) {
        _disableContributions(plugin.id);
      }
    }
    _removeOrphanContributions();
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
      _syncHostContributions();
      _removeOrphanContributions();
      return;
    }

    final trashRoot = Directory(
      path.join(updatesRoot.path, _trashDirectoryName),
    );
    await _deleteDirectory(trashRoot);
    final newBlocked = await _recoverNewBackups(root, updatesRoot, state);
    newBlocked.addAll(
      await _recoverUnmarkedNewPackages(root, updatesRoot, state),
    );
    final activeRecovery = await _recoverActiveBackups(
      root,
      updatesRoot,
      state.values
          .map((plugin) => plugin.manifest)
          .whereType<PluginManifestV2>(),
    );
    final blocked = {...newBlocked, ...activeRecovery.blocked};
    if (activeRecovery.blocked.isNotEmpty) {
      state = {
        for (final entry in state.entries)
          entry.key: activeRecovery.blocked.contains(entry.key)
              ? entry.value.copyWith(
                  status: PluginStatus.disabled,
                  manifestErrorCode:
                      activeRecovery.manifestErrors[entry.key] ??
                      entry.value.manifestErrorCode,
                )
              : entry.value,
      };
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
            final replacement = _pluginChild(
              Directory(path.join(updatesRoot.path, _newDirectoryName)),
              pluginId,
            );
            final replacementBackup = _pluginChild(
              Directory(path.join(updatesRoot.path, _newBackupsDirectoryName)),
              pluginId,
            );
            await _trashDirectory(replacement, trashRoot);
            await _trashDirectory(replacementBackup, trashRoot);
            final updateMarker = pendingPluginDeletionMarker(root, pluginId);
            if (await updateMarker.exists()) await updateMarker.delete();
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

    final pendingDeletionsRoot = Directory(
      path.join(updatesRoot.path, _pendingDeletionsDirectoryName),
    );
    if (await pendingDeletionsRoot.exists()) {
      final markers = await pendingDeletionsRoot
          .list(followLinks: false)
          .toList();
      for (final marker in markers.whereType<File>()) {
        final pluginId = _pluginIdFromPendingDeletionMarker(marker);
        if (pluginId == null) continue;
        if (blocked.contains(pluginId)) continue;
        final replacement = newPluginDirectory(root, pluginId);
        if (!await replacement.exists()) {
          try {
            final activeManifest = PluginTomlParser.parseFromDirectory(
              installedPluginDirectory(root, pluginId),
            );
            final targetVersion = await _pendingDeletionTargetVersion(marker);
            if (activeManifest.id != pluginId ||
                targetVersion == null ||
                activeManifest.version != targetVersion) {
              throw StateError('Committed replacement does not match marker');
            }
            final updated = _mergePluginUpdate(activeManifest, state[pluginId]);
            final next = {...state, pluginId: updated};
            await _save(next.values);
            state = next;
            await marker.delete();
          } catch (error) {
            debugPrint(
              'PluginManager: Failed to finish replacement $pluginId: $error',
            );
          }
          continue;
        }
        late final PluginPersistedData manifest;
        try {
          manifest = PluginTomlParser.parseFromDirectory(replacement);
        } on PluginManifestException catch (error) {
          debugPrint(
            'PluginManager: Invalid replacement package $pluginId '
            '[${error.code}]: ${error.message}',
          );
          continue;
        }
        final entryPoint = File(path.join(replacement.path, '__main__.py'));
        if (manifest.id != pluginId || !await entryPoint.exists()) {
          debugPrint('PluginManager: Invalid replacement package $pluginId');
          continue;
        }
        try {
          PluginManifestValidator().validateNoConflicts(
            manifest.manifest!,
            state.values
                .where((plugin) => plugin.id != pluginId)
                .map((plugin) => plugin.manifest)
                .whereType<PluginManifestV2>(),
          );
        } on PluginManifestException catch (error) {
          debugPrint(
            'PluginManager: Conflicting replacement package $pluginId '
            '[${error.code}]: ${error.message}',
          );
          continue;
        }

        final updated = _mergePluginUpdate(manifest, state[pluginId]);
        final next = {...state, pluginId: updated};
        var metadataSaved = false;
        try {
          await _save(next.values);
          metadataSaved = true;
          await _activateNewPackage(root, updatesRoot, pluginId);
          if (await marker.exists()) await marker.delete();
          _intendedStatuses.remove(pluginId);
          state = next;
        } catch (error) {
          if (metadataSaved) {
            late Plugin rollbackPlugin;
            try {
              rollbackPlugin = _readActivePluginMetadata(
                root,
                pluginId,
                state[pluginId],
                _intendedStatuses[pluginId],
              );
            } catch (rollbackError) {
              final current = state[pluginId] ?? updated;
              rollbackPlugin = current.copyWith(
                status: PluginStatus.disabled,
                manifestErrorCode: rollbackError is PluginManifestException
                    ? rollbackError.code
                    : PluginManifestErrorCode.invalidSchema,
              );
              debugPrint(
                'PluginManager: Failed to read active metadata for '
                '$pluginId: $rollbackError',
              );
            }
            final rollbackState = {...state, pluginId: rollbackPlugin};
            state = rollbackState;
            try {
              await _save(rollbackState.values);
            } catch (rollbackError) {
              debugPrint(
                'PluginManager: Failed to restore metadata for '
                '$pluginId: $rollbackError',
              );
            }
          }
          debugPrint('PluginManager: Failed to apply $pluginId: $error');
        }
      }
    }
    _syncHostContributions();
    _removeOrphanContributions();
  }

  Future<void> autoStart() async {
    await ref
        .read(activationManagerProvider.notifier)
        .activateOnStartup(state.values);
  }

  Future<void> changeStatus(String id, PluginStatus status) async {
    final plugin = state[id];
    if (plugin == null) return;
    if (status == PluginStatus.usable) {
      final manifest = plugin.manifest;
      if (manifest == null) {
        throw PluginManifestException(
          plugin.manifestErrorCode ?? PluginManifestErrorCode.missingVersion,
          'Plugin $id does not have a valid Manifest v2',
        );
      }
      final validator = PluginManifestValidator()..validate(manifest);
      validator.validateNoConflicts(
        manifest,
        state.values
            .where((candidate) => candidate.id != id)
            .map((candidate) => candidate.manifest)
            .whereType<PluginManifestV2>(),
      );
    }
    if (status == PluginStatus.disabled) {
      _disableContributions(id);
    }
    final updated = plugin.copyWith(
      status: status,
      manifestErrorCode: status == PluginStatus.usable
          ? null
          : plugin.manifestErrorCode,
    );
    _intendedStatuses.remove(id);
    final next = {...state, id: updated};
    _syncHostContributions(next);
    state = next;
    if (status == PluginStatus.disabled) {
      unawaited(
        ref.read(activationManagerProvider.notifier).deactivate(updated),
      );
    }
    _onChanged?.call();
  }

  void _disableContributions(String pluginId) {
    final records = ref.read(dataContributionsProvider);
    if (!records.any((record) => record.pluginId == pluginId)) return;
    ref.read(dataContributionsProvider.notifier).state = [
      for (final record in records)
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
      final plugin = state[id]!;
      state = {
        ...state,
        id: plugin.copyWith(
          permissions: restrictPluginPermissions(
            permissions,
            plugin.declaredPermissions,
          ),
        ),
      };
      _onChanged?.call();
    }
  }

  /// Returns whether an installed plugin was updated.
  Future<bool> install(String packagePath) =>
      _runExclusive(() => _install(packagePath));

  Future<bool> _install(String packagePath) async {
    _requireMetadata();
    final root = await _supportDirectory();
    final updatesRoot = await Directory(
      path.join(root.path, _pluginUpdatesDirectoryName),
    ).create(recursive: true);
    final blocked = await _recoverNewBackups(root, updatesRoot, state);
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
      final normalizedManifest = manifest.manifest!;
      final newRoot = await Directory(
        path.join(updatesRoot.path, _newDirectoryName),
      ).create(recursive: true);
      final newManifests = <PluginManifestV2>[];
      await for (final entity in newRoot.list(followLinks: false)) {
        if (entity is! Directory) continue;
        try {
          final newManifest = PluginTomlParser.parseFromDirectory(entity);
          if (newManifest.id != manifest.id &&
              newManifest.id == path.basename(entity.path)) {
            newManifests.add(newManifest.manifest!);
          }
        } on PluginManifestException {
          // Invalid replacement transactions are handled during recovery.
        }
      }
      PluginManifestValidator().validateNoConflicts(normalizedManifest, [
        ...state.values
            .where((plugin) => plugin.id != manifest.id)
            .map((plugin) => plugin.manifest)
            .whereType<PluginManifestV2>(),
        ...newManifests,
      ]);
      final active = _pluginChild(
        Directory(path.join(root.path, _pluginDirectoryName)),
        manifest.id,
      );
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
        throw const PluginManifestException(
          PluginManifestErrorCode.contributionConflict,
          'Plugin ID conflicts with an installed plugin',
        );
      }
      for (final directory in [
        Directory(path.join(root.path, _pluginDirectoryName)),
        newRoot,
        activeBackupsRoot,
      ]) {
        if (!await directory.exists()) continue;
        await for (final entity in directory.list(followLinks: false)) {
          final name = path.basename(entity.path);
          if (name != manifest.id &&
              name.toLowerCase() == manifest.id.toLowerCase()) {
            throw const PluginManifestException(
              PluginManifestErrorCode.contributionConflict,
              'Plugin ID conflicts with an installed plugin',
            );
          }
        }
      }
      final replacement = _pluginChild(newRoot, manifest.id);
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
          await replacement.exists() ||
          removalPending;

      final previousIntendedStatus = _intendedStatuses[manifest.id];
      var showingUpdateInstall = false;
      if (updatePending &&
          existingPlugin != null &&
          existingPlugin.status != PluginStatus.uninstalled) {
        _intendedStatuses[manifest.id] = _persistablePluginStatus(
          previousIntendedStatus ?? existingPlugin.status,
        );
        state = {
          ...state,
          manifest.id: existingPlugin.copyWith(status: PluginStatus.installing),
        };
        showingUpdateInstall = true;
      }

      if (updatePending) {
        final currentDirectory = await resolvePluginPackageDirectory(
          root,
          manifest.id,
        );
        if (await currentDirectory.exists()) {
          await _restoreUserDirectories(
            currentDirectory,
            staged,
            Directory(path.join(updatesRoot.path, _trashDirectoryName)),
          );
        }
        final runManager = ref.read(pluginRunManagerProvider.notifier);
        final wasRunning = runManager.isRunning(manifest.id);
        final oldPlugin = existingPlugin;
        if (wasRunning && oldPlugin != null) await runManager.stop(oldPlugin);

        final marker = pendingPluginDeletionMarker(root, manifest.id);
        final markerExisted = await marker.exists();
        final previousMarkerContents = markerExisted
            ? await marker.readAsString()
            : null;
        final backup = _pluginChild(
          Directory(path.join(updatesRoot.path, _newBackupsDirectoryName)),
          manifest.id,
        );
        try {
          await _replaceNewPackage(updatesRoot, manifest.id, staged);
          await _writePendingDeletionMarker(
            root,
            manifest.id,
            manifest.version,
          );
          if (removalPending) {
            await removal.writeAsString('reinstall', flush: true);
          }

          final intendedStatus = removalPending
              ? PluginStatus.usable
              : _persistablePluginStatus(
                  previousIntendedStatus ??
                      oldPlugin?.status ??
                      PluginStatus.usable,
                );
          final updated = _mergePluginUpdate(
            manifest,
            oldPlugin,
          ).copyWith(status: intendedStatus);
          final next = {...state, manifest.id: updated};
          _intendedStatuses.remove(manifest.id);
          await _save(next.values);
          _syncHostContributions(next);
          state = next;

          if (updated.status == PluginStatus.usable) {
            if (updated.type == PluginType.data) {
              await runManager.runOnce(updated);
            } else if (wasRunning) {
              await runManager.start(updated);
            }
          }
          return true;
        } catch (_) {
          await _trashDirectory(
            replacement,
            Directory(path.join(updatesRoot.path, _trashDirectoryName)),
          );
          if (await backup.exists()) await backup.rename(replacement.path);
          if (previousMarkerContents != null) {
            await marker.writeAsString(previousMarkerContents, flush: true);
          } else if (await marker.exists()) {
            await marker.delete();
          }
          if (showingUpdateInstall && oldPlugin != null) {
            if (previousIntendedStatus == null) {
              _intendedStatuses.remove(manifest.id);
            } else {
              _intendedStatuses[manifest.id] = previousIntendedStatus;
            }
            state = {...state, manifest.id: oldPlugin};
          }
          if (wasRunning && oldPlugin != null) {
            await runManager.start(oldPlugin);
          }
          rethrow;
        }
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
        await _replaceNewPackage(updatesRoot, manifest.id, staged);
        await _writePendingDeletionMarker(root, manifest.id, manifest.version);
        await _activateNewPackage(root, updatesRoot, manifest.id);
        final marker = pendingPluginDeletionMarker(root, manifest.id);
        if (await marker.exists()) await marker.delete();
        _syncHostContributions(next);
        state = next;

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
            replacement,
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
    final blocked = await _recoverNewBackups(root, updatesRoot, state);
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
    _syncHostContributions(next);
    state = next;
    _removeContributions(pluginId);
    await ref
        .read(activationManagerProvider.notifier)
        .deactivate(next[pluginId]!);

    final replacement = _pluginChild(
      Directory(path.join(updatesRoot.path, _newDirectoryName)),
      pluginId,
    );
    final replacementBackup = _pluginChild(
      Directory(path.join(updatesRoot.path, _newBackupsDirectoryName)),
      pluginId,
    );
    final updateMarker = pendingPluginDeletionMarker(root, pluginId);
    final trashRoot = Directory(
      path.join(updatesRoot.path, _trashDirectoryName),
    );
    try {
      await _trashDirectory(replacement, trashRoot);
      await _trashDirectory(replacementBackup, trashRoot);
      if (await updateMarker.exists()) await updateMarker.delete();
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
    unawaited(ref.read(pluginRunManagerProvider.notifier).restart(plugin));
  }
}

final StateNotifierProvider<PluginManagerNotifier, Map<String, Plugin>>
pluginManagerProvider = StateNotifierProvider(
  (ref) => PluginManagerNotifier(ref),
);
