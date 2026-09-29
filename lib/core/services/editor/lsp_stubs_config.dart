import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/editor/python_virtual_environment.dart';
import 'package:pyrite_ide/core/services/settings.dart';

typedef LspProviderReader = T Function<T>(ProviderListenable<T> provider);

class LspStubsConfig {
  const LspStubsConfig({
    required this.paths,
    required this.virtualEnvironment,
    required this.initializationOptions,
    required this.workspaceConfiguration,
    required this.environment,
  });

  final List<String> paths;
  final String virtualEnvironment;
  final Map<String, dynamic> initializationOptions;
  final Map<String, dynamic> workspaceConfiguration;
  final Map<String, String> environment;
}

/// Whether the configured language server is Zuban.
///
/// Zuban only speaks stdio, so the executable (and any module-style argument
/// such as `python -m zuban`) is enough to identify it. Detecting the server
/// this way keeps the choice out of the settings UI: the user already
/// selects the server by pointing the stdio executable at it.
bool isZubanLanguageServer({
  required String stdioExecutable,
  required String stdioArgs,
}) {
  final executable = stdioExecutable.trim();
  if (executable.isNotEmpty && _isZubanBinaryName(executable)) return true;
  // Covers wrappers such as `python -m zuban` and `uvx zuban`.
  return stdioArgs.split(RegExp(r'\s+')).any(_isZubanBinaryName);
}

/// Whether [name] is the Zuban binary, either bare or at the end of a path
/// such as `C:/tools/zuban.exe`.
bool _isZubanBinaryName(String name) {
  final base = path.basename(name.trim().toLowerCase());
  return base == 'zuban' || base == 'zuban.exe';
}

LspStubsConfig buildLspStubsConfig(
  LspProviderReader read, {
  String? workspacePath,
}) {
  final stubsEnabled = read(microPythonStubsEnabled);
  final configuredLayers = stubsEnabled
      ? read(microPythonStubsLayers)
            .map(
              (layer) => {'provider': layer.provider, 'profile': layer.profile},
            )
            .toList()
      : const <Map<String, String>>[];
  final resolvedLayers = stubsEnabled
      ? read(dataRegistryProvider).resolveStubsLayers(configuredLayers)
      : const <Map<String, dynamic>>[];
  final paths = <String>{
    for (final layer in resolvedLayers)
      if (layer['path']?.toString().isNotEmpty == true)
        layer['path'].toString(),
    for (final path in read(microPythonStubsExtraPaths))
      if (stubsEnabled && path.trim().isNotEmpty) path.trim(),
  }.toList();
  final virtualEnvironment = resolvePythonVirtualEnvironment(
    configuredVirtualEnvironment: read(lspVirtualEnvironment),
    workspacePath: workspacePath,
  );
  final useWorkspaceDefaultVirtualEnvironment =
      virtualEnvironment != null &&
      isWorkspaceDefaultVirtualEnvironment(
        virtualEnvironment,
        workspacePath: workspacePath,
      );
  final pythonInterpreter = virtualEnvironment?.interpreter.path ?? '';

  // Zuban has no WebSocket transport, so only a stdio launch can be one.
  final isZuban =
      read(lspType) == LspType.stdio &&
      isZubanLanguageServer(
        stdioExecutable: read(lspStdioExecutable),
        stdioArgs: read(lspStdioArgs),
      );

  final existingPythonPath = Platform.environment['PYTHONPATH'];
  final existingMypyPath = Platform.environment['MYPYPATH'];
  final pythonPath = [
    ...paths,
    if (existingPythonPath != null && existingPythonPath.isNotEmpty)
      existingPythonPath,
  ].join(Platform.isWindows ? ';' : ':');

  final jediConfiguration = <String, dynamic>{
    if (paths.isNotEmpty) ...{
      'extra_paths': paths,
      'prioritize_extra_paths': true,
    },
    if (pythonInterpreter.isNotEmpty) 'environment': pythonInterpreter,
  };
  final basedPyrightAnalysis = <String, dynamic>{
    'typeCheckingMode': read(lspBasedPyrightTypeCheckingMode).jsonName,
    if (paths.isNotEmpty) 'extraPaths': paths,
  };
  // Zuban reads one flat options object and has no `pylsp`/`basedpyright`
  // sections, so the sectioned configuration is replaced rather than merged.
  // It also resolves stub paths from MYPYPATH instead of `extraPaths`.
  final languageServerConfiguration = <String, dynamic>{
    if (isZuban) ...{
      'typeCheckingMode': read(lspBasedPyrightTypeCheckingMode).jsonName,
      if (pythonInterpreter.isNotEmpty) 'pythonExecutable': pythonInterpreter,
      // Check the whole workspace so imported stub modules are covered, not
      // only the files the user happens to have open.
      if (stubsEnabled) 'diagnosticMode': 'workspace',
    } else ...{
      if (jediConfiguration.isNotEmpty)
        'pylsp': {
          'plugins': {'jedi': jediConfiguration},
        },
      'basedpyright': {'analysis': basedPyrightAnalysis},
      // Let BasedPyright discover the workspace's .venv with its native
      // handling, preserving virtual-environment paths for uv symlink targets.
      if (virtualEnvironment != null && !useWorkspaceDefaultVirtualEnvironment)
        'python': {
          'venvPath': virtualEnvironment.root.parent.path,
          'venv': path.basename(virtualEnvironment.root.path),
        },
    },
  };

  var environment = <String, String>{...Platform.environment};
  if (virtualEnvironment != null) {
    environment = buildPythonVirtualEnvironmentEnvironment(
      virtualEnvironment,
      baseEnvironment: environment,
    );
  }
  environment.addAll({
    if (stubsEnabled) ...{
      'PYRITE_MICROPYTHON_STUBS_ENABLED': '1',
      'PYRITE_MICROPYTHON_STUBS_PATHS': paths.join(Platform.pathSeparator),
      if (pythonPath.isNotEmpty) 'PYTHONPATH': pythonPath,
      // Zuban resolves stub and search paths from the environment rather than
      // a configuration key, so the layers are also exposed through MYPYPATH.
      if (isZuban && paths.isNotEmpty)
        'MYPYPATH': [
          ...paths,
          if (existingMypyPath != null && existingMypyPath.isNotEmpty)
            existingMypyPath,
        ].join(Platform.pathSeparator),
    },
  });

  return LspStubsConfig(
    paths: paths,
    virtualEnvironment: virtualEnvironment?.root.path ?? '',
    initializationOptions: languageServerConfiguration,
    workspaceConfiguration: languageServerConfiguration,
    environment: environment,
  );
}
