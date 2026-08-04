import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';

/// Topic emitted when a Manifest configuration value changes.
abstract class ConfigurationTopics {
  static const String changed = 'configuration.changed';
}

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
  }) : _emit = emit,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _dataDirectoryForPlugin = dataDirectoryForPlugin;

  final ContributionRegistry registry;
  final void Function(String topic, Map<String, dynamic> payload) _emit;
  final Future<Directory> Function() _supportDirectory;
  final String Function(String pluginId)? _dataDirectoryForPlugin;

  final Map<String, Map<String, Object?>> _values = {};
  final Map<String, Future<void>> _loads = {};

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
  Future<Object?> set(String pluginId, String id, Object? value) async {
    await _ensureLoaded(pluginId);
    final contribution = _contribution(pluginId, id);
    if (contribution == null) {
      throw StateError('Unknown configuration: $id');
    }
    _validate(contribution, value);
    final previous = await get(pluginId, id);
    _values.putIfAbsent(pluginId, () => {})[id] = value;
    await _persist(pluginId);
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
      try {
        final file = await _fileFor(pluginId);
        if (!await file.exists()) {
          _values[pluginId] = {};
          return;
        }
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          _values[pluginId] = {
            for (final entry in decoded.entries)
              entry.key.toString(): entry.value,
          };
        } else {
          _values[pluginId] = {};
        }
      } catch (_) {
        _values[pluginId] = {};
      }
    });
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
