import 'package:flutter/foundation.dart';
import 'package:pyrite_ide/core/services/pylsp/core.dart';

@immutable
class LspHoverContent {
  const LspHoverContent({
    required this.text,
    this.kind,
  });

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
    'position': {'line': line, 'character': character},
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
    return LspHoverContent(text: contents, kind: 'plaintext');
  }

  if (contents is Map) {
    final map = Map<String, dynamic>.from(contents);
    final value = map['value'];
    if (value is String) {
      final kind = map['kind'] as String?;
      return LspHoverContent(text: value, kind: kind);
    }
  }

  if (contents is List) {
    final parts = <String>[];
    String? kind;
    for (final entry in contents) {
      if (entry is String) {
        parts.add(entry);
        kind ??= 'plaintext';
        continue;
      }
      if (entry is Map) {
        final map = Map<String, dynamic>.from(entry);
        final value = map['value'];
        if (value is String) {
          parts.add(value);
          kind ??= map['kind'] as String?;
        }
      }
    }
    if (parts.isEmpty) return null;
    return LspHoverContent(text: parts.join('\n\n'), kind: kind);
  }

  return null;
}

