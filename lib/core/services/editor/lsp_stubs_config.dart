import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_context.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_profile.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_registry.dart';
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
    if (stubsEnabled)
      for (final path in read(microPythonStubsExtraPaths))
        if (path.trim().isNotEmpty) path.trim(),
  }.toList();
  final virtualEnvironment = resolvePythonVirtualEnvironment(
    configuredVirtualEnvironment: read(lspVirtualEnvironment),
    workspacePath: workspacePath,
  );
  final pythonInterpreter = virtualEnvironment?.interpreter.path ?? '';

  final context = LspServerContext(
    transport: read(lspType),
    stdioExecutable: read(lspStdioExecutable),
    stdioArgs: read(lspStdioArgs),
    stubsEnabled: stubsEnabled,
    stubsPaths: paths,
    pythonInterpreter: pythonInterpreter,
    typeCheckingMode: read(lspBasedPyrightTypeCheckingMode),
    virtualEnvironment: virtualEnvironment,
    workspacePath: workspacePath ?? '',
  );
  final adapter = LspServerRegistry(
    contributed: [
      for (final entry in read(dataRegistryProvider).allLspServers)
        LspServerProfileAdapter(entry),
    ],
  ).resolve(context);

  final existingPythonPath = Platform.environment['PYTHONPATH'];
  final pythonPath = [
    ...paths,
    if (existingPythonPath != null && existingPythonPath.isNotEmpty)
      existingPythonPath,
  ].join(Platform.isWindows ? ';' : ':');

  final languageServerConfiguration = adapter.buildConfiguration(context);

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
  environment.addAll(adapter.buildEnvironment(context, environment));

  return LspStubsConfig(
    paths: paths,
    virtualEnvironment: virtualEnvironment?.root.path ?? '',
    initializationOptions: languageServerConfiguration,
    workspaceConfiguration: languageServerConfiguration,
    environment: environment,
  );
}
