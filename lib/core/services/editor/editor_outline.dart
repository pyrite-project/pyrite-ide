/// Normalised view of the two shapes `textDocument/documentSymbol` can return.
///
/// The protocol defines `DocumentSymbol[]` (hierarchical, each entry carries
/// `children` and a `selectionRange`) and `SymbolInformation[]` (flat, each
/// entry carries a `location`). Servers pick one or the other, so an outline
/// has to accept both — otherwise the panel is empty against exactly the
/// servers that chose the other spelling.
///
/// This file is pure parsing: it takes the raw JSON list — or the raw source
/// text for the regex fallback — and returns a tree. Rendering and navigation
/// live in the widget that consumes it. The behavior mirrors the
/// debug-enhanced plugin's outline, which is the reference implementation
/// this panel follows.
library;

import 'dart:convert';

/// One row of an outline.
class DocumentOutlineNode {
  const DocumentOutlineNode({
    required this.name,
    required this.kind,
    required this.line,
    required this.character,
    this.detail = '',
    this.endLine,
    this.endCharacter,
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

  /// Zero-based line/character just past the symbol's body, when the server
  /// reported a full range. Null means the extent is unknown, in which case
  /// the symbol is treated as ending where it starts (it can hold no child).
  final int? endLine;
  final int? endCharacter;

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
/// A flat `SymbolInformation` answer reports every symbol as a sibling, so
/// the class/method hierarchy is rebuilt afterwards, following the
/// debug-enhanced plugin: a symbol becomes the child of the smallest range
/// that strictly contains its own, or — when no range encloses it — of the
/// last earlier symbol named by its `containerName`. Hierarchical answers
/// keep the server's own nesting untouched, even when it arrived without any
/// children.
///
/// Entries that carry neither a range nor a resolvable location are dropped:
/// they cannot be jumped to, so showing them would be a dead row.
List<DocumentOutlineNode> parseDocumentOutline(Object? result) {
  if (result is! List) return const [];
  final entries = result.whereType<Map>().toList(growable: false);
  final parsed = <(DocumentOutlineNode, Map)>[];
  for (final raw in entries) {
    final node = _parseEntry(raw);
    if (node != null) parsed.add((node, raw));
  }
  // The flat shape is the one where every entry carries a `location` — that
  // is the shape whose hierarchy was lost and has to be rebuilt.
  final flatShape =
      parsed.isNotEmpty && parsed.every((entry) => entry.$2['location'] is Map);
  if (!flatShape) return [for (final (node, _) in parsed) node];
  return _rebuildFlatTree(parsed);
}

/// Rebuilds parent/child nesting among flat `SymbolInformation` entries.
///
/// Each entry still carries the full range of the symbol it describes, and a
/// method's range lies inside its class's range, so the parent is the
/// smallest range that strictly contains the child's — a range does not
/// contain itself or an equal one, which keeps duplicated extents siblings.
/// Entries no range encloses fall back to `containerName`: the last earlier
/// symbol with that name becomes the parent. Siblings keep the answer's
/// original order.
List<DocumentOutlineNode> _rebuildFlatTree(
  List<(DocumentOutlineNode, Map)> parsed,
) {
  final ranges = [for (final (_, raw) in parsed) _rawRange(raw)];
  final parents = List<int?>.filled(parsed.length, null);

  for (var child = 0; child < parsed.length; child++) {
    final childRange = ranges[child];
    if (childRange != null) {
      int? parent;
      var parentSpan = (0, 0);
      for (var candidate = 0; candidate < parsed.length; candidate++) {
        final candidateRange = ranges[candidate];
        if (candidate == child || candidateRange == null) continue;
        if (!_strictlyContains(candidateRange, childRange)) continue;
        final span = (
          candidateRange.$2.$1 - candidateRange.$1.$1,
          candidateRange.$2.$2 - candidateRange.$1.$2,
        );
        // Strictly smaller keeps the lowest index on ties, which is the
        // order Python's `min` would pick for the plugin.
        if (parent == null || _spanLess(span, parentSpan)) {
          parent = candidate;
          parentSpan = span;
        }
      }
      if (parent != null) {
        parents[child] = parent;
        continue;
      }
    }

    final containerName = parsed[child].$2['containerName']?.toString();
    if (containerName == null || containerName.isEmpty) continue;
    for (var candidate = child - 1; candidate >= 0; candidate--) {
      if (parsed[candidate].$1.name == containerName) {
        parents[child] = candidate;
        break;
      }
    }
  }

  final holders = [for (final (node, _) in parsed) _OutlineHolder(node)];
  for (var child = 0; child < parsed.length; child++) {
    final parent = parents[child];
    if (parent != null) holders[parent].children.add(holders[child]);
  }
  return [
    for (var index = 0; index < holders.length; index++)
      if (parents[index] == null) holders[index].build(),
  ];
}

/// The full symbol extent as `((startLine, startCharacter), (endLine, endCharacter))`,
/// or null when the entry reports no usable extent.
///
/// The hierarchical `range` wins, then the flat `location.range`, then
/// `selectionRange`; a range missing either end counts as no extent at all.
((int, int), (int, int))? _rawRange(Map raw) {
  final location = raw['location'];
  final locationRange = location is Map ? location['range'] : null;
  Map? symbolRange = _nonEmptyMap(raw['range']);
  symbolRange ??= _nonEmptyMap(locationRange);
  symbolRange ??= _nonEmptyMap(raw['selectionRange']);
  if (symbolRange == null) return null;
  final start = symbolRange['start'];
  final end = symbolRange['end'];
  if (start is! Map || end is! Map) return null;
  return (
    (_asInt(start['line']) ?? 0, _asInt(start['character']) ?? 0),
    (_asInt(end['line']) ?? 0, _asInt(end['character']) ?? 0),
  );
}

Map? _nonEmptyMap(Object? value) =>
    value is Map && value.isNotEmpty ? value : null;

/// Whether [outer]'s extent strictly contains [inner]'s.
///
/// Equal ranges do not contain each other, so a duplicate extent never nests
/// under its twin.
bool _strictlyContains(
  ((int, int), (int, int)) outer,
  ((int, int), (int, int)) inner,
) {
  if (_samePosition(outer.$1, inner.$1) && _samePosition(outer.$2, inner.$2)) {
    return false;
  }
  return _comparePositions(outer.$1, inner.$1) <= 0 &&
      _comparePositions(outer.$2, inner.$2) >= 0;
}

bool _samePosition((int, int) a, (int, int) b) => a.$1 == b.$1 && a.$2 == b.$2;

int _comparePositions((int, int) a, (int, int) b) {
  if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
  return a.$2.compareTo(b.$2);
}

/// Whether span [a] is strictly shorter than span [b] (lines first, then
/// characters).
bool _spanLess((int, int) a, (int, int) b) {
  if (a.$1 != b.$1) return a.$1 < b.$1;
  return a.$2 < b.$2;
}

class _OutlineHolder {
  _OutlineHolder(this.node);

  final DocumentOutlineNode node;
  final children = <_OutlineHolder>[];

  DocumentOutlineNode build() {
    return DocumentOutlineNode(
      name: node.name,
      kind: node.kind,
      line: node.line,
      character: node.character,
      detail: node.detail,
      endLine: node.endLine,
      endCharacter: node.endCharacter,
      children: [for (final child in children) child.build()],
    );
  }
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

  // Nesting works from the whole-symbol extent, so keep the end even when
  // the anchor came from the selection range.
  final extent = _endOf(range) ?? _endOf(locationRange);

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
    endLine: extent?.$1,
    endCharacter: extent?.$2,
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

(int, int)? _endOf(Object? range) {
  if (range is! Map) return null;
  final end = range['end'];
  if (end is! Map) return null;
  final line = _asInt(end['line']);
  final character = _asInt(end['character']) ?? 0;
  if (line == null) return null;
  return (line, character);
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

/// Source-size limits the fallback outline scan accepts, matching the
/// debug-enhanced plugin: the scan is a plain line-by-line regex pass, and
/// capping it keeps a pathological file from stalling the UI.
const int outlineMaxSourceBytes = 1024 * 1024;
const int outlineMaxSourceLines = 20000;

/// Raised by [scanPythonOutline] when the source exceeds the scan limits.
class OutlineSourceTooLarge implements Exception {
  const OutlineSourceTooLarge(this.bytes, this.lines);

  final int bytes;
  final int lines;

  @override
  String toString() =>
      'source is $bytes bytes / $lines lines; '
      'limit is $outlineMaxSourceBytes bytes / $outlineMaxSourceLines lines';
}

final RegExp _pythonDefinitionPattern = RegExp(
  r'^([ \t]*)(?:async[ \t]+)?(def|class)[ \t]+([^\W\d]\w*)',
);

/// Scans Python source for `class` / `def` definitions and nests them by
/// indentation.
///
/// This is the fallback the debug-enhanced plugin uses when the language
/// service answers no symbols or is not running: a plain pattern pass that
/// keeps working on files a real parser would reject. Kinds follow the LSP
/// numbering the rest of the outline uses — class 5, a `def` directly inside
/// a class 6, any other `def` 12 — and the detail carries the keyword. Each
/// row lands on the name's column, and its extent covers just the name.
///
/// Throws [OutlineSourceTooLarge] past [outlineMaxSourceBytes] or
/// [outlineMaxSourceLines].
List<DocumentOutlineNode> scanPythonOutline(String source) {
  final bytes = utf8.encode(source).length;
  final lines = source.isEmpty ? const <String>[] : source.split('\n');
  if (bytes > outlineMaxSourceBytes || lines.length > outlineMaxSourceLines) {
    throw OutlineSourceTooLarge(bytes, lines.length);
  }

  final roots = <_OutlineSymbolBuilder>[];
  final stack = <(int, _OutlineSymbolBuilder)>[];
  for (var lineNumber = 0; lineNumber < lines.length; lineNumber++) {
    final match = _pythonDefinitionPattern.firstMatch(lines[lineNumber]);
    if (match == null) continue;

    final indent = _expandedTabsWidth(match.group(1)!);
    while (stack.isNotEmpty && indent <= stack.last.$1) {
      stack.removeLast();
    }

    final keyword = match.group(2)!;
    final parent = stack.isEmpty ? null : stack.last.$2;
    final kind = switch (keyword) {
      'class' => 5,
      _ when parent != null && parent.kind == 5 => 6,
      _ => 12,
    };
    final symbol = _OutlineSymbolBuilder(
      name: match.group(3)!,
      kind: kind,
      detail: keyword,
      line: lineNumber,
      character: match.group(1)!.length,
    );
    if (parent == null) {
      roots.add(symbol);
    } else {
      parent.children.add(symbol);
    }
    stack.add((indent, symbol));
  }
  return [for (final root in roots) root.build()];
}

/// Width of an indent run with tabs advancing to the next multiple of 8 —
/// the plugin's `expandtabs(8)`. The pattern only puts spaces and tabs in an
/// indent, so no other character needs a width.
int _expandedTabsWidth(String indent) {
  var width = 0;
  for (final codeUnit in indent.codeUnits) {
    width = codeUnit == 0x09 ? (width ~/ 8 + 1) * 8 : width + 1;
  }
  return width;
}

/// Mutable stand-in while the scan assembles the tree.
class _OutlineSymbolBuilder {
  _OutlineSymbolBuilder({
    required this.name,
    required this.kind,
    required this.detail,
    required this.line,
    required this.character,
  });

  final String name;
  final int kind;
  final String detail;
  final int line;
  final int character;
  final children = <_OutlineSymbolBuilder>[];

  DocumentOutlineNode build() {
    return DocumentOutlineNode(
      name: name,
      kind: kind,
      line: line,
      character: character,
      detail: detail,
      endLine: line,
      endCharacter: character + name.length,
      children: [for (final child in children) child.build()],
    );
  }
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
