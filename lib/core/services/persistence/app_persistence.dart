import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppPersistedData {
  final String themeMode;
  final int? themeColorValue;

  AppPersistedData({required this.themeMode, this.themeColorValue});

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'themeColorValue': themeColorValue,
  };

  factory AppPersistedData.fromJson(Map<String, dynamic> json) =>
      AppPersistedData(
        themeMode: json['themeMode'] as String? ?? 'system',
        themeColorValue: json['themeColorValue'] as int?,
      );
}

class AppPersistence {
  static const _fileName = 'app.json';

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    final subDir = Directory('${dir.path}/pyrite_ide');
    if (!await subDir.exists()) await subDir.create(recursive: true);
    return File('${subDir.path}/$_fileName');
  }

  Future<AppPersistedData?> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return AppPersistedData.fromJson(json);
    } catch (e) {
      debugPrint('AppPersistence: Failed to load: $e');
      return null;
    }
  }

  Future<void> save(AppPersistedData data) async {
    try {
      final file = await _file;
      await file.writeAsString(jsonEncode(data.toJson()));
    } catch (e) {
      debugPrint('AppPersistence: Failed to save: $e');
    }
  }
}
