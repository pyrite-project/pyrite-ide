import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/file/file_rename.dart';

void main() {
  test('rebases every descendant of a renamed local folder', () {
    final oldRoot = path.join('workspace', 'source');
    final newRoot = path.join('workspace', 'renamed');
    expect(
      rebaseLocalPath(
        path.join(oldRoot, 'lib', 'main.py'),
        oldRoot: oldRoot,
        newRoot: newRoot,
      ),
      path.join(newRoot, 'lib', 'main.py'),
    );
    expect(
      rebaseLocalPath(
        path.join('workspace', 'source-not-renamed', 'main.py'),
        oldRoot: oldRoot,
        newRoot: newRoot,
      ),
      isNull,
    );
  });

  test('rebases board paths using POSIX separators', () {
    expect(
      rebaseBoardPath('/lib/main.py', oldRoot: '/lib', newRoot: '/src'),
      '/src/main.py',
    );
    expect(
      rebaseBoardPath('/library/main.py', oldRoot: '/lib', newRoot: '/src'),
      isNull,
    );
  });

  test('maps a board tab cache path to its renamed remote path', () {
    final cacheRoot = path.join('cache', 'temporary_board_files');
    expect(
      rebaseBoardCachePath(
        oldCachePath: path.join(cacheRoot, 'lib', 'main.py'),
        oldBoardPath: '/lib/main.py',
        newBoardPath: '/src/main.py',
      ),
      path.join(cacheRoot, 'src', 'main.py'),
    );
  });
}
