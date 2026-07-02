import 'dart:async';

import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_config.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/settings.dart';

void refreshOpenLspStubsConfiguration(dynamic ref) {
  final enabled = ref.read(microPythonStubsEnabled);
  final layers = ref.read(microPythonStubsLayers);
  final controllers = ref.read(editorControllerMapProvider).values.toList();
  final stubsConfig = buildLspStubsConfig(ref);
  ref.read(ideOutputLogProvider.notifier).add(
        IdeOutputSource.ide,
        'Stubs refresh requested: enabled=$enabled, '
        'layers=${layers.map((layer) => '${layer.provider}/${layer.profile}').join(', ')}, '
        'paths=${stubsConfig.paths.join(';')}, '
        'openLsp=${controllers.where((controller) => controller.lspConfig != null).length}',
      );
  if (stubsConfig.workspaceConfiguration.isEmpty) {
    ref.read(ideOutputLogProvider.notifier).add(
          IdeOutputSource.ide,
          'Skipped LSP stubs refresh: no resolved stubs paths',
        );
    return;
  }
  for (final controller in controllers) {
    final lspConfig = controller.lspConfig;
    if (lspConfig == null || !lspConfig.isInitialized) {
      continue;
    }
    ref.read(ideOutputLogProvider.notifier).add(
          IdeOutputSource.ide,
          'Refreshing LSP stubs paths: ${stubsConfig.paths.join(';')}',
        );
    unawaited(
      lspConfig.sendNotification(
        method: 'workspace/didChangeConfiguration',
        params: {'settings': stubsConfig.workspaceConfiguration},
      ),
    );
  }
}
