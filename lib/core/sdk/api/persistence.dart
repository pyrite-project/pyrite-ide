import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/api/sdk_response.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';

abstract class SdkPersistenceCommands {
  static const String get = 'sdk.persistence.get';
  static const String set = 'sdk.persistence.set';
  static const String delete = 'sdk.persistence.delete';
  static const String listGroups = 'sdk.persistence.list_groups';
  static const String listKeys = 'sdk.persistence.list_keys';
  static const String clear = 'sdk.persistence.clear';
}

class SdkPersistence {
  final Ref ref;
  SdkPersistence(this.ref);

  void bind(PluginRunManager runManager) {
    final dataPath = runManager.dataPath;
    runManager.registerHandler(
      SdkPersistenceCommands.get,
      (envelope, respond) => _handleGet(dataPath, envelope, respond),
    );
    runManager.registerHandler(
      SdkPersistenceCommands.set,
      (envelope, respond) => _handleSet(dataPath, envelope, respond),
    );
    runManager.registerHandler(
      SdkPersistenceCommands.delete,
      (envelope, respond) => _handleDelete(dataPath, envelope, respond),
    );
    runManager.registerHandler(
      SdkPersistenceCommands.listGroups,
      (envelope, respond) => _handleListGroups(dataPath, envelope, respond),
    );
    runManager.registerHandler(
      SdkPersistenceCommands.listKeys,
      (envelope, respond) => _handleListKeys(dataPath, envelope, respond),
    );
    runManager.registerHandler(
      SdkPersistenceCommands.clear,
      (envelope, respond) => _handleClear(dataPath, envelope, respond),
    );
  }

  /// A group or key names exactly one path segment below the plugin's data
  /// directory. Dots only join non-empty segments, so dots-only names and
  /// trailing dots cannot alias the data directory or its parent on platforms
  /// whose filesystems trim them; separators and drive prefixes are rejected
  /// outright.
  static final RegExp _segmentPattern = RegExp(
    r'^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$',
  );

  static String? _segmentError(String field, String value) {
    if (value.isEmpty) return '缺少 $field';
    if (value.contains('/') || value.contains('\\') || value.contains('..')) {
      return '$field 不能包含路径分隔符或 ".."';
    }
    if (value.replaceAll('.', '').isEmpty) {
      return '$field 不能只由点号组成';
    }
    if (!_segmentPattern.hasMatch(value)) {
      return '$field 只能包含字母、数字、下划线、连字符和单段内的点号';
    }
    return null;
  }

  /// Every handler that turns plugin-provided names into a filesystem path
  /// goes through this check first.
  static String? _groupKeyError(String? group, String? key) {
    if (group != null) {
      final error = _segmentError('group', group);
      if (error != null) return error;
    }
    if (key != null) {
      final error = _segmentError('key', key);
      if (error != null) return error;
    }
    return null;
  }

  static Directory _groupDirectory(String dataPath, String group) =>
      Directory(path.join(dataPath, group));

  static File _entryFile(String dataPath, String group, String key) =>
      File(path.join(dataPath, group, '$key.json'));

  Future<Directory> _ensureGroupDir(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ── Handlers ──

  void _handleGet(
    String dataPath,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final group = payload['group']?.toString() ?? '';
    final key = payload['key']?.toString() ?? '';

    final invalid = _groupKeyError(group, key);
    if (invalid != null) {
      respondError(envelope, respond, invalid);
      return;
    }

    final file = _entryFile(dataPath, group, key);
    if (!file.existsSync()) {
      respondOk(envelope, respond, data: null);
      return;
    }

    try {
      final content = file.readAsStringSync();
      final value = jsonDecode(content);
      respondOk(envelope, respond, data: value);
    } catch (e) {
      respondError(envelope, respond, '读取失败: $e');
    }
  }

  void _handleSet(
    String dataPath,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final group = payload['group']?.toString() ?? '';
    final key = payload['key']?.toString() ?? '';
    final value = payload['value'];

    final invalid = _groupKeyError(group, key);
    if (invalid != null) {
      respondError(envelope, respond, invalid);
      return;
    }

    try {
      final dir = await _ensureGroupDir(_groupDirectory(dataPath, group));
      final file = File(path.join(dir.path, '$key.json'));
      await file.writeAsString(jsonEncode(value));
      respondOk(envelope, respond);
    } catch (e) {
      respondError(envelope, respond, '写入失败: $e');
    }
  }

  void _handleDelete(
    String dataPath,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final group = payload['group']?.toString() ?? '';
    final key = payload['key']?.toString() ?? '';

    final invalid = _groupKeyError(group, key);
    if (invalid != null) {
      respondError(envelope, respond, invalid);
      return;
    }

    final file = _entryFile(dataPath, group, key);
    if (await file.exists()) {
      await file.delete();
    }
    respondOk(envelope, respond, data: true);
  }

  void _handleListGroups(
    String dataPath,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final dir = Directory(dataPath);
    if (!await dir.exists()) {
      respondOk(envelope, respond, data: <String>[]);
      return;
    }

    final groups = <String>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        groups.add(entity.path.split(Platform.pathSeparator).last);
      }
    }
    respondOk(envelope, respond, data: groups);
  }

  void _handleListKeys(
    String dataPath,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final group = payload['group']?.toString() ?? '';

    final invalid = _groupKeyError(group, null);
    if (invalid != null) {
      respondError(envelope, respond, invalid);
      return;
    }

    final dir = _groupDirectory(dataPath, group);
    if (!await dir.exists()) {
      respondOk(envelope, respond, data: <String>[]);
      return;
    }

    final keys = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        final fileName = entity.path.split(Platform.pathSeparator).last;
        keys.add(fileName.substring(0, fileName.length - 5));
      }
    }
    respondOk(envelope, respond, data: keys);
  }

  void _handleClear(
    String dataPath,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final group = payload['group']?.toString() ?? '';

    final invalid = _groupKeyError(group, null);
    if (invalid != null) {
      respondError(envelope, respond, invalid);
      return;
    }

    final dir = _groupDirectory(dataPath, group);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    respondOk(envelope, respond);
  }

  // ── Response Helpers ──
}

final Provider<SdkPersistence> sdkPersistenceProvider = Provider(
  SdkPersistence.new,
);
