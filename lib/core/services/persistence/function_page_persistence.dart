import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class FunctionPagePersistedData {
  final int desktopSelectedIndex;
  final int mobileSelectedIndex;
  final int tabletSelectedIndex;

  FunctionPagePersistedData({
    required this.desktopSelectedIndex,
    required this.mobileSelectedIndex,
    required this.tabletSelectedIndex,
  });

  Map<String, dynamic> toJson() => {
        'desktopSelectedIndex': desktopSelectedIndex,
        'mobileSelectedIndex': mobileSelectedIndex,
        'tabletSelectedIndex': tabletSelectedIndex,
      };

  factory FunctionPagePersistedData.fromJson(Map<String, dynamic> json) =>
      FunctionPagePersistedData(
        desktopSelectedIndex: json['desktopSelectedIndex'] as int? ?? 0,
        mobileSelectedIndex: json['mobileSelectedIndex'] as int? ?? 0,
        tabletSelectedIndex: json['tabletSelectedIndex'] as int? ?? 0,
      );
}

class FunctionPagePersistence {
  static const _fileName = 'function_page.json';

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    final subDir = Directory('${dir.path}/pyrite_ide');
    if (!await subDir.exists()) await subDir.create(recursive: true);
    return File('${subDir.path}/$_fileName');
  }

  Future<FunctionPagePersistedData?> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return FunctionPagePersistedData.fromJson(json);
    } catch (e) {
      debugPrint('FunctionPagePersistence: Failed to load: $e');
      return null;
    }
  }

  Future<void> save(FunctionPagePersistedData data) async {
    try {
      final file = await _file;
      await file.writeAsString(jsonEncode(data.toJson()));
    } catch (e) {
      debugPrint('FunctionPagePersistence: Failed to save: $e');
    }
  }
}
