import 'package:flutter/foundation.dart';
import 'package:pyrite_ide/core/services/pylsp/core.dart';

@immutable
class LspHoverContent {
  const LspHoverContent({required this.text, this.kind});

  final String text;
  final String? kind;
}

Future<LspHoverContent?> fetchHover({
  required LspClient client,
  required String uri,
  required int line,
  required int character,
}) async {
  final result = await client.sendRequest('textDocument/hover', {
    'textDocument': {'uri': uri},
    'position': {'line': line + 1, 'character': character},
  });

  if (result is! Map) return null;
  final contents = result['contents'];
  if (contents == null) return null;

  final parsed = _parseHoverContents(contents);
  if (parsed == null) return null;
  if (parsed.text.trim().isEmpty) return null;
  return parsed;
}

LspHoverContent? _parseHoverContents(dynamic contents) {
  if (contents is String) {
    // LSP MarkedString string is Markdown by spec; plain text will still render.
    return LspHoverContent(text: contents, kind: 'markdown');
  }

  if (contents is Map) {
    final map = Map<String, dynamic>.from(contents);
    final language = map['language'];
    final value = map['value'];
    if (value is String) {
      if (language is String) {
        final lang = language.trim();
        final fenced = ['```$lang'.trimRight(), value, '```'].join('\n');
        return LspHoverContent(text: fenced, kind: 'markdown');
      }

      final kind = map['kind'] as String?;
      return LspHoverContent(text: value, kind: kind ?? 'plaintext');
    }
  }

  if (contents is List) {
    final parts = <String>[];
    String? kind;
    for (final entry in contents) {
      if (entry is String) {
        parts.add(entry);
        kind ??= 'markdown';
        continue;
      }
      if (entry is Map) {
        final map = Map<String, dynamic>.from(entry);
        final language = map['language'];
        final value = map['value'];
        if (value is String) {
          if (language is String) {
            final lang = language.trim();
            parts.add(['```$lang'.trimRight(), value, '```'].join('\n'));
            kind = 'markdown';
          } else {
            parts.add(value);
            final entryKind = map['kind'] as String?;
            if (entryKind == 'markdown') {
              kind = 'markdown';
            } else {
              kind ??= entryKind ?? 'plaintext';
            }
          }
        }
      }
    }
    if (parts.isEmpty) return null;
    return LspHoverContent(text: parts.join('\n\n'), kind: kind);
  }

  return null;
}
