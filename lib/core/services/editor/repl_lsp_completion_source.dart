import 'dart:async';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:pyrite_ide/core/services/editor/repl_completion_controller.dart';

class ReplLspCompletionSource {
  ReplLspCompletionSource({required this.currentController});

  final CodeForgeController? Function() currentController;

  Future<void> _tail = Future<void>.value();
  LspConfig? _activeConfig;
  String? _documentPath;
  bool _documentOpen = false;
  bool _disposed = false;

  Future<List<ReplCompletionItem>> complete(ReplCompletionContext context) =>
      _synchronized(() => _complete(context));

  Future<ReplSignatureHint?> signature(ReplSignatureContext context) =>
      _synchronized(() => _signature(context));

  Future<List<ReplCompletionItem>> _complete(
    ReplCompletionContext context,
  ) async {
    if (_disposed) return const [];
    final config = currentController()?.lspConfig;
    if (config == null ||
        !config.isInitialized ||
        !config.capabilities.codeCompletion) {
      return const [];
    }

    try {
      await _ensureDocument(config, context.source);
      final before = context.source.substring(0, context.cursor);
      final lines = before.split('\n');
      final completions = await config.getCompletions(
        _documentPath!,
        lines.length - 1,
        lines.last.length,
      );
      final items = <ReplCompletionItem>[];
      for (final completion in completions) {
        final item = _mapCompletion(completion, context);
        if (item != null) items.add(item);
      }
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<ReplSignatureHint?> _signature(ReplSignatureContext context) async {
    if (_disposed) return null;
    final config = currentController()?.lspConfig;
    if (config == null ||
        !config.isInitialized ||
        !config.capabilities.signatureHelp) {
      return null;
    }
    try {
      await _ensureDocument(config, context.source);
      final before = context.source.substring(0, context.cursor);
      final lines = before.split('\n');
      final result = await config.getSignatureHelp(
        _documentPath!,
        lines.length - 1,
        lines.last.length,
        context.triggerCharacter == null ? 1 : 2,
        triggerCharacter: context.triggerCharacter,
      );
      if (result.label.isEmpty) return null;
      return ReplSignatureHint(
        label: result.label,
        activeParameter: result.activeParameter,
        source: ReplCompletionSource.lsp,
        documentation: result.documentation.isEmpty
            ? null
            : result.documentation,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureDocument(LspConfig config, String source) async {
    if (_activeConfig != null && _activeConfig != config && _documentOpen) {
      try {
        await _activeConfig!.closeDocument(_documentPath!);
      } catch (_) {}
      _documentOpen = false;
    }
    _activeConfig = config;
    _documentPath ??=
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'pyrite_ide_repl_${identityHashCode(this)}.py';
    final file = File(_documentPath!);
    if (!_documentOpen) {
      await file.writeAsString(source);
      await config.openDocument(_documentPath!);
      _documentOpen = true;
    } else {
      await config.updateDocument(_documentPath!, source);
    }
  }

  ReplCompletionItem? _mapCompletion(
    LspCompletion completion,
    ReplCompletionContext context,
  ) {
    final raw = completion.completionItem;
    final insertText = _completionText(raw, completion.label);
    if (insertText.isEmpty || !completion.label.startsWith(context.token)) {
      return null;
    }
    return ReplCompletionItem(
      label: completion.label,
      insertText: insertText,
      replaceStart: context.replaceStart,
      replaceEnd: context.replaceEnd,
      kind: _mapKind(completion.itemType),
      source: ReplCompletionSource.lsp,
      detail: raw['detail']?.toString(),
      documentation: _documentationText(raw['documentation']),
    );
  }

  String _completionText(Map<String, dynamic> raw, String fallback) {
    final textEdit = raw['textEdit'];
    if (textEdit is Map && textEdit['newText'] != null) {
      return _plainInsertText(textEdit['newText'].toString(), raw);
    }
    return _plainInsertText(raw['insertText']?.toString() ?? fallback, raw);
  }

  String _plainInsertText(String value, Map<String, dynamic> raw) {
    if (raw['insertTextFormat'] == 2) {
      return raw['label']?.toString() ?? value;
    }
    return value;
  }

  String? _documentationText(Object? value) {
    if (value is String) return value;
    if (value is Map && value['value'] != null) {
      return value['value'].toString();
    }
    return null;
  }

  ReplCompletionKind _mapKind(CompletionItemType kind) => switch (kind) {
    CompletionItemType.keyword => ReplCompletionKind.keyword,
    CompletionItemType.module ||
    CompletionItemType.file ||
    CompletionItemType.folder => ReplCompletionKind.module,
    CompletionItemType.function ||
    CompletionItemType.method ||
    CompletionItemType.constructor => ReplCompletionKind.function,
    CompletionItemType.class_ ||
    CompletionItemType.interface ||
    CompletionItemType.struct ||
    CompletionItemType.typeParameter => ReplCompletionKind.className,
    CompletionItemType.variable ||
    CompletionItemType.field => ReplCompletionKind.variable,
    CompletionItemType.property => ReplCompletionKind.property,
    CompletionItemType.constant ||
    CompletionItemType.enum_ ||
    CompletionItemType.enumMember ||
    CompletionItemType.value_ => ReplCompletionKind.constant,
    _ => ReplCompletionKind.text,
  };

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final config = _activeConfig;
    final path = _documentPath;
    if (config != null && path != null && _documentOpen) {
      unawaited(config.closeDocument(path).catchError((_) {}));
    }
    if (path != null) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
  }
}
