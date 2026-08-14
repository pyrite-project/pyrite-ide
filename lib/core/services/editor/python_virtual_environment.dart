import 'dart:io';

import 'package:path/path.dart' as path;

class PythonVirtualEnvironment {
  const PythonVirtualEnvironment({
    required this.root,
    required this.interpreter,
  });

  final Directory root;
  final File interpreter;
}

/// Resolves the selected virtual environment or discovers `.venv` at the
/// workspace root when no environment has been selected.
PythonVirtualEnvironment? resolvePythonVirtualEnvironment({
  required String configuredVirtualEnvironment,
  String? workspacePath,
}) {
  final configuredPath = configuredVirtualEnvironment.trim();
  if (configuredPath.isNotEmpty) {
    final rootPath =
        path.isAbsolute(configuredPath) ||
            workspacePath == null ||
            workspacePath.trim().isEmpty
        ? configuredPath
        : path.normalize(path.join(workspacePath, configuredPath));
    return _fromDirectory(Directory(rootPath));
  }

  if (workspacePath == null || workspacePath.trim().isEmpty) return null;
  return _fromDirectory(Directory(path.join(workspacePath, '.venv')));
}

bool isWorkspaceDefaultVirtualEnvironment(
  PythonVirtualEnvironment virtualEnvironment, {
  String? workspacePath,
}) {
  if (workspacePath == null || workspacePath.trim().isEmpty) return false;
  return path.normalize(virtualEnvironment.root.path) ==
      path.normalize(path.join(workspacePath, '.venv'));
}

/// Builds the process environment used when launching tools in [environment].
Map<String, String> buildPythonVirtualEnvironmentEnvironment(
  PythonVirtualEnvironment environment, {
  Map<String, String>? baseEnvironment,
}) {
  final result = Map<String, String>.of(
    baseEnvironment ?? Platform.environment,
  );
  final interpreterDirectory = environment.interpreter.parent.path;
  final pathKey = result.keys.firstWhere(
    (key) => key.toLowerCase() == 'path',
    orElse: () => 'PATH',
  );
  final separator = Platform.isWindows ? ';' : ':';
  final existingPaths = (result[pathKey] ?? '')
      .split(separator)
      .where((entry) => entry.isNotEmpty && entry != interpreterDirectory);

  result['VIRTUAL_ENV'] = environment.root.path;
  // An inherited PYTHONHOME prevents a virtual environment from locating its
  // own standard library and site-packages.
  result['PYTHONHOME'] = '';
  result[pathKey] = [interpreterDirectory, ...existingPaths].join(separator);
  return result;
}

PythonVirtualEnvironment? _fromDirectory(Directory root) {
  if (!File(path.join(root.path, 'pyvenv.cfg')).existsSync()) return null;

  final scriptsDirectory = Platform.isWindows ? 'Scripts' : 'bin';
  final executableNames = Platform.isWindows
      ? const ['python.exe']
      : const ['python', 'python3'];
  for (final executableName in executableNames) {
    final interpreter = File(
      path.join(root.path, scriptsDirectory, executableName),
    );
    if (interpreter.existsSync()) {
      return PythonVirtualEnvironment(root: root, interpreter: interpreter);
    }
  }
  return null;
}
