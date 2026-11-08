import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';

class DataContributionsPersistence {
  static const _fileName = 'data_contributions.json';

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    final subDir = Directory('${dir.path}/data');
    if (!await subDir.exists()) await subDir.create(recursive: true);
    return File('${subDir.path}/$_fileName');
  }

  Future<List<DataContributionRecord>?> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final records = json['records'] as List? ?? const [];
      return records
          .whereType<Map>()
          .map(
            (item) => DataContributionRecord.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('DataContributionsPersistence: Failed to load: $e');
      return null;
    }
  }

  Future<void> save(List<DataContributionRecord> records) async {
    try {
      final file = await _file;
      // Temp file + rename, like TabsPersistence and PluginPersistence: a crash
      // mid-write would otherwise leave truncated JSON here, and `load` turns a
      // parse error into null, which silently drops every contributed theme,
      // locale pack and stubs profile.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'records': records.map((record) => record.toJson()).toList(),
        }),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('DataContributionsPersistence: Failed to save: $e');
    }
  }
}
