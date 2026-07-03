import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/settings.dart';

class LspStubsConfig {
  const LspStubsConfig({
    required this.paths,
    required this.initializationOptions,
    required this.workspaceConfiguration,
    required this.environment,
  });

  final List<String> paths;
  final Map<String, dynamic> initializationOptions;
  final Map<String, dynamic> workspaceConfiguration;
  final Map<String, String> environment;
}

LspStubsConfig buildLspStubsConfig(Ref ref) {
  if (!ref.read(microPythonStubsEnabled)) {
    return const LspStubsConfig(
      paths: [],
      initializationOptions: {},
      workspaceConfiguration: {},
      environment: {},
    );
  }

  final configuredLayers = ref
      .read(microPythonStubsLayers)
      .map((layer) => {'provider': layer.provider, 'profile': layer.profile})
      .toList();
  final resolvedLayers = ref
      .read(dataRegistryProvider)
      .resolveStubsLayers(configuredLayers);
  final paths = <String>{
    for (final layer in resolvedLayers)
      if (layer['path']?.toString().isNotEmpty == true) layer['path'].toString(),
    for (final path in ref.read(microPythonStubsExtraPaths))
      if (path.trim().isNotEmpty) path.trim(),
  }.toList();

  if (paths.isEmpty && resolvedLayers.isEmpty) {
    return const LspStubsConfig(
      paths: [],
      initializationOptions: {},
      workspaceConfiguration: {},
      environment: {},
    );
  }

  final existingPythonPath = Platform.environment['PYTHONPATH'];
  final pythonPath = [
    ...paths,
    if (existingPythonPath != null && existingPythonPath.isNotEmpty)
      existingPythonPath,
  ].join(Platform.isWindows ? ';' : ':');

  final pylspConfiguration = {
    'pylsp': {
      'plugins': {
        'jedi': {
          'extra_paths': paths,
          'prioritize_extra_paths': true,
        },
      },
    },
  };

  return LspStubsConfig(
    paths: paths,
    initializationOptions: pylspConfiguration,
    workspaceConfiguration: pylspConfiguration,
    environment: {
      'PYRITE_MICROPYTHON_STUBS_ENABLED': '1',
      'PYRITE_MICROPYTHON_STUBS_PATHS': paths.join(Platform.pathSeparator),
      if (pythonPath.isNotEmpty) 'PYTHONPATH': pythonPath,
    },
  );
}
