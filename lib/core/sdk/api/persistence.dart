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

class SdkPersistence extends StateNotifier<PluginRunManager?> {
  final Ref ref;
  SdkPersistence(this.ref) : super(null);

  void bind(PluginRunManager runManager) {
    state = runManager;
    runManager.registerHandler(SdkPersistenceCommands.get, _handleGet);
    runManager.registerHandler(SdkPersistenceCommands.set, _handleSet);
    runManager.registerHandler(SdkPersistenceCommands.delete, _handleDelete);
    runManager.registerHandler(SdkPersistenceCommands.listGroups, _handleListGroups);
    runManager.registerHandler(SdkPersistenceCommands.listKeys, _handleListKeys);
    runManager.registerHandler(SdkPersistenceCommands.clear, _handleClear);
  }

  String get _dataPath => '${state!.assetsPath}/data';

  Future<Directory> _ensureGroupDir(String group) async {
    final dir = Directory('$_dataPath/$group');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ── Handlers ──

  void _handleGet(
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

    final file = File('$_dataPath/$group/$key.json');
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
      final dir = await _ensureGroupDir(group);
      final file = File('${dir.path}/$key.json');
      await file.writeAsString(jsonEncode(value));
      _respondOk(envelope, respond);
    } catch (e) {
      _respondError(envelope, respond, '写入失败: $e');
    }
  }

  void _handleDelete(
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

    final file = File('$_dataPath/$group/$key.json');
    if (await file.exists()) {
      await file.delete();
    }
    _respondOk(envelope, respond, data: true);
  }

  void _handleListGroups(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final dir = Directory(_dataPath);
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
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final group = payload['group']?.toString() ?? '';

    if (group.isEmpty) {
      _respondError(envelope, respond, '缺少 group');
      return;
    }

    final dir = Directory('$_dataPath/$group');
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
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final group = payload['group']?.toString() ?? '';

    if (group.isEmpty) {
      _respondError(envelope, respond, '缺少 group');
      return;
    }

    final dir = Directory('$_dataPath/$group');
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

  @override
  void dispose() {
    state?.unregisterHandler(SdkPersistenceCommands.get);
    state?.unregisterHandler(SdkPersistenceCommands.set);
    state?.unregisterHandler(SdkPersistenceCommands.delete);
    state?.unregisterHandler(SdkPersistenceCommands.listGroups);
    state?.unregisterHandler(SdkPersistenceCommands.listKeys);
    state?.unregisterHandler(SdkPersistenceCommands.clear);
    super.dispose();
  }
}

final StateNotifierProvider<SdkPersistence, PluginRunManager?>
sdkPersistenceProvider = StateNotifierProvider(
  (ref) => SdkPersistence(ref),
);
