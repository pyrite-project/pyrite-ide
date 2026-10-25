import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/editor_outline.dart';

/// A flat `SymbolInformation` entry spanning [startLine] to [endLine].
Map<String, Object> _flatSymbol(
  String name,
  int kind,
  int startLine,
  int startCharacter,
  int endLine,
  int endCharacter, {
  String? containerName,
}) {
  return {
    'name': name,
    'kind': kind,
    'containerName': ?containerName,
    'location': {
      'uri': 'file:///work/ui.py',
      'range': {
        'start': {'line': startLine, 'character': startCharacter},
        'end': {'line': endLine, 'character': endCharacter},
      },
    },
  };
}

void main() {
  group('parseDocumentOutline', () {
    test('reads the hierarchical DocumentSymbol shape', () {
      final outline = parseDocumentOutline([
        {
          'name': 'Server',
          'kind': 5,
          'range': {
            'start': {'line': 2, 'character': 0},
            'end': {'line': 20, 'character': 0},
          },
          'selectionRange': {
            'start': {'line': 2, 'character': 6},
            'end': {'line': 2, 'character': 12},
          },
          'children': [
            {
              'name': 'start',
              'kind': 6,
              'detail': '() -> None',
              'range': {
                'start': {'line': 5, 'character': 2},
                'end': {'line': 9, 'character': 0},
              },
              'selectionRange': {
                'start': {'line': 5, 'character': 6},
                'end': {'line': 5, 'character': 11},
              },
            },
          ],
        },
      ]);

      expect(outline, hasLength(1));
      final server = outline.single;
      expect(server.name, 'Server');
      expect(server.kind, 5);
      // Navigation lands on the identifier, not the `class` keyword.
      expect(server.line, 2);
      expect(server.character, 6);
      expect(server.children, hasLength(1));

      final start = server.children.single;
      expect(start.name, 'start');
      expect(start.detail, '() -> None');
      expect(start.line, 5);
      expect(start.character, 6);
    });

    test('reads the flat SymbolInformation shape', () {
      final outline = parseDocumentOutline([
        {
          'name': 'main',
          'kind': 12,
          'location': {
            'uri': 'file:///work/main.py',
            'range': {
              'start': {'line': 30, 'character': 0},
              'end': {'line': 40, 'character': 0},
            },
          },
        },
      ]);

      expect(outline.single.name, 'main');
      expect(outline.single.line, 30);
      expect(outline.single.children, isEmpty);
    });

    test('rebuilds the class/method hierarchy from flat ranges', () {
      final outline = parseDocumentOutline([
        _flatSymbol('ST7789', 13, 0, 0, 0, 10),
        _flatSymbol('Ui', 5, 4, 0, 20, 0),
        _flatSymbol('__init__', 9, 5, 2, 8, 0),
        _flatSymbol('render', 6, 10, 2, 15, 0),
        _flatSymbol('start', 12, 20, 0, 30, 0),
      ]);

      expect(outline.map((node) => node.name), ['ST7789', 'Ui', 'start']);
      final ui = outline[1];
      expect(ui.children.map((node) => node.name), ['__init__', 'render']);
      // Nesting never moves the anchor a row navigates to.
      expect(ui.line, 4);
      expect(ui.children.first.line, 5);
    });

    test('trusts a hierarchical answer as-is, even without children', () {
      // The plugin rebuilds only the flat SymbolInformation shape; a
      // hierarchical answer is the server's own nesting and stays untouched.
      final outline = parseDocumentOutline([
        {
          'name': 'Ui',
          'kind': 5,
          'range': {
            'start': {'line': 4, 'character': 0},
            'end': {'line': 20, 'character': 0},
          },
          'selectionRange': {
            'start': {'line': 4, 'character': 6},
            'end': {'line': 4, 'character': 8},
          },
        },
        {
          'name': 'render',
          'kind': 6,
          'range': {
            'start': {'line': 10, 'character': 2},
            'end': {'line': 15, 'character': 0},
          },
          'selectionRange': {
            'start': {'line': 10, 'character': 6},
            'end': {'line': 10, 'character': 12},
          },
        },
      ]);

      expect(outline.map((node) => node.name), ['Ui', 'render']);
      expect(outline.every((node) => !node.hasChildren), isTrue);
      expect(outline[1].character, 6);
    });

    test('a symbol with no reported extent never gains children', () {
      final outline = parseDocumentOutline([
        {
          'name': 'Ui',
          'kind': 5,
          'selectionRange': {
            'start': {'line': 4, 'character': 6},
            'end': {'line': 4, 'character': 8},
          },
        },
        {
          'name': 'render',
          'kind': 6,
          'range': {
            'start': {'line': 10, 'character': 2},
            'end': {'line': 15, 'character': 0},
          },
          'selectionRange': {
            'start': {'line': 10, 'character': 6},
            'end': {'line': 10, 'character': 12},
          },
        },
      ]);

      expect(outline.map((node) => node.name), ['Ui', 'render']);
      expect(outline.every((node) => !node.hasChildren), isTrue);
    });

    test('keeps identical ranges as siblings instead of nesting them', () {
      final outline = parseDocumentOutline([
        _flatSymbol('b', 6, 10, 2, 20, 0),
        _flatSymbol('a', 6, 10, 2, 20, 0),
      ]);

      // The plugin's containment is strict: a range does not contain itself
      // or an equal one, so duplicated extents never nest.
      expect(outline.map((node) => node.name), ['b', 'a']);
      expect(outline.every((node) => !node.hasChildren), isTrue);
    });

    test('nests a flat symbol under the smallest enclosing range', () {
      final outline = parseDocumentOutline([
        _flatSymbol('app', 2, 0, 0, 100, 0),
        _flatSymbol('Ui', 5, 10, 0, 30, 0),
        _flatSymbol('render', 6, 12, 2, 20, 0),
      ]);

      // Both app and Ui enclose render; the tighter one wins.
      expect(outline, hasLength(1));
      expect(outline.single.name, 'app');
      expect(outline.single.children.map((node) => node.name), ['Ui']);
      expect(outline.single.children.single.children.single.name, 'render');
    });

    test('falls back to containerName when no range encloses the symbol', () {
      final outline = parseDocumentOutline([
        _flatSymbol('Ui', 5, 4, 0, 4, 8),
        _flatSymbol('run', 6, 6, 0, 6, 10, containerName: 'Ui'),
      ]);

      // Ui's reported extent is too small to contain run, so the parent comes
      // from the containerName the server attached.
      expect(outline, hasLength(1));
      expect(outline.single.name, 'Ui');
      expect(outline.single.children.single.name, 'run');
    });

    test('drops entries without a usable position', () {
      final outline = parseDocumentOutline([
        {'name': 'nowhere', 'kind': 12},
        {
          'kind': 12,
          'range': {
            'start': {'line': 1, 'character': 0},
          },
        },
        {'name': '', 'kind': 12},
      ]);

      expect(outline, isEmpty);
    });

    test('returns an empty tree for malformed input', () {
      expect(parseDocumentOutline(null), isEmpty);
      expect(parseDocumentOutline('not a list'), isEmpty);
      expect(parseDocumentOutline(<Object>[]), isEmpty);
    });
  });

  group('DocumentOutlineNode.flatten', () {
    const tree = DocumentOutlineNode(
      name: 'root',
      kind: 1,
      line: 0,
      character: 0,
      children: [
        DocumentOutlineNode(name: 'a', kind: 12, line: 1, character: 0),
        DocumentOutlineNode(
          name: 'b',
          kind: 5,
          line: 5,
          character: 0,
          children: [
            DocumentOutlineNode(name: 'b1', kind: 6, line: 6, character: 2),
          ],
        ),
      ],
    );

    test('includes nested rows with their depth when nothing is collapsed', () {
      final rows = tree.flatten(const {});

      expect(rows.map((row) => row.node.name), ['root', 'a', 'b', 'b1']);
      expect(rows.map((row) => row.depth), [0, 1, 1, 2]);
    });

    test('hides children of a collapsed row but keeps the row itself', () {
      final rows = tree.flatten({5});

      expect(rows.map((row) => row.node.name), ['root', 'a', 'b']);
    });
  });

  test('outlineKindLabel names the protocol kinds', () {
    expect(outlineKindLabel(5), 'class');
    expect(outlineKindLabel(12), 'function');
    expect(outlineKindLabel(999), '');
  });

  group('scanPythonOutline', () {
    test('nests defs and classes by indentation', () {
      const source =
          'class Ui:\n'
          '    def start(self):\n'
          '        x = 1\n'
          '\n'
          'def main():\n'
          '    pass\n'
          '\n'
          'async def fetch():\n'
          '    pass\n';
      final outline = scanPythonOutline(source);

      expect(outline.map((node) => node.name), ['Ui', 'main', 'fetch']);

      final ui = outline[0];
      expect(ui.kind, 5);
      expect(ui.detail, 'class');
      expect(ui.line, 0);
      expect(ui.character, 0);
      expect(ui.children, hasLength(1));

      final start = ui.children.single;
      expect(start.kind, 6);
      expect(start.detail, 'def');
      expect(start.line, 1);
      expect(start.character, 4);
      // The extent covers just the name.
      expect(start.endLine, 1);
      expect(start.endCharacter, 9);

      // `main` dedents back to column 0, so it leaves the class.
      expect(outline[1].kind, 12);
      expect(outline[1].line, 4);
      expect(outline[1].children, isEmpty);

      // `async def` at the top level is a plain function.
      expect(outline[2].kind, 12);
      expect(outline[2].line, 7);
    });

    test('a dedent re-parents to the enclosing block', () {
      const source =
          'class Ui:\n'
          '    def a(self):\n'
          '        pass\n'
          '  def b(self):\n'
          '        pass\n';
      final outline = scanPythonOutline(source);

      expect(outline, hasLength(1));
      final ui = outline.single;
      expect(ui.children.map((node) => node.name), ['a', 'b']);
      // `b` sits shallower than `a` but deeper than the class, so it is
      // still a method of Ui.
      expect(ui.children.every((node) => node.kind == 6), isTrue);
    });

    test('tabs expand to eight columns for nesting', () {
      const source =
          'class Ui:\n'
          '\tdef start(self):\n'
          '\t\tpass\n';
      final outline = scanPythonOutline(source);

      final ui = outline.single;
      expect(ui.children.single.name, 'start');
      expect(ui.children.single.character, 1);
    });

    test('a def inside a def stays a function', () {
      const source =
          'def outer():\n'
          '    def inner():\n'
          '        pass\n';
      final outline = scanPythonOutline(source);

      expect(outline.single.name, 'outer');
      final inner = outline.single.children.single;
      expect(inner.name, 'inner');
      expect(inner.kind, 12);
    });

    test('only real definitions match', () {
      const source =
          'def _ok():\n'
          '    pass\n'
          '\n'
          'definitely_not_a_def()\n'
          '\n'
          'def 1bad():\n'
          '    pass\n';
      final outline = scanPythonOutline(source);

      // A name must start with a letter or underscore, and the keyword must
      // be a whole word.
      expect(outline.map((node) => node.name), ['_ok']);
    });

    test('rejects sources past the size limits', () {
      expect(
        () => scanPythonOutline('x\n' * 20001),
        throwsA(isA<OutlineSourceTooLarge>()),
      );
      expect(
        () => scanPythonOutline('x' * (1024 * 1024 + 1)),
        throwsA(isA<OutlineSourceTooLarge>()),
      );
    });

    test('accepts a file at exactly the line limit', () {
      final outline = scanPythonOutline('x\n' * 19998 + 'def ok():\n    pass');
      expect(outline.single.name, 'ok');
    });
  });
}
