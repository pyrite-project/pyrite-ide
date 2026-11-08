import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/serial/device_run_directory.dart';

void main() {
  group('device-side files', () {
    test('use their own parent directory', () {
      expect(
        resolveDeviceRunWorkingDirectory(
          isBoardFile: true,
          boardFilePath: '/apps/demo/main.py',
        ),
        '/apps/demo',
      );
    });

    test('at the device root keep the current directory', () {
      expect(
        resolveDeviceRunWorkingDirectory(
          isBoardFile: true,
          boardFilePath: '/main.py',
        ),
        isNull,
      );
    });

    test('without a leading slash still resolve', () {
      expect(
        resolveDeviceRunWorkingDirectory(
          isBoardFile: true,
          boardFilePath: 'lib/main.py',
        ),
        '/lib',
      );
    });
  });

  group('workspace files', () {
    test('map their workspace-relative directory onto the device root', () {
      expect(
        resolveDeviceRunWorkingDirectory(
          isBoardFile: false,
          localFilePath: '/home/user/proj/lib/main.py',
          workspaceRootPath: '/home/user/proj',
        ),
        '/lib',
      );
    });

    test('map host-style paths onto POSIX device directories', () {
      // Built with the host context so the assertion holds on Windows (the
      // IDE's primary target) and POSIX hosts alike; the device side is
      // always POSIX.
      final root = p.join(
        p.separator == '\\' ? r'C:' : '/home',
        'user',
        'proj',
      );
      final file = p.join(root, 'lib', 'main.py');
      expect(
        resolveDeviceRunWorkingDirectory(
          isBoardFile: false,
          localFilePath: file,
          workspaceRootPath: root,
        ),
        '/lib',
      );
    });

    test('at the workspace root need no switch', () {
      expect(
        resolveDeviceRunWorkingDirectory(
          isBoardFile: false,
          localFilePath: '/home/user/proj/main.py',
          workspaceRootPath: '/home/user/proj',
        ),
        isNull,
      );
    });

    test('outside the workspace resolve to nothing', () {
      expect(
        resolveDeviceRunWorkingDirectory(
          isBoardFile: false,
          localFilePath: '/elsewhere/main.py',
          workspaceRootPath: '/home/user/proj',
        ),
        isNull,
      );
    });

    test('without an open workspace resolve to nothing', () {
      expect(
        resolveDeviceRunWorkingDirectory(
          isBoardFile: false,
          localFilePath: '/home/user/proj/main.py',
          workspaceRootPath: null,
        ),
        isNull,
      );
    });
  });

  test('a tab without a file resolves to nothing', () {
    expect(resolveDeviceRunWorkingDirectory(), isNull);
  });
}
