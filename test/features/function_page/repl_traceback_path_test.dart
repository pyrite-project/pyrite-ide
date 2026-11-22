import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/file/board_backend.dart';
import 'package:pyrite_ide/features/function_page/repl_surface.dart';

void main() {
  group('boardPathForTracebackFile', () {
    test('keeps an absolute device path at a single leading slash', () {
      expect(boardPathForTracebackFile('/lib/x.py'), '/lib/x.py');
    });

    test('collapses repeated leading slashes', () {
      expect(boardPathForTracebackFile('//lib/x.py'), '/lib/x.py');
      expect(boardPathForTracebackFile('///lib/x.py'), '/lib/x.py');
    });

    test('roots a relative path without changing its segments', () {
      expect(boardPathForTracebackFile('main.py'), '/main.py');
      expect(boardPathForTracebackFile('lib/x.py'), '/lib/x.py');
      expect(boardPathForTracebackFile('./lib/x.py'), '/lib/x.py');
    });

    test('resolves dot segments against the device root', () {
      expect(boardPathForTracebackFile('../lib/x.py'), '/lib/x.py');
      expect(boardPathForTracebackFile('/lib/../main.py'), '/main.py');
    });

    test('treats backslashes as device separators', () {
      expect(boardPathForTracebackFile(r'\lib\x.py'), '/lib/x.py');
      expect(boardPathForTracebackFile(r'lib\x.py'), '/lib/x.py');
    });

    test('maps the device root itself to a single slash', () {
      expect(boardPathForTracebackFile('/'), '/');
      expect(boardPathForTracebackFile(''), '/');
    });
  });

  group('traceback path in the local mirror', () {
    const mirrorRoot = '/support/temporary_board_files';

    test('mirrors an absolute traceback path inside the mirror root', () {
      final boardPath = boardPathForTracebackFile('/lib/x.py');
      final relative = boardMirrorRelativePath(boardPath);
      final mirrored = path.posix.join(mirrorRoot, relative);

      expect(relative, 'lib/x.py');
      expect(mirrored, '$mirrorRoot/lib/x.py');
      // A leading separator would make path.join treat the relative part as a
      // new root, so the mirror would write outside its own directory.
      expect(path.posix.isWithin(mirrorRoot, mirrored), isTrue);
    });

    test('normalises a doubled-slash path before mirroring it', () {
      final relative = boardMirrorRelativePath('//lib/x.py');
      final mirrored = path.posix.join(mirrorRoot, relative);

      expect(relative, 'lib/x.py');
      expect(mirrored, '$mirrorRoot/lib/x.py');
      expect(path.posix.isWithin(mirrorRoot, mirrored), isTrue);
    });

    test('a dot segment cannot climb out of the mirror root', () {
      final relative = boardMirrorRelativePath('../lib/x.py');
      final mirrored = path.posix.join(mirrorRoot, relative);

      expect(relative, 'lib/x.py');
      expect(path.posix.isWithin(mirrorRoot, mirrored), isTrue);
    });
  });
}
