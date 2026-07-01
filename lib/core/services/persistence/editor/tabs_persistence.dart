import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';

class TabsPersistedData {
  final List<PersistedTab> tabs;
  final int selectedTabIndex;

  TabsPersistedData({required this.tabs, required this.selectedTabIndex});

  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'selectedTabIndex': selectedTabIndex,
  };

  factory TabsPersistedData.fromJson(Map<String, dynamic> json) =>
      TabsPersistedData(
        tabs:
            (json['tabs'] as List<dynamic>?)
                ?.map((t) => PersistedTab.fromJson(t as Map<String, dynamic>))
                .toList() ??
            [],
        selectedTabIndex: json['selectedTabIndex'] as int? ?? 0,
      );
}

class TabsPersistence {
  static const _fileName = 'tabs.json';

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    final subDir = Directory('${dir.path}/data');
    if (!await subDir.exists()) await subDir.create(recursive: true);
    return File('${subDir.path}/$_fileName');
  }

  Future<TabsPersistedData?> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return TabsPersistedData.fromJson(json);
    } catch (e) {
      debugPrint('TabsPersistence: Failed to load: $e');
      return null;
    }
  }

  Future<void> save(TabsPersistedData data) async {
    try {
      final file = await _file;
      await file.writeAsString(jsonEncode(data.toJson()));
    } catch (e) {
      debugPrint('TabsPersistence: Failed to save: $e');
    }
  }
}
