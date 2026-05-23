import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class WorkspacePersistedData {
  final String? workspacePath;

  WorkspacePersistedData({this.workspacePath});

  Map<String, dynamic> toJson() => {
        'workspacePath': workspacePath,
      };

  factory WorkspacePersistedData.fromJson(Map<String, dynamic> json) =>
      WorkspacePersistedData(
        workspacePath: json['workspacePath'] as String?,
      );
}

class WorkspacePersistence {
  static const _fileName = 'workspace.json';

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    final subDir = Directory('${dir.path}/pyrite_ide');
    if (!await subDir.exists()) await subDir.create(recursive: true);
    return File('${subDir.path}/$_fileName');
  }

  Future<WorkspacePersistedData?> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return WorkspacePersistedData.fromJson(json);
    } catch (e) {
      debugPrint('WorkspacePersistence: Failed to load: $e');
      return null;
    }
  }

  Future<void> save(WorkspacePersistedData data) async {
    try {
      final file = await _file;
      await file.writeAsString(jsonEncode(data.toJson()));
    } catch (e) {
      debugPrint('WorkspacePersistence: Failed to save: $e');
    }
  }
}
