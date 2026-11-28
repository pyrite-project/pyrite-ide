import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/features/edit_core/lsp_location_dialog.dart';

void main() {
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
      expect(entry.path, _localPath('/w:/work/main.py', r'W:\work\main.py'));
    });

    test('reads an implementation-style location map', () {
      final entry = LspLocationEntry.fromLspMap({
        'targetUri': 'file:///w:/work/impl.py',
        'targetSelectionRange': {
          'start': {'line': 0, 'character': 0},
        },
      });
      expect(entry, isNotNull);
      expect(entry!.path, _localPath('/w:/work/impl.py', r'W:\work\impl.py'));
    });

    test('canonicalizes the drive letter of a lowercase-drive URI', () {
      final entry = LspLocationEntry.fromLspMap({
        'uri': 'file:///w%3A/work/main.py',
        'range': {
          'start': {'line': 1, 'character': 2},
        },
      });
      expect(entry, isNotNull);
      if (path.Style.platform == path.Style.windows) {
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

/// The path a `file:///w:/...` URI resolves to on this platform: a drive path
/// on Windows, a plain absolute path everywhere else.
String _localPath(String posix, String windows) =>
    path.Style.platform == path.Style.windows ? windows : posix;
