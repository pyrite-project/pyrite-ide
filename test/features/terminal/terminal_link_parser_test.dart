import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/terminal/terminal_link_parser.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('parseTerminalLinks: URLs', () {
    test('finds an http and an https URL with their spans', () {
      const text = 'see http://a.dev/x and https://b.dev/y?z=1 done';
      final links = parseTerminalLinks(text);

      expect(links.map((link) => link.url), [
        'http://a.dev/x',
        'https://b.dev/y?z=1',
      ]);
      for (final link in links) {
        expect(link.kind, TerminalLinkKind.url);
        expect(text.substring(link.start, link.end), link.url);
      }
    });

    test('drops sentence punctuation the URL does not own', () {
      final links = parseTerminalLinks('done: https://example.com/a. Next.');

      expect(links.single.url, 'https://example.com/a');
    });

    test('keeps a balanced parenthesis but drops an unbalanced one', () {
      expect(
        parseTerminalLinks('(https://e.dev/wiki/Foo_(bar))').single.url,
        'https://e.dev/wiki/Foo_(bar)',
      );
      expect(
        parseTerminalLinks('see https://e.dev/x)').single.url,
        'https://e.dev/x',
      );
    });

    test('a port is not re-read as a file reference', () {
      final links = parseTerminalLinks('open http://localhost:8080/index.html');

      expect(links, hasLength(1));
      expect(links.single.kind, TerminalLinkKind.url);
      expect(links.single.url, 'http://localhost:8080/index.html');
    });

    test('is case insensitive about the scheme', () {
      expect(parseTerminalLinks('HTTPS://E.DEV').single.url, 'HTTPS://E.DEV');
    });

    test('ignores a bare scheme with no host', () {
      expect(parseTerminalLinks('https:// only'), isEmpty);
    });
  });

  group('parseTerminalLinks: file references', () {
    test('finds path:line with its span', () {
      const text = 'error in src/app/main.py:42:7 here';
      final link = parseTerminalLinks(text).single;

      expect(link.kind, TerminalLinkKind.file);
      expect(link.path, 'src/app/main.py');
      expect(link.line, 42);
      expect(link.column, 7);
      expect(text.substring(link.start, link.end), 'src/app/main.py:42:7');
    });

    test('finds a bare file name with only a line', () {
      final link = parseTerminalLinks('main.py:12').single;

      expect(link.path, 'main.py');
      expect(link.line, 12);
      expect(link.column, isNull);
    });

    test('finds a Windows absolute path and keeps the drive colon', () {
      final link = parseTerminalLinks(r'at C:\proj\src\main.py:9:2').single;

      expect(link.path, r'C:\proj\src\main.py');
      expect(link.line, 9);
      expect(link.column, 2);
    });

    test('finds a Python traceback frame as a file reference', () {
      const text = '  File "main.py", line 12, in handler';
      final link = parseTerminalLinks(text).single;

      expect(link.path, 'main.py');
      expect(link.line, 12);
      expect(text.substring(link.start, link.end), 'File "main.py", line 12');
    });

    test('rejects timestamps and decimal numbers', () {
      expect(parseTerminalLinks('finished in 12.30:45'), isEmpty);
      expect(parseTerminalLinks('count: 10'), isEmpty);
    });

    test('accepts a path without a dot when it has a separator', () {
      final link = parseTerminalLinks('bin/tool:3').single;

      expect(link.path, 'bin/tool');
      expect(link.line, 3);
    });

    test('sorts links by position when both kinds appear', () {
      const text = 'main.py:3 then https://e.dev';
      final links = parseTerminalLinks(text);

      expect(links.map((link) => link.kind), [
        TerminalLinkKind.file,
        TerminalLinkKind.url,
      ]);
      expect(links.first.start, lessThan(links.last.start));
    });
  });

  group('terminalLinkAtCell', () {
    test('returns the link covering the clicked column', () {
      final links = parseTerminalLinks('run main.py:7 now');
      final link = terminalLinkAtCell(links, 5);

      expect(link?.path, 'main.py');
      expect(terminalLinkAtCell(links, 0), isNull);
    });

    test('treats the end column as outside the link', () {
      final links = parseTerminalLinks('main.py:7');

      // 'main.py:7' spans columns 0..8, so 8 is the last clickable cell and
      // one past it is plain output.
      expect(terminalLinkAtCell(links, 8)?.line, 7);
      expect(terminalLinkAtCell(links, 9), isNull);
    });
  });

  group('terminalLineCellText', () {
    test('renders one character per cell', () {
      final terminal = Terminal()..resize(10, 2);
      terminal.write('ab');

      expect(terminalLineCellText(terminal.buffer.lines[0]), startsWith('ab'));

      final secondCellGap = terminalLineCellText(terminal.buffer.lines[0]);
      expect(secondCellGap.length, terminal.buffer.lines[0].length);
    });

    test('a wide character occupies one character of the cell text', () {
      final terminal = Terminal()..resize(10, 2);
      terminal.write('中a');

      final text = terminalLineCellText(terminal.buffer.lines[0]);

      // The CJK glyph is one cell wide in this rendering; the trailing space is
      // its empty second cell, so the offsets stay aligned with columns.
      expect(text.startsWith('中'), isTrue);
      expect(text[1], ' ');
      expect(text[2], 'a');
    });
  });

  group('resolveTerminalLinkPath', () {
    test('prefers the workspace root for a relative reference', () {
      final resolved = resolveTerminalLinkPath(
        reference: 'src/main.py',
        workspaceRoot: '/work',
        exists: (candidate) => candidate == '/work/src/main.py',
      );

      expect(resolved, '/work/src/main.py');
    });

    test('falls back to the raw relative path', () {
      final resolved = resolveTerminalLinkPath(
        reference: 'src/main.py',
        workspaceRoot: '/work',
        exists: (candidate) => candidate == 'src/main.py',
      );

      expect(resolved, 'src/main.py');
    });

    test('keeps an absolute reference absolute', () {
      final resolved = resolveTerminalLinkPath(
        reference: '/opt/app/main.py',
        workspaceRoot: '/work',
        exists: (candidate) => candidate == '/opt/app/main.py',
      );

      expect(resolved, '/opt/app/main.py');
    });

    test('expands a leading home marker', () {
      final resolved = resolveTerminalLinkPath(
        reference: '~/notes.txt',
        homeDirectory: '/home/me',
        exists: (candidate) => candidate == '/home/me/notes.txt',
      );

      expect(resolved, '/home/me/notes.txt');
    });

    test('returns null when nothing exists', () {
      expect(
        resolveTerminalLinkPath(
          reference: 'gone.py',
          workspaceRoot: '/work',
          exists: (_) => false,
        ),
        isNull,
      );
    });

    test('returns null for a blank reference', () {
      expect(
        resolveTerminalLinkPath(reference: '  ', exists: (_) => true),
        isNull,
      );
    });
  });
}
