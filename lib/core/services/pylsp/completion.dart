import 'package:flutter/foundation.dart';
import 'package:pyrite_ide/core/services/pylsp/core.dart';

@immutable
class LspCompletionItem {
  const LspCompletionItem({
    required this.label,
    required this.insertText,
    this.detail,
    this.kind,
    this.sortText,
  });

  final String label;
  final String insertText;
  final String? detail;
  final int? kind;
  final String? sortText;
}

Future<List<LspCompletionItem>> fetchCompletions({
  required LspClient client,
  required String uri,
  required int line,
  required int character,
  String? triggerCharacter,
}) async {
  final triggerKind = triggerCharacter == null ? 1 : 2;
  print(triggerCharacter);
  final result = await client.sendRequest('textDocument/completion', {
    'textDocument': {'uri': uri},
    'position': {'line': line, 'character': character},
    'context': {
      'triggerKind': triggerKind,
      if (triggerCharacter != null) 'triggerCharacter': triggerCharacter,
    },
  });

  final items = _extractCompletionItems(result);
  final parsed = items
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .map(_parseCompletionItem)
      .whereType<LspCompletionItem>()
      .toList(growable: false);

  return parsed;
}

List<dynamic> _extractCompletionItems(dynamic result) {
  if (result is List) return result;
  if (result is Map) {
    final items = result['items'];
    if (items is List) return items;
  }
  return const [];
}

LspCompletionItem? _parseCompletionItem(Map<String, dynamic> json) {
  final label = json['label'];
  if (label is! String || label.isEmpty) return null;

  String? insertText;

  // Prefer textEdit.newText when present.
  final textEdit = json['textEdit'];
  if (textEdit is Map) {
    final newText = textEdit['newText'];
    if (newText is String && newText.isNotEmpty) {
      insertText = newText;
    }
  }

  insertText ??= (json['insertText'] as String?)?.trimRight();
  insertText ??= label;

  final insertTextFormat = json['insertTextFormat'];
  if (insertTextFormat == 2) {
    insertText = _flattenSnippet(insertText);
  }

  return LspCompletionItem(
    label: label,
    insertText: insertText,
    detail: json['detail'] as String?,
    kind: json['kind'] as int?,
    sortText: json['sortText'] as String?,
  );
}

String _flattenSnippet(String snippet) {
  var text = snippet;

  // ${1:foo} -> foo
  text = text.replaceAllMapped(
    RegExp(r'\$\{\d+:([^}]+)\}'),
    (m) => m.group(1) ?? '',
  );
  // ${1} -> ''
  text = text.replaceAllMapped(RegExp(r'\$\{\d+\}'), (_) => '');
  // $1 -> ''
  text = text.replaceAllMapped(RegExp(r'\$\d+'), (_) => '');
  // $0 -> ''
  text = text.replaceAll('\$0', '');

  return text;
}
