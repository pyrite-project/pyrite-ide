import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  Future<Directory> _ensureGroupDir(String dataPath, String group) async {
    final dir = Directory('$dataPath/$group');
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

    if (group.isEmpty || key.isEmpty) {
      _respondError(envelope, respond, '缺少 group 或 key');
      return;
    }

    final file = File('$dataPath/$group/$key.json');
    if (!file.existsSync()) {
      _respondOk(envelope, respond, data: null);
      return;
    }

    try {
      final content = file.readAsStringSync();
      final value = jsonDecode(content);
      _respondOk(envelope, respond, data: value);
    } catch (e) {
      _respondError(envelope, respond, '读取失败: $e');
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

    if (group.isEmpty || key.isEmpty) {
      _respondError(envelope, respond, '缺少 group 或 key');
      return;
    }

    try {
      final dir = await _ensureGroupDir(dataPath, group);
      final file = File('${dir.path}/$key.json');
      await file.writeAsString(jsonEncode(value));
      _respondOk(envelope, respond);
    } catch (e) {
      _respondError(envelope, respond, '写入失败: $e');
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

    if (group.isEmpty || key.isEmpty) {
      _respondError(envelope, respond, '缺少 group 或 key');
      return;
    }

    final file = File('$dataPath/$group/$key.json');
    if (await file.exists()) {
      await file.delete();
    }
    _respondOk(envelope, respond, data: true);
  }

  void _handleListGroups(
    String dataPath,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final dir = Directory(dataPath);
    if (!await dir.exists()) {
      _respondOk(envelope, respond, data: <String>[]);
      return;
    }

    final groups = <String>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        groups.add(entity.path.split(Platform.pathSeparator).last);
      }
    }
    _respondOk(envelope, respond, data: groups);
  }

  void _handleListKeys(
    String dataPath,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final group = payload['group']?.toString() ?? '';

    if (group.isEmpty) {
      _respondError(envelope, respond, '缺少 group');
      return;
    }

    final dir = Directory('$dataPath/$group');
    if (!await dir.exists()) {
      _respondOk(envelope, respond, data: <String>[]);
      return;
    }

    final keys = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        final fileName = entity.path.split(Platform.pathSeparator).last;
        keys.add(fileName.substring(0, fileName.length - 5));
      }
    }
    _respondOk(envelope, respond, data: keys);
  }

  void _handleClear(
    String dataPath,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final group = payload['group']?.toString() ?? '';

    if (group.isEmpty) {
      _respondError(envelope, respond, '缺少 group');
      return;
    }

    final dir = Directory('$dataPath/$group');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _respondOk(envelope, respond);
  }

  // ── Response Helpers ──

  void _respondOk(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond, {
    dynamic data,
  }) {
    respond({
      'version': '0.0',
      'id': '',
      'type': 'sdk.response.ok',
      'payload': {'data': data},
      'reply_to': envelope['id'],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _respondError(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    String message,
  ) {
    respond({
      'version': '0.0',
      'id': '',
      'type': 'sdk.response.error',
      'payload': {'message': message},
      'reply_to': envelope['id'],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
}

final Provider<SdkPersistence> sdkPersistenceProvider = Provider(
  SdkPersistence.new,
);
