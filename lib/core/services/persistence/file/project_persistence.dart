import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ProjectPersistedData {
  final String? projectPath;

  ProjectPersistedData({this.projectPath});

  Map<String, dynamic> toJson() => {'projectPath': projectPath};

  factory ProjectPersistedData.fromJson(Map<String, dynamic> json) =>
      ProjectPersistedData(projectPath: json['projectPath'] as String?);
}

class ProjectPersistence {
  static const _fileName = 'project.json';

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    final subDir = Directory('${dir.path}/data');
    if (!await subDir.exists()) await subDir.create(recursive: true);
    return File('${subDir.path}/$_fileName');
  }

  Future<ProjectPersistedData?> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return ProjectPersistedData.fromJson(json);
    } catch (e) {
      debugPrint('ProjectPersistence: Failed to load: $e');
      return null;
    }
  }

  Future<void> save(ProjectPersistedData data) async {
    try {
      final file = await _file;
      await file.writeAsString(jsonEncode(data.toJson()));
    } catch (e) {
      debugPrint('ProjectPersistence: Failed to save: $e');
    }
  }
}
