/// Normalised view of the two shapes `textDocument/documentSymbol` can return.
///
/// The protocol defines `DocumentSymbol[]` (hierarchical, each entry carries
/// `children` and a `selectionRange`) and `SymbolInformation[]` (flat, each
/// entry carries a `location`). Servers pick one or the other, so an outline
/// has to accept both — otherwise the panel is empty against exactly the
/// servers that chose the other spelling.
///
/// This file is pure parsing: it takes the raw JSON list and returns a tree.
/// Rendering and navigation live in the widget that consumes it.
library;

/// One row of an outline.
class DocumentOutlineNode {
  const DocumentOutlineNode({
    required this.name,
    required this.kind,
    required this.line,
    required this.character,
    this.detail = '',
    this.children = const [],
  });

  /// Symbol name as the server reported it.
  final String name;

  /// LSP `SymbolKind` (1 = file, 12 = function, 13 = variable, …).
  final int kind;

  /// Zero-based line the symbol body starts on.
  final int line;

  /// Zero-based character on [line].
  final int character;

  /// Type or signature text, when the server sent one.
  final String detail;

  final List<DocumentOutlineNode> children;

  bool get hasChildren => children.isNotEmpty;

  /// Flattens the tree for a list view that indents by depth.
  ///
  /// [expanded] decides which parents contribute their children, so the
  /// flattened result matches what the user has collapsed.
  List<({DocumentOutlineNode node, int depth})> flatten(
    Set<int> collapsedLines,
  ) {
    final rows = <({DocumentOutlineNode node, int depth})>[];
    void walk(DocumentOutlineNode node, int depth) {
      rows.add((node: node, depth: depth));
      if (collapsedLines.contains(node.line)) return;
      for (final child in node.children) {
        walk(child, depth + 1);
      }
    }

    walk(this, 0);
    return rows;
  }
}

/// Parses the `result` of `textDocument/documentSymbol` into a tree.
///
/// Entries that carry neither a range nor a resolvable location are dropped:
/// they cannot be jumped to, so showing them would be a dead row.
List<DocumentOutlineNode> parseDocumentOutline(Object? result) {
  final roots = <DocumentOutlineNode>[];
  if (result is! List) return roots;

  for (final raw in result) {
    final node = _parseEntry(raw);
    if (node != null) roots.add(node);
  }
  return roots;
}

DocumentOutlineNode? _parseEntry(Object? raw) {
  if (raw is! Map) return null;
  final name = raw['name']?.toString() ?? '';
  if (name.isEmpty) return null;

  final kind = _asInt(raw['kind']) ?? 0;
  final detail = raw['detail']?.toString() ?? '';

  // Hierarchical shape first: `range` describes the whole symbol and
  // `selectionRange` the identifier inside it. Navigation wants the
  // identifier, because that is the line a reader expects to land on.
  final selectionRange = raw['selectionRange'];
  final range = raw['range'];
  final anchor = _startOf(selectionRange) ?? _startOf(range);

  // Flat shape: everything hangs off `location.range`.
  final locationRange = raw['location'] is Map
      ? (raw['location'] as Map)['range']
      : null;
  final resolved = anchor ?? _startOf(locationRange);
  if (resolved == null) return null;

  final children = <DocumentOutlineNode>[];
  final rawChildren = raw['children'];
  if (rawChildren is List) {
    for (final child in rawChildren) {
      final parsed = _parseEntry(child);
      if (parsed != null) children.add(parsed);
    }
  }

  return DocumentOutlineNode(
    name: name,
    kind: kind,
    line: resolved.$1,
    character: resolved.$2,
    detail: detail,
    children: children,
  );
}

(int, int)? _startOf(Object? range) {
  if (range is! Map) return null;
  final start = range['start'];
  if (start is! Map) return null;
  final line = _asInt(start['line']);
  final character = _asInt(start['character']) ?? 0;
  if (line == null) return null;
  return (line, character);
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

/// A short label for [kind], used when a row has no detail text.
///
/// Unknown kinds fall back to an empty string rather than a wrong name; the
/// row simply shows the symbol alone.
String outlineKindLabel(int kind) {
  return switch (kind) {
    1 => 'file',
    2 => 'module',
    3 => 'namespace',
    4 => 'package',
    5 => 'class',
    6 => 'method',
    7 => 'property',
    8 => 'field',
    9 => 'constructor',
    10 => 'enum',
    11 => 'interface',
    12 => 'function',
    13 => 'variable',
    14 => 'constant',
    15 => 'string',
    16 => 'number',
    17 => 'boolean',
    18 => 'array',
    19 => 'object',
    20 => 'key',
    21 => 'null',
    22 => 'enum member',
    23 => 'struct',
    24 => 'event',
    25 => 'operator',
    26 => 'type parameter',
    _ => '',
  };
}
