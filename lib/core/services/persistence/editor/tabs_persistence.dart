import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';

class TabsPersistedData {
  final List<PersistedTab> tabs;
  final int selectedTabIndex;

  /// File path of the tab that was selected at save time.
  ///
  /// [selectedTabIndex] alone is not restorable: the persisted list only
  /// contains `file` tabs while the live tab strip also holds the welcome tab,
  /// git diff tabs and plugin views, and files deleted while the app was
  /// closed are dropped on restore. Both make the saved index drift. Resolving
  /// the selection by path keeps it correct in every one of those cases.
  /// [selectedTabIndex] is still written and read as a fallback for sessions
  /// saved before this field existed.
  final String? selectedTabPath;

  TabsPersistedData({
    required this.tabs,
    required this.selectedTabIndex,
    this.selectedTabPath,
  });

  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'selectedTabIndex': selectedTabIndex,
    'selectedTabPath': selectedTabPath,
  };

  factory TabsPersistedData.fromJson(Map<String, dynamic> json) =>
      TabsPersistedData(
        tabs:
            (json['tabs'] as List<dynamic>?)
                ?.map((t) => PersistedTab.fromJson(t as Map<String, dynamic>))
                .toList() ??
            [],
        selectedTabIndex: json['selectedTabIndex'] as int? ?? 0,
        selectedTabPath: json['selectedTabPath'] as String?,
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
      // Write to a sibling temp file and rename into place. A crash or power
      // loss mid-write would otherwise leave truncated JSON here, and because
      // `load` swallows parse errors into `null` that silently discards every
      // open tab *and* every unsaved buffer. Same pattern PluginPersistence
      // already uses.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(data.toJson()), flush: true);
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('TabsPersistence: Failed to save: $e');
    }
  }
}
