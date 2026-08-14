import 'dart:async';

import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_config.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/settings.dart';

void refreshOpenLspConfiguration(LspProviderReader read) {
  final enabled = read(microPythonStubsEnabled);
  final layers = read(microPythonStubsLayers);
  final controllers = read(editorControllerMapProvider).values.toList();
  read(ideOutputLogProvider.notifier).add(
    IdeOutputSource.ide,
    'LSP configuration refresh requested: stubsEnabled=$enabled, '
    'layers=${layers.map((layer) => '${layer.provider}/${layer.profile}').join(', ')}, '
    'openLsp=${controllers.where((controller) => controller.lspConfig != null).length}',
  );
  for (final controller in controllers) {
    final lspConfig = controller.lspConfig;
    if (lspConfig == null || !lspConfig.isInitialized) {
      continue;
    }
    final stubsConfig = buildLspStubsConfig(
      read,
      workspacePath: lspConfig.workspacePath,
    );
    lspConfig.updateWorkspaceConfiguration(stubsConfig.workspaceConfiguration);
    read(ideOutputLogProvider.notifier).add(
      IdeOutputSource.ide,
      'Refreshing LSP configuration: stubs=${stubsConfig.paths.join(';')}, '
      'virtualEnvironment=${stubsConfig.virtualEnvironment}',
    );
    unawaited(
      lspConfig.sendNotification(
        method: 'workspace/didChangeConfiguration',
        params: {'settings': stubsConfig.workspaceConfiguration},
      ),
    );
  }
}

void refreshOpenLspStubsConfiguration(LspProviderReader read) {
  refreshOpenLspConfiguration(read);
}
