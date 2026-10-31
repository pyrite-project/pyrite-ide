import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/models/window_placement.dart';

class AppPersistedData {
  final String themeMode;
  final String themeStyle;
  final int? themeColorValue;
  final String editorThemeKey;
  final String? activePluginThemeId;
  final bool welcomeCompleted;
  final String activeLocale;
  final bool alwaysOnTop;

  /// Last window geometry, or null when the window shell has not published one
  /// yet or the persisted entry was invalid. Written under the `window` key.
  final WindowPlacement? windowPlacement;

  AppPersistedData({
    required this.themeMode,
    this.themeStyle = 'standard',
    this.themeColorValue,
    this.editorThemeKey = 'atom-one',
    this.activePluginThemeId,
    this.welcomeCompleted = false,
    this.activeLocale = 'zh-CN',
    this.alwaysOnTop = false,
    this.windowPlacement,
  });

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'themeStyle': themeStyle,
    'themeColorValue': themeColorValue,
    'editorThemeKey': editorThemeKey,
    'activePluginThemeId': activePluginThemeId,
    'welcomeCompleted': welcomeCompleted,
    'activeLocale': activeLocale,
    'alwaysOnTop': alwaysOnTop,
    'window': windowPlacement?.toJson(),
  };

  factory AppPersistedData.fromJson(Map<String, dynamic> json) {
    final rawWindow = json['window'];
    return AppPersistedData(
      themeMode: json['themeMode'] as String? ?? 'system',
      themeStyle: json['themeStyle'] as String? ?? 'standard',
      themeColorValue: json['themeColorValue'] as int?,
      editorThemeKey: json['editorThemeKey'] as String? ?? 'atom-one',
      activePluginThemeId: json['activePluginThemeId'] as String?,
      welcomeCompleted: json['welcomeCompleted'] as bool? ?? false,
      activeLocale: json['activeLocale'] as String? ?? 'zh-CN',
      alwaysOnTop: json['alwaysOnTop'] as bool? ?? false,
      windowPlacement: rawWindow is Map
          ? WindowPlacement.fromJson(Map<String, dynamic>.from(rawWindow))
          : null,
    );
  }
}

class AppPersistence {
  /// Creates a persistence instance writing `app.json` below
  /// [getApplicationSupportDirectory] by default.
  ///
  /// [fileResolver] overrides the file location. Tests use it to point at a
  /// temporary directory without the platform path provider; production code
  /// leaves it unset and keeps the existing `<support>/data/app.json` path.
  AppPersistence({Future<File> Function()? fileResolver})
    : _fileResolver = fileResolver;

  static const _fileName = 'app.json';

  final Future<File> Function()? _fileResolver;

  Future<File> get _file async {
    final resolver = _fileResolver;
    if (resolver != null) return resolver();
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
      // Temp file + rename, like the other JSON stores: a crash mid-write
      // leaves truncated JSON behind, and load() turns a parse error into
      // null, which silently resets this store to its defaults.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(data.toJson()), flush: true);
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('AppPersistence: Failed to save: $e');
    }
  }

  /// Merges [changes] into the raw persisted JSON, creating the file when it
  /// does not exist yet.
  ///
  /// Unlike [save], this preserves keys this build does not know about (and
  /// fields another part of the app last wrote) by reading the current file
  /// verbatim instead of mapping it through [AppPersistedData]. An unreadable
  /// or malformed file is treated as empty: a failed read must not prevent a
  /// caller such as the welcome flow from persisting its flag.
  Future<void> patch(Map<String, Object?> changes) async {
    try {
      final file = await _file;
      var json = <String, dynamic>{};
      if (await file.exists()) {
        try {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map<String, dynamic>) json = decoded;
        } catch (e) {
          debugPrint(
            'AppPersistence: Ignoring unreadable file before patch: $e',
          );
        }
      }
      json.addAll(changes);
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('AppPersistence: Failed to patch: $e');
    }
  }
}
