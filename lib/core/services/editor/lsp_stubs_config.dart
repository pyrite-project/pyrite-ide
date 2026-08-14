import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
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

  final existingPythonPath = Platform.environment['PYTHONPATH'];
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
  final languageServerConfiguration = <String, dynamic>{
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
