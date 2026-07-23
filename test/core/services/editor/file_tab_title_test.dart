import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/file_tab_title.dart';
import 'package:tabbed_view/tabbed_view.dart';

void main() {
  test('uses the basename when file names are unique', () {
    expect(
      buildFileTabTitles([
        '/workspace/src/main.dart',
        '/workspace/src/app.dart',
      ]),
      ['main.dart', 'app.dart'],
    );
  });

  test('uses the shortest distinguishing parent for duplicate names', () {
    expect(
      buildFileTabTitles([
        '/workspace/client/main.dart',
        '/workspace/server/main.dart',
      ]),
      ['client/main.dart', 'server/main.dart'],
    );
  });

  test('expands only duplicate suffixes when more context is needed', () {
    expect(
      buildFileTabTitles([
        '/workspace/client/src/main.dart',
        '/workspace/server/src/main.dart',
        '/workspace/server/test/main.dart',
      ]),
      ['client/src/main.dart', 'server/src/main.dart', 'test/main.dart'],
    );
  });

  test('treats Windows and POSIX separators as path separators', () {
    expect(
      buildFileTabTitles([
        r'C:\workspace\client\main.py',
        'D:/workspace/server/main.py',
      ]),
      ['client/main.py', 'server/main.py'],
    );
  });

  test('includes drive or root information only when required', () {
    expect(buildFileTabTitles([r'C:\src\main.py', r'D:\src\main.py']), [
      'C:/src/main.py',
      'D:/src/main.py',
    ]);
    expect(buildFileTabTitles(['/src/main.py', 'src/main.py']), [
      '/src/main.py',
      'src/main.py',
    ]);
  });

  test('distinguishes UNC roots when the remaining path is identical', () {
    expect(
      buildFileTabTitles([
        r'\\server-a\share\src\main.py',
        r'\\server-b\share\src\main.py',
      ]),
      ['server-a/share/src/main.py', 'server-b/share/src/main.py'],
    );
  });

  test('stops at the full path when duplicate inputs are identical', () {
    expect(buildFileTabTitles(['/src/main.py', '/src/main.py']), [
      '/src/main.py',
      '/src/main.py',
    ]);
  });

  test('returns to the basename after a duplicate path is removed', () {
    final paths = ['/workspace/client/main.py', '/workspace/server/main.py'];

    expect(buildFileTabTitles(paths), ['client/main.py', 'server/main.py']);
    expect(buildFileTabTitles([paths.first]), ['main.py']);
  });

  test('updates file tabs using logical board paths and leaves other tabs', () {
    final localTab = TabData(
      text: 'main.py',
      value: TabDataValue(type: 'file', filePath: r'C:\workspace\src\main.py'),
    );
    final boardTab = TabData(
      text: 'main.py',
      value: TabDataValue(
        type: 'file',
        filePath: r'C:\cache\unrelated\main.py',
        isBoardFile: true,
        boardFilePath: '/device/lib/main.py',
      ),
    );
    final diffTab = TabData(
      text: 'main.py - staged',
      value: TabDataValue(type: 'git_diff', filePath: 'git-diff:main.py'),
    );
    final tabs = [localTab, boardTab, diffTab];

    refreshFileTabTitles(tabs);

    expect(localTab.text, 'src/main.py');
    expect(boardTab.text, 'lib/main.py');
    expect(diffTab.text, 'main.py - staged');

    tabs.remove(boardTab);
    refreshFileTabTitles(tabs);
    expect(localTab.text, 'main.py');
  });
}
