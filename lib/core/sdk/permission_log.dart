import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class PermissionLogEntry {
  final String pluginId;
  final String command;
  final String required;
  final bool granted;
  final int timestamp;

  PermissionLogEntry({
    required this.pluginId,
    required this.command,
    required this.required,
    required this.granted,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'pluginId': pluginId,
        'command': command,
        'required': required,
        'granted': granted,
        'timestamp': timestamp,
      };

  factory PermissionLogEntry.fromJson(Map<String, dynamic> json) {
    return PermissionLogEntry(
      pluginId: json['pluginId'] as String? ?? '',
      command: json['command'] as String? ?? '',
      required: json['required'] as String? ?? '',
      granted: json['granted'] as bool? ?? false,
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }
}

class PermissionLogService extends ChangeNotifier {
  static const int _maxEntries = 1000;
  static const String _fileName = 'permission_logs.json';

  final List<PermissionLogEntry> _entries = [];
  Timer? _flushTimer;
  bool _dirty = false;

  List<PermissionLogEntry> get entries => List.unmodifiable(_entries);

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    final subDir = Directory('${dir.path}/data');
    if (!await subDir.exists()) await subDir.create(recursive: true);
    return File('${subDir.path}/$_fileName');
  }

  Future<void> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final list = json['logs'] as List<dynamic>? ?? [];
      _entries.clear();
      _entries.addAll(list.map(
        (e) => PermissionLogEntry.fromJson(e as Map<String, dynamic>),
      ));
    } catch (e) {
      debugPrint('PermissionLogService: Failed to load: $e');
    }
  }

  void add(PermissionLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    _dirty = true;
    _scheduleFlush();
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    _dirty = true;
    _scheduleFlush();
    notifyListeners();
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 1), _flush);
  }

  Future<void> _flush() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      final file = await _file;
      await file.writeAsString(jsonEncode({
        'logs': _entries.map((e) => e.toJson()).toList(),
      }));
    } catch (e) {
      debugPrint('PermissionLogService: Failed to flush: $e');
    }
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _flush();
    super.dispose();
  }
}

final permissionLogServiceProvider =
    ChangeNotifierProvider<PermissionLogService>(
  (ref) => PermissionLogService(),
);
