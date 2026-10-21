import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/features/edit_core/lsp_location_dialog.dart';

/// LSP 服务端返回的 `file:` URI 经 `Uri.toFilePath()` 落地后，拼写取决于
/// **运行平台**，而不是 URI 本身写了什么：
///
/// * Windows 上 `file:///w:/work/main.py` → `w:\work\main.py`，再经
///   `canonicalLocalPath` 把盘符大写；
/// * POSIX 上同一 URI 的 authority 为空、path 是 `/w:/work/main.py`，
///   于是得到 `/w:/work/main.py`。
///
/// 旧断言直接拿 `canonicalLocalPath(r'w:\work\main.py')` 当期望值，在
/// POSIX 宿主上 `path.posix.normalize` 不会把反斜杠当分隔符，期望值仍是
/// `w:\work\main.py`，与真实（且正确的）`/w:/work/...` 不符。这里按平台
/// 分支给出各自平台的正确期望，两个分支都是生产代码的既有行为。
void main() {
  final isWindows = path.Style.platform == path.Style.windows;

  group('LspLocationEntry.fromLspMap', () {
    test('reads a definition-style location map', () {
      final entry = LspLocationEntry.fromLspMap({
        'uri': 'file:///w:/work/main.py',
        'range': {
          'start': {'line': 3, 'character': 7},
        },
      });
      expect(entry, isNotNull);
      expect(entry!.line, 3);
      expect(entry.character, 7);
      expect(entry.path, isWindows ? r'W:\work\main.py' : '/w:/work/main.py');
    });

    test('reads an implementation-style location map', () {
      final entry = LspLocationEntry.fromLspMap({
        'targetUri': 'file:///w:/work/impl.py',
        'targetSelectionRange': {
          'start': {'line': 0, 'character': 0},
        },
      });
      expect(entry, isNotNull);
      expect(entry!.path, isWindows ? r'W:\work\impl.py' : '/w:/work/impl.py');
    });

    test('canonicalizes the drive letter of a lowercase-drive URI', () {
      final entry = LspLocationEntry.fromLspMap({
        'uri': 'file:///w%3A/work/main.py',
        'range': {
          'start': {'line': 1, 'character': 2},
        },
      });
      expect(entry, isNotNull);
      if (isWindows) {
        expect(entry!.path, r'W:\work\main.py');
      } else {
        expect(entry!.path, '/w:/work/main.py');
      }
    });

    test('returns null for non-file URIs', () {
      expect(
        LspLocationEntry.fromLspMap({'uri': 'untitled:Untitled-1'}),
        isNull,
      );
      expect(
        LspLocationEntry.fromLspMap({'uri': 'https://example.com/a.py'}),
        isNull,
      );
    });
  });
}
