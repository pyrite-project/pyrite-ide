import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';
import 'package:pyrite_ide/core/services/logging/app_log.dart';

/// Topic emitted when a Manifest configuration value changes.
abstract class ConfigurationTopics {
  static const String changed = 'configuration.changed';
}

/// Receives configuration load failures; [AppLog.e] is the real implementation.
typedef PluginConfigLogWriter =
    void Function(
      String area,
      String message, {
      Object? error,
      StackTrace? stack,
    });

/// In-memory + on-disk store for Manifest `contributes.configuration` values.
///
/// Keys are scoped to `(pluginId, configurationId)`. Defaults come from the
/// contribution registry; values persist under each plugin's `data/` directory.
class PluginConfigStore {
  PluginConfigStore({
    required this.registry,
    required void Function(String topic, Map<String, dynamic> payload) emit,
    Future<Directory> Function()? supportDirectory,
    String Function(String pluginId)? dataDirectoryForPlugin,
    PluginConfigLogWriter? logWriter,
  }) : _emit = emit,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _dataDirectoryForPlugin = dataDirectoryForPlugin,
       _log = logWriter ?? AppLog.e;

  final ContributionRegistry registry;
  final void Function(String topic, Map<String, dynamic> payload) _emit;
  final Future<Directory> Function() _supportDirectory;
  final String Function(String pluginId)? _dataDirectoryForPlugin;
  final PluginConfigLogWriter _log;

  final Map<String, Map<String, Object?>> _values = {};
  final Map<String, Future<void>> _loads = {};

  /// Plugins whose configuration failed to load and could not be preserved.
  /// Writes are refused for them so the unreadable bytes are not overwritten.
  final Set<String> _failedLoads = {};

  /// Returns the effective value for [id] owned by [pluginId].
  Future<Object?> get(String pluginId, String id) async {
    await _ensureLoaded(pluginId);
    final contribution = _contribution(pluginId, id);
    if (contribution == null) {
      throw StateError('Unknown configuration: $id');
    }
    final stored = _values[pluginId]?[id];
    return stored ?? contribution.defaultValue;
  }

  /// Lists every configuration contribution for [pluginId] with effective values.
  Future<List<Map<String, dynamic>>> list(String pluginId) async {
    await _ensureLoaded(pluginId);
    final entries = registry.configuration.all
        .where((entry) => entry.pluginId == pluginId)
        .toList(growable: false);
    return [
      for (final entry in entries)
        {
          'id': entry.value.id,
          'title': entry.value.title,
          'type': entry.value.type,
          if (entry.value.description.isNotEmpty)
            'description': entry.value.description,
          'default': entry.value.defaultValue,
          'value':
              _values[pluginId]?[entry.value.id] ?? entry.value.defaultValue,
          if (entry.value.enumValues.isNotEmpty) 'enum': entry.value.enumValues,
          'order': entry.value.order,
        },
    ]..sort((a, b) {
      final byOrder = (a['order'] as int).compareTo(b['order'] as int);
      if (byOrder != 0) return byOrder;
      return (a['id'] as String).compareTo(b['id'] as String);
    });
  }

  /// Validates and stores [value], persists, and emits [ConfigurationTopics.changed].
  ///
  /// The in-memory map is committed only after the disk write succeeds: a
  /// value that lives in memory but not in `configuration.json` would silently
  /// vanish on the next start, which is far more confusing than the write
  /// error the caller sees here.
  Future<Object?> set(String pluginId, String id, Object? value) async {
    await _ensureLoaded(pluginId);
    _throwIfLoadFailed(pluginId);
    final contribution = _contribution(pluginId, id);
    if (contribution == null) {
      throw StateError('Unknown configuration: $id');
    }
    _validate(contribution, value);
    // Rollback needs the raw stored entry, not `previous`: the effective value
    // substitutes the contribution default, and persisting that default would
    // turn "no stored value" into an explicit one.
    final stored = _values[pluginId]?[id];
    final previous = stored ?? contribution.defaultValue;
    final values = _values.putIfAbsent(pluginId, () => {});
    values[id] = value;
    try {
      await _persist(pluginId);
    } catch (_) {
      if (stored == null) {
        values.remove(id);
      } else {
        values[id] = stored;
      }
      rethrow;
    }
    if (!_jsonEquals(previous, value)) {
      _emit(ConfigurationTopics.changed, {
        'pluginId': pluginId,
        'id': id,
        'value': value,
      });
    }
    return value;
  }

  PluginConfigurationContribution? _contribution(String pluginId, String id) {
    final entry = registry.configuration.byId(id);
    if (entry == null || entry.pluginId != pluginId) return null;
    return entry.value;
  }

  Future<void> _ensureLoaded(String pluginId) {
    return _loads.putIfAbsent(pluginId, () async {
      File? file;
      try {
        file = await _fileFor(pluginId);
        if (!await file.exists()) {
          _failedLoads.remove(pluginId);
          _values[pluginId] = {};
          return;
        }
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) {
          throw const FormatException('Configuration must be a JSON object');
        }
        _failedLoads.remove(pluginId);
        _values[pluginId] = {
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value,
        };
      } catch (error, stack) {
        await _handleLoadFailure(pluginId, file, error, stack);
        // A failed load must not be cached as an empty configuration: a later
        // access retries, which is also what lets a transient read heal.
        _loads.remove(pluginId);
      }
    });
  }

  /// Logs a load failure and moves the unreadable file aside.
  ///
  /// The original bytes are kept as `<configuration>.corrupt`; only when that
  /// is impossible is the plugin marked unsafe to write, because starting from
  /// an empty map would otherwise erase a configuration the user can no longer
  /// read from the store.
  Future<void> _handleLoadFailure(
    String pluginId,
    File? file,
    Object error,
    StackTrace stack,
  ) async {
    final backup = file == null ? null : await _preserveCorruptFile(file);
    if (backup == null) {
      _failedLoads.add(pluginId);
    } else {
      _failedLoads.remove(pluginId);
    }
    final message = StringBuffer(
      'Failed to load configuration for plugin "$pluginId"',
    );
    if (file != null) message.write(' from ${file.path}');
    if (backup != null) {
      message.write('; unreadable file preserved at ${backup.path}');
    } else {
      message.write('; it could not be preserved, so writes are refused');
    }
    _log('plugin-config', message.toString(), error: error, stack: stack);
  }

  /// Moves an unreadable configuration aside so a later [set] cannot erase it.
  ///
  /// An existing backup is never overwritten: a numbered sibling is used
  /// instead, so repeated corruption still leaves every copy recoverable.
  Future<File?> _preserveCorruptFile(File file) async {
    try {
      var backup = File('${file.path}.corrupt');
      var index = 1;
      while (await backup.exists()) {
        backup = File('${file.path}.corrupt.$index');
        index++;
      }
      return await file.rename(backup.path);
    } catch (_) {
      return null;
    }
  }

  void _throwIfLoadFailed(String pluginId) {
    if (!_failedLoads.contains(pluginId)) return;
    throw StateError(
      'Configuration for plugin "$pluginId" failed to load and could not be '
      'preserved; refusing to overwrite it',
    );
  }

  Future<void> _persist(String pluginId) async {
    final file = await _fileFor(pluginId);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_values[pluginId] ?? {}),
    );
  }

  Future<File> _fileFor(String pluginId) async {
    final custom = _dataDirectoryForPlugin;
    final dataDir = custom != null
        ? Directory(custom(pluginId))
        : Directory(
            path.join(
              (await _supportDirectory()).path,
              'plugin',
              pluginId,
              'data',
            ),
          );
    return File(path.join(dataDir.path, 'configuration.json'));
  }

  void _validate(PluginConfigurationContribution contribution, Object? value) {
    switch (contribution.type) {
      case 'boolean':
        if (value is! bool) {
          throw ArgumentError.value(value, 'value', 'Expected boolean');
        }
      case 'string':
        if (value is! String) {
          throw ArgumentError.value(value, 'value', 'Expected string');
        }
      case 'password':
        // Passwords are strings at rest, but the error must not carry the
        // value: store errors surface in dialogs and logs.
        if (value is! String) {
          throw ArgumentError('Expected a password string');
        }
      case 'number':
        if (value is! num) {
          throw ArgumentError.value(value, 'value', 'Expected number');
        }
      case 'integer':
        if (value is! int) {
          throw ArgumentError.value(value, 'value', 'Expected integer');
        }
      case 'array':
        if (value is! List) {
          throw ArgumentError.value(value, 'value', 'Expected array');
        }
      case 'object':
        if (value is! Map) {
          throw ArgumentError.value(value, 'value', 'Expected object');
        }
      default:
        throw StateError(
          'Unsupported configuration type: ${contribution.type}',
        );
    }
    if (contribution.enumValues.isNotEmpty &&
        !contribution.enumValues.any((item) => _jsonEquals(item, value))) {
      throw ArgumentError.value(value, 'value', 'Value is not in enum');
    }
  }

  static bool _jsonEquals(Object? a, Object? b) =>
      jsonEncode(a) == jsonEncode(b);
}

final Provider<PluginConfigStore> pluginConfigStoreProvider = Provider((ref) {
  return PluginConfigStore(
    registry: ref.watch(contributionRegistryProvider),
    emit: (topic, payload) =>
        ref.read(pluginEventBusProvider).emit(topic, payload),
  );
});
