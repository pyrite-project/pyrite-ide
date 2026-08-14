import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/editor/python_virtual_environment.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_config.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_refresh.dart';
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

    final config = container.read(
      Provider((ref) => buildLspStubsConfig(ref.read)),
    );
    final pylsp =
        config.workspaceConfiguration['pylsp'] as Map<String, dynamic>;
    final basedpyright =
        config.workspaceConfiguration['basedpyright'] as Map<String, dynamic>;

    expect(config.paths, ['/stubs/rp2', '/stubs/shared']);
    expect((pylsp['plugins'] as Map<String, dynamic>)['jedi'], {
      'extra_paths': config.paths,
      'prioritize_extra_paths': true,
    });
    expect(basedpyright['analysis'], {
      'typeCheckingMode': 'standard',
      'extraPaths': config.paths,
    });
    expect(config.initializationOptions, config.workspaceConfiguration);
  });

  test(
    'maps the selected virtual environment for basedpyright without stubs',
    () {
      final root = Directory.systemTemp.createTempSync('pyrite-venv-');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}${Platform.pathSeparator}pyvenv.cfg').createSync();
      final scriptsDirectoryName = Platform.isWindows ? 'Scripts' : 'bin';
      final executableName = Platform.isWindows ? 'python.exe' : 'python';
      final scripts = Directory(
        '${root.path}${Platform.pathSeparator}$scriptsDirectoryName',
      )..createSync();
      final interpreter = File(
        '${scripts.path}${Platform.pathSeparator}$executableName',
      )..createSync();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(lspVirtualEnvironment.notifier).state = root.path;

      final config = container.read(
        Provider((ref) => buildLspStubsConfig(ref.read)),
      );

      expect(config.paths, isEmpty);
      expect(config.virtualEnvironment, root.path);
      expect(config.workspaceConfiguration, {
        'pylsp': {
          'plugins': {
            'jedi': {'environment': interpreter.path},
          },
        },
        'basedpyright': {
          'analysis': {'typeCheckingMode': 'standard'},
        },
        'python': {
          'venvPath': root.parent.path,
          'venv': root.path.split(Platform.pathSeparator).last,
        },
      });
      final pathSeparator = Platform.isWindows ? ';' : ':';
      final environmentPath = config.environment.entries
          .firstWhere((entry) => entry.key.toLowerCase() == 'path')
          .value;
      expect(environmentPath, startsWith('${scripts.path}$pathSeparator'));
      expect(config.environment['VIRTUAL_ENV'], root.path);
    },
  );

  test('configures the default BasedPyright type checking mode', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final config = container.read(
      Provider((ref) => buildLspStubsConfig(ref.read)),
    );

    expect(config.workspaceConfiguration, {
      'basedpyright': {
        'analysis': {'typeCheckingMode': 'standard'},
      },
    });
  });

  test('configures the selected BasedPyright type checking mode', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(lspBasedPyrightTypeCheckingMode.notifier).state =
        BasedPyrightTypeCheckingMode.strict;

    final config = container.read(
      Provider((ref) => buildLspStubsConfig(ref.read)),
    );

    expect(config.workspaceConfiguration['basedpyright'], {
      'analysis': {'typeCheckingMode': 'strict'},
    });
  });

  test('does not discover a virtual environment above the workspace root', () {
    final root = Directory.systemTemp.createTempSync('pyrite-workspace-');
    addTearDown(() => root.deleteSync(recursive: true));
    final workspace = Directory('${root.path}${Platform.pathSeparator}child')
      ..createSync();
    final venvDirectory = Directory(
      '${root.path}${Platform.pathSeparator}.venv',
    )..createSync();
    File(
      '${venvDirectory.path}${Platform.pathSeparator}pyvenv.cfg',
    ).createSync();
    final scriptsDirectoryName = Platform.isWindows ? 'Scripts' : 'bin';
    final executableName = Platform.isWindows ? 'python.exe' : 'python';
    final scripts = Directory(
      '${venvDirectory.path}${Platform.pathSeparator}$scriptsDirectoryName',
    )..createSync();
    File(
      '${scripts.path}${Platform.pathSeparator}$executableName',
    ).createSync();

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final config = container.read(
      Provider(
        (ref) => buildLspStubsConfig(ref.read, workspacePath: workspace.path),
      ),
    );

    expect(config.virtualEnvironment, isEmpty);
    expect(config.workspaceConfiguration, {
      'basedpyright': {
        'analysis': {'typeCheckingMode': 'standard'},
      },
    });
  });

  test(
    'lets BasedPyright discover a symlinked workspace .venv',
    () {
      final root = Directory.systemTemp.createTempSync('pyrite-workspace-');
      addTearDown(() => root.deleteSync(recursive: true));
      final workspace = Directory(
        '${root.path}${Platform.pathSeparator}project',
      )..createSync();
      final venvDirectory = Directory(
        '${workspace.path}${Platform.pathSeparator}.venv',
      )..createSync();
      File(
        '${venvDirectory.path}${Platform.pathSeparator}pyvenv.cfg',
      ).createSync();
      final scriptsDirectoryName = Platform.isWindows ? 'Scripts' : 'bin';
      final executableName = Platform.isWindows ? 'python.exe' : 'python';
      final scripts = Directory(
        '${venvDirectory.path}${Platform.pathSeparator}$scriptsDirectoryName',
      )..createSync();
      final target = File('${root.path}${Platform.pathSeparator}python-target')
        ..createSync();
      final interpreterPath =
          '${scripts.path}${Platform.pathSeparator}$executableName';
      Link(interpreterPath).createSync(target.path);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final config = container.read(
        Provider(
          (ref) => buildLspStubsConfig(ref.read, workspacePath: workspace.path),
        ),
      );

      expect(config.virtualEnvironment, venvDirectory.path);
      expect(config.environment['VIRTUAL_ENV'], venvDirectory.path);
      expect(config.workspaceConfiguration.containsKey('python'), isFalse);
    },
    skip: Platform.isWindows
        ? 'Windows symlinks need elevated privileges'
        : false,
  );

  test('activates a detected virtual environment for launched processes', () {
    final root = Directory.systemTemp.createTempSync('pyrite-venv-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}${Platform.pathSeparator}pyvenv.cfg').createSync();
    final scriptsDirectoryName = Platform.isWindows ? 'Scripts' : 'bin';
    final executableName = Platform.isWindows ? 'python.exe' : 'python';
    final scripts = Directory(
      '${root.path}${Platform.pathSeparator}$scriptsDirectoryName',
    )..createSync();
    File(
      '${scripts.path}${Platform.pathSeparator}$executableName',
    ).createSync();

    final virtualEnvironment = resolvePythonVirtualEnvironment(
      configuredVirtualEnvironment: root.path,
    );

    final environment = buildPythonVirtualEnvironmentEnvironment(
      virtualEnvironment!,
      baseEnvironment: const {'PATH': '/usr/bin', 'PYTHONHOME': '/system'},
    );

    expect(environment['VIRTUAL_ENV'], root.path);
    final pathSeparator = Platform.isWindows ? ';' : ':';
    expect(environment['PATH'], '${scripts.path}$pathSeparator/usr/bin');
    expect(environment['PYTHONHOME'], isEmpty);
  });

  test('does not override a workspace .venv selected with a relative path', () {
    final root = Directory.systemTemp.createTempSync('pyrite-workspace-');
    addTearDown(() => root.deleteSync(recursive: true));
    final venvDirectory = Directory(
      '${root.path}${Platform.pathSeparator}.venv',
    )..createSync();
    File(
      '${venvDirectory.path}${Platform.pathSeparator}pyvenv.cfg',
    ).createSync();
    final scriptsDirectoryName = Platform.isWindows ? 'Scripts' : 'bin';
    final executableName = Platform.isWindows ? 'python.exe' : 'python';
    final scripts = Directory(
      '${venvDirectory.path}${Platform.pathSeparator}$scriptsDirectoryName',
    )..createSync();
    File(
      '${scripts.path}${Platform.pathSeparator}$executableName',
    ).createSync();

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(lspVirtualEnvironment.notifier).state = '.venv';

    final config = container.read(
      Provider(
        (ref) => buildLspStubsConfig(ref.read, workspacePath: root.path),
      ),
    );

    expect(config.virtualEnvironment, venvDirectory.path);
    expect(config.workspaceConfiguration.containsKey('python'), isFalse);
  });

  testWidgets('refreshes open LSP configuration from a WidgetRef', (
    tester,
  ) async {
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, widgetRef, child) {
            ref = widgetRef;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(() => refreshOpenLspConfiguration(ref.read), returnsNormally);
  });
}
