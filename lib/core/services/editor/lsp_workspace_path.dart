import 'dart:io';

import 'package:path/path.dart' as path;

/// Uses the opened project as the LSP root for files it contains.
///
/// Language servers use the workspace root to locate `.venv`, pyproject.toml,
/// and other project configuration. Files opened outside that project retain
/// their parent directory as the single-file workspace.
String lspWorkspacePathForFile(File file, Directory? openedWorkspace) {
  if (openedWorkspace == null) return file.parent.path;

  final workspacePath = path.normalize(openedWorkspace.path);
  final filePath = path.normalize(file.path);
  if (filePath == workspacePath || path.isWithin(workspacePath, filePath)) {
    return workspacePath;
  }
  return file.parent.path;
}
