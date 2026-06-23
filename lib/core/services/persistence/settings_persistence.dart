import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class SettingsPersistedData {
  final String editorTextFont;
  final double editorFontSize;
  final bool editorWordWrap;
  final bool editorLineNumber;
  final bool useLsp;
  final String lspWebSocketPath;
  final bool disableWarning;
  final bool disableError;
  final bool chineseToUnicodeConversion;
  final bool enableSignalDetection;
  final String uploadConfirmStyle;

  SettingsPersistedData({
    required this.editorTextFont,
    required this.editorFontSize,
    required this.editorWordWrap,
    required this.editorLineNumber,
    required this.useLsp,
    required this.lspWebSocketPath,
    required this.disableWarning,
    required this.disableError,
    this.chineseToUnicodeConversion = true,
    this.enableSignalDetection = true,
    this.uploadConfirmStyle = 'toolbar',
  });

  Map<String, dynamic> toJson() => {
    'editorTextFont': editorTextFont,
    'editorFontSize': editorFontSize,
    'editorWordWrap': editorWordWrap,
    'editorLineNumber': editorLineNumber,
    'useLsp': useLsp,
    'lspWebSocketPath': lspWebSocketPath,
    'disableWarning': disableWarning,
    'disableError': disableError,
    'chineseToUnicodeConversion': chineseToUnicodeConversion,
    'enableSignalDetection': enableSignalDetection,
    'uploadConfirmStyle': uploadConfirmStyle,
  };

  factory SettingsPersistedData.fromJson(Map<String, dynamic> json) =>
      SettingsPersistedData(
        editorTextFont: json['editorTextFont'] as String? ?? 'JetBrains Mono',
        editorFontSize: (json['editorFontSize'] as num?)?.toDouble() ?? 15,
        editorWordWrap: json['editorWordWrap'] as bool? ?? false,
        editorLineNumber: json['editorLineNumber'] as bool? ?? true,
        useLsp: json['useLsp'] as bool? ?? true,
        lspWebSocketPath:
            json['lspWebSocketPath'] as String? ?? '127.0.0.1:2026',
        disableWarning: json['disableWarning'] as bool? ?? false,
        disableError: json['disableError'] as bool? ?? false,
        chineseToUnicodeConversion:
            json['chineseToUnicodeConversion'] as bool? ?? true,
        enableSignalDetection:
            json['enableSignalDetection'] as bool? ?? true,
        uploadConfirmStyle:
            json['uploadConfirmStyle'] as String? ?? 'toolbar',
      );
}

class SettingsPersistence {
  static const _fileName = 'settings.json';

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    final subDir = Directory('${dir.path}/pyrite_ide');
    if (!await subDir.exists()) await subDir.create(recursive: true);
    return File('${subDir.path}/$_fileName');
  }

  Future<SettingsPersistedData?> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return SettingsPersistedData.fromJson(json);
    } catch (e) {
      debugPrint('SettingsPersistence: Failed to load: $e');
      return null;
    }
  }

  Future<void> save(SettingsPersistedData data) async {
    try {
      final file = await _file;
      await file.writeAsString(jsonEncode(data.toJson()));
    } catch (e) {
      debugPrint('SettingsPersistence: Failed to save: $e');
    }
  }
}
