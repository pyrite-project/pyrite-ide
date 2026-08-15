import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/file/file_manager.dart';

void main() {
  test('Windows Explorer selects a file', () {
    final command = fileManagerCommand(
      platform: FileManagerPlatform.windows,
      itemPath: r'C:\workspace\main.py',
      isDirectory: false,
    );

    expect(command?.executable, 'explorer.exe');
    expect(command?.arguments, <String>['/select,', r'C:\workspace\main.py']);
  });

  test('Finder reveals a file', () {
    final command = fileManagerCommand(
      platform: FileManagerPlatform.macos,
      itemPath: '/workspace/main.py',
      isDirectory: false,
    );

    expect(command?.executable, 'open');
    expect(command?.arguments, <String>['-R', '/workspace/main.py']);
  });

  test('Linux opens the directory containing a file', () {
    final command = fileManagerCommand(
      platform: FileManagerPlatform.linux,
      itemPath: '/workspace/src/main.py',
      isDirectory: false,
    );

    expect(command?.executable, 'xdg-open');
    expect(command?.arguments, <String>['/workspace/src']);
  });

  test(
    'Android delegates the containing directory to the file manager',
    () async {
      final openedPaths = <String>[];
      final launcher = FileManagerLauncher(
        platform: FileManagerPlatform.android,
        androidFileManagerOpener: (directoryPath) async {
          openedPaths.add(directoryPath);
          return true;
        },
      );

      await launcher.open(
        '/storage/emulated/0/project/main.py',
        isDirectory: false,
      );

      expect(openedPaths, <String>['/storage/emulated/0/project']);
    },
  );
}
