import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/editor_outline.dart';

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
}
