import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';

void main() {
  test('builds board upload target from Windows local folder path', () {
    final targetPath = buildBoardUploadTargetPath(
      sourcePath: r'E:\Can1425\xterm.dart\media',
      boardFolderPath: '/media',
    );

    expect(targetPath, '/media/media');
  });

  test('defaults board upload target to the board root', () {
    final targetPath = buildBoardUploadTargetPath(
      sourcePath: r'E:\Can1425\xterm.dart\media',
      boardFolderPath: null,
    );

    expect(targetPath, '/media');
  });

  test('uses POSIX separators for board upload targets', () {
    final targetPath = buildBoardUploadTargetPath(
      sourcePath: '/Users/example/project/demo-dialog.png',
      boardFolderPath: '/',
    );

    expect(targetPath, '/demo-dialog.png');
  });
}
