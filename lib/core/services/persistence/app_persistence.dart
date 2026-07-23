import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppPersistedData {
  final String themeMode;
  final String themeStyle;
  final int? themeColorValue;
  final String editorThemeKey;
  final String? activePluginThemeId;
  final bool welcomeCompleted;
  final String activeLocale;

  AppPersistedData({
    required this.themeMode,
    this.themeStyle = 'standard',
    this.themeColorValue,
    this.editorThemeKey = 'atom-one',
    this.activePluginThemeId,
    this.welcomeCompleted = false,
    this.activeLocale = 'zh-CN',
  });

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'themeStyle': themeStyle,
    'themeColorValue': themeColorValue,
    'editorThemeKey': editorThemeKey,
    'activePluginThemeId': activePluginThemeId,
    'welcomeCompleted': welcomeCompleted,
    'activeLocale': activeLocale,
  };

  factory AppPersistedData.fromJson(Map<String, dynamic> json) =>
      AppPersistedData(
        themeMode: json['themeMode'] as String? ?? 'system',
        themeStyle: json['themeStyle'] as String? ?? 'standard',
        themeColorValue: json['themeColorValue'] as int?,
        editorThemeKey: json['editorThemeKey'] as String? ?? 'atom-one',
        activePluginThemeId: json['activePluginThemeId'] as String?,
        welcomeCompleted: json['welcomeCompleted'] as bool? ?? false,
        activeLocale: json['activeLocale'] as String? ?? 'zh-CN',
      );
}

class AppPersistence {
  static const _fileName = 'app.json';

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    final subDir = Directory('${dir.path}/data');
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
