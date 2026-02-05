import 'package:pyrite_ide/core/services/pylsp/core.dart';
import 'package:pyrite_ide/core/services/pylsp/data.dart';

Future<void> fetchDocumentHighlights({
  required LspClient client,
  required String uri,
  required int line,
  required int character,
}) async {
  try {
    final result = await client.sendRequest('textDocument/documentHighlight', {
      'textDocument': {'uri': uri},
      'position': {'line': line, 'character': character},
    });

    final highlights = (result is List ? result : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(LspDocumentHighlight.fromJson)
        .toList(growable: false);

    setDocumentHighlights(uri, highlights);
  } catch (_) {
    setDocumentHighlights(uri, const []);
  }
}

Future<void> fetchSemanticTokens({
  required LspClient client,
  required String uri,
}) async {
  if (!client.supportsSemanticTokens) return;

  try {
    final result = await client.sendRequest('textDocument/semanticTokens/full', {
      'textDocument': {'uri': uri},
    });

    final data = _extractSemanticTokenData(result);
    if (data == null || data.isEmpty) {
      setSemanticTokens(uri, const {});
      return;
    }

    final tokensByLine = _decodeSemanticTokens(
      data: data,
      tokenTypes: client.semanticTokenTypes,
    );
    setSemanticTokens(uri, tokensByLine);
  } catch (_) {
    // Server may not support semantic tokens even if we asked for it.
    setSemanticTokens(uri, const {});
  }
}

List<int>? _extractSemanticTokenData(dynamic result) {
  if (result is Map) {
    final data = result['data'];
    if (data is List) {
      return data.whereType<num>().map((e) => e.toInt()).toList(growable: false);
    }
  }
  return null;
}

Map<int, List<LspSemanticToken>> _decodeSemanticTokens({
  required List<int> data,
  required List<String> tokenTypes,
}) {
  var line = 0;
  var character = 0;

  final byLine = <int, List<LspSemanticToken>>{};

  for (var i = 0; i + 4 < data.length; i += 5) {
    final deltaLine = data[i];
    final deltaStart = data[i + 1];
    final length = data[i + 2];
    final tokenTypeIndex = data[i + 3];
    final modifiers = data[i + 4];

    line += deltaLine;
    if (deltaLine == 0) {
      character += deltaStart;
    } else {
      character = deltaStart;
    }

    final tokenType = tokenTypeIndex >= 0 && tokenTypeIndex < tokenTypes.length
        ? tokenTypes[tokenTypeIndex]
        : null;

    final token = LspSemanticToken(
      line: line,
      startChar: character,
      length: length,
      tokenType: tokenType,
      modifiers: modifiers,
    );

    (byLine[line] ??= <LspSemanticToken>[]).add(token);
  }

  // Keep stable ordering for deterministic rendering.
  for (final entry in byLine.entries) {
    entry.value.sort((a, b) => a.startChar.compareTo(b.startChar));
  }

  return byLine;
}
