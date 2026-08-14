import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/python_virtual_environment.dart';

void main() {
  test(
    'discovers a symlinked workspace .venv without resolving the link',
    () {
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
      final target = File('${root.path}${Platform.pathSeparator}python-target')
        ..createSync();
      final interpreterPath =
          '${scripts.path}${Platform.pathSeparator}$executableName';
      Link(interpreterPath).createSync(target.path);

      final virtualEnvironment = resolvePythonVirtualEnvironment(
        configuredVirtualEnvironment: '',
        workspacePath: root.path,
      );

      expect(virtualEnvironment, isNotNull);
      expect(virtualEnvironment!.root.path, venvDirectory.path);
      expect(virtualEnvironment.interpreter.path, interpreterPath);
      expect(
        isWorkspaceDefaultVirtualEnvironment(
          virtualEnvironment,
          workspacePath: root.path,
        ),
        isTrue,
      );
    },
    skip: Platform.isWindows
        ? 'Windows symlinks need elevated privileges'
        : false,
  );

  test('resolves a selected virtual environment relative to the workspace', () {
    final workspace = Directory.systemTemp.createTempSync('pyrite-workspace-');
    addTearDown(() => workspace.deleteSync(recursive: true));
    final venvDirectory = Directory(
      '${workspace.path}${Platform.pathSeparator}env',
    )..createSync();
    File(
      '${venvDirectory.path}${Platform.pathSeparator}pyvenv.cfg',
    ).createSync();
    final scriptsDirectoryName = Platform.isWindows ? 'Scripts' : 'bin';
    final executableName = Platform.isWindows ? 'python.exe' : 'python';
    final scripts = Directory(
      '${venvDirectory.path}${Platform.pathSeparator}$scriptsDirectoryName',
    )..createSync();
    final interpreter = File(
      '${scripts.path}${Platform.pathSeparator}$executableName',
    )..createSync();

    final virtualEnvironment = resolvePythonVirtualEnvironment(
      configuredVirtualEnvironment: 'env',
      workspacePath: workspace.path,
    );

    expect(virtualEnvironment!.root.path, venvDirectory.path);
    expect(virtualEnvironment.interpreter.path, interpreter.path);
  });

  test(
    'does not fall back to .venv when the selected directory is invalid',
    () {
      final workspace = Directory.systemTemp.createTempSync(
        'pyrite-workspace-',
      );
      addTearDown(() => workspace.deleteSync(recursive: true));

      expect(
        resolvePythonVirtualEnvironment(
          configuredVirtualEnvironment: 'missing-environment',
          workspacePath: workspace.path,
        ),
        isNull,
      );
    },
  );
}
