import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_config.dart';
import 'package:pyrite_ide/core/services/settings.dart';

void main() {
  test('maps MicroPython stub paths for pylsp and basedpyright', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(dataRegistryProvider)
        .registerStubsProvider(
          const StubsProviderEntry(
            pluginId: 'stubs-fixture',
            providerId: 'micropython',
            kind: 'micropython',
            version: '1.0.0',
            profiles: [StubsProfileEntry(id: 'rp2', path: '/stubs/rp2')],
          ),
        );
    container.read(microPythonStubsEnabled.notifier).state = true;
    container.read(microPythonStubsLayers.notifier).state = const [
      MicroPythonStubsLayer(provider: 'micropython', profile: 'rp2'),
    ];
    container.read(microPythonStubsExtraPaths.notifier).state = const [
      '/stubs/shared',
    ];

    final config = container.read(Provider((ref) => buildLspStubsConfig(ref)));
    final pylsp =
        config.workspaceConfiguration['pylsp'] as Map<String, dynamic>;
    final basedpyright =
        config.workspaceConfiguration['basedpyright'] as Map<String, dynamic>;

    expect(config.paths, ['/stubs/rp2', '/stubs/shared']);
    expect((pylsp['plugins'] as Map<String, dynamic>)['jedi'], {
      'extra_paths': config.paths,
      'prioritize_extra_paths': true,
    });
    expect(basedpyright['analysis'], {'extraPaths': config.paths});
    expect(config.initializationOptions, config.workspaceConfiguration);
  });
}
