import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';

class TabsPersistedData {
  /// The tabs of a session saved with a single group.
  ///
  /// Empty when the editor area was split: [groups] holds every tab then, so
  /// no buffer is written twice.
  final List<PersistedTab> tabs;

  /// One entry per group, in layout order; empty for a single group.
  final List<PersistedEditorGroup> groups;

  /// The layout tree [groups] are placed by, or null for a single group.
  final PersistedEditorLayout? layout;

  /// Which of [groups] is the primary group -- the one holding the welcome
  /// page, where new tabs fall back to while no group has focus.
  final int primaryGroupIndex;

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
    this.groups = const [],
    this.layout,
    this.primaryGroupIndex = 0,
  });

  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'selectedTabIndex': selectedTabIndex,
    'selectedTabPath': selectedTabPath,
    if (groups.isNotEmpty) 'groups': groups.map((g) => g.toJson()).toList(),
    if (layout != null) 'layout': layout!.toJson(),
    if (layout != null) 'primaryGroupIndex': primaryGroupIndex,
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
        groups:
            (json['groups'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(PersistedEditorGroup.fromJson)
                .toList() ??
            const [],
        layout: json['layout'] is Map<String, dynamic>
            ? PersistedEditorLayout.fromJson(
                json['layout'] as Map<String, dynamic>,
              )
            : null,
        primaryGroupIndex: (json['primaryGroupIndex'] as num?)?.toInt() ?? 0,
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
