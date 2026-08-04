import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/document_registry.dart';
import 'package:pyrite_ide/core/sdk/document_service.dart';
import 'package:pyrite_ide/core/sdk/editor_document_host.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';

abstract class SdkEditorDocumentCommands {
  static const String activeDocumentGet = 'sdk.editor.active_document.get';
  static const String documentGet = 'sdk.editor.document.get';
  static const String documentSymbols = 'sdk.editor.document.symbols';
  static const String documentReveal = 'sdk.editor.document.reveal';
  static const String selectionGet = 'sdk.editor.document.selection.get';
}

/// Resolves a plugin-facing document to the host state needed to serve queries.
///
/// Supplied by the Flutter wiring layer; kept as an interface so the API can be
/// unit-tested with a fake editor.
abstract class DocumentHost {
  DocumentRegistry get registry;

  /// Read access to the document with [documentId], or null when it is not an
  /// open, inspectable document.
  DocumentAccess? access(String documentId);

  /// The active document's id, or null when none is focused.
  String? get activeDocumentId;

  /// Activates the target document and reveals a location once its editor is
  /// mounted. Compact layouts may need to navigate to the editor page first.
  Future<void> reveal(String documentId, {required int line, int? column});
}

/// Exposes host document queries to a plugin: active/get/symbols/reveal/
/// selection. Requires `editor.read`; reveal additionally requires
/// `editor.write` since it moves the caret.
class SdkEditorDocument {
  SdkEditorDocument(this.ref);

  final Ref ref;

  DocumentHost get _host => ref.read(documentHostProvider);

  void bind(PluginRunManager manager) {
    manager.registerHandler(
      SdkEditorDocumentCommands.activeDocumentGet,
      _handleActiveGet,
      requiredPermission: 'editor:read',
    );
    manager.registerHandler(
      SdkEditorDocumentCommands.documentGet,
      _handleGet,
      requiredPermission: 'editor:read',
    );
    manager.registerHandler(
      SdkEditorDocumentCommands.documentSymbols,
      _handleSymbols,
      requiredPermission: 'editor:read',
    );
    manager.registerHandler(
      SdkEditorDocumentCommands.selectionGet,
      _handleSelectionGet,
      requiredPermission: 'editor:read',
    );
    manager.registerHandler(
      SdkEditorDocumentCommands.documentReveal,
      _handleReveal,
      requiredPermission: 'editor:write',
    );
  }

  void _handleActiveGet(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final host = _host;
    final id = host.activeDocumentId;
    if (id == null) {
      _ok(envelope, respond, null);
      return;
    }
    final document = host.registry.byId(id);
    final access = host.access(id);
    _ok(
      envelope,
      respond,
      document?.toJson(revision: access?.revision, isActive: true),
    );
  }

  void _handleGet(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final documentId = _documentId(envelope);
    if (documentId == null) {
      _error(envelope, respond, 'invalid_request', 'Missing documentId');
      return;
    }
    final host = _host;
    final document = host.registry.byId(documentId);
    if (document == null) {
      _error(envelope, respond, 'document_not_found', 'No such document');
      return;
    }
    final access = host.access(documentId);
    _ok(envelope, respond, {
      ...document.toJson(
        revision: access?.revision,
        isActive: host.activeDocumentId == documentId,
      ),
      'lineCount': access?.lineCount,
      'text': access?.text,
    });
  }

  Future<void> _handleSymbols(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final documentId = _documentId(envelope);
    if (documentId == null) {
      _error(envelope, respond, 'invalid_request', 'Missing documentId');
      return;
    }
    final host = _host;
    final access = host.access(documentId);
    if (access == null) {
      _error(envelope, respond, 'document_not_found', 'No such document');
      return;
    }
    final requestRevision = access.revision;
    final future = access.documentSymbols();
    if (future == null) {
      _error(
        envelope,
        respond,
        'unavailable',
        'Language service is unavailable for this document',
      );
      return;
    }
    try {
      final symbols = await future;
      // A stale result must not overwrite a newer query: report the revision
      // the symbols were computed against so the plugin can discard old data.
      final latest = host.access(documentId);
      _ok(envelope, respond, {
        'documentId': documentId,
        'revision': requestRevision,
        'stale': latest == null || latest.revision != requestRevision,
        'symbols': symbols,
      });
    } catch (error) {
      _error(
        envelope,
        respond,
        'internal_error',
        'Symbol query failed: $error',
      );
    }
  }

  void _handleSelectionGet(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final documentId = _documentId(envelope) ?? _host.activeDocumentId;
    if (documentId == null) {
      _error(envelope, respond, 'invalid_request', 'Missing documentId');
      return;
    }
    final access = _host.access(documentId);
    if (access == null) {
      _error(envelope, respond, 'document_not_found', 'No such document');
      return;
    }
    final selection = access.selection;
    final cursor = access.cursor;
    _ok(envelope, respond, {
      'documentId': documentId,
      'start': selection.start,
      'end': selection.end,
      'cursor': {'line': cursor.line, 'column': cursor.column},
    });
  }

  Future<void> _handleReveal(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final documentId = payload['documentId']?.toString();
    if (documentId == null || documentId.isEmpty) {
      _error(envelope, respond, 'invalid_request', 'Missing documentId');
      return;
    }
    final line = payload['line'];
    if (line is! int) {
      _error(envelope, respond, 'invalid_request', 'Missing or invalid line');
      return;
    }
    final access = _host.access(documentId);
    if (access == null) {
      _error(envelope, respond, 'document_not_found', 'No such document');
      return;
    }
    final column = payload['column'];
    try {
      await _host.reveal(
        documentId,
        line: line,
        column: column is int ? column : null,
      );
    } catch (_) {
      _error(
        envelope,
        respond,
        'unavailable',
        'Editor is not ready to reveal the location',
      );
      return;
    }
    _ok(envelope, respond, {'documentId': documentId, 'line': line});
  }

  String? _documentId(Map<String, dynamic> envelope) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final id = payload['documentId']?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  void _ok(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    dynamic data,
  ) {
    respond(
      makeEnvelope(
        type: SdkCommands.responseOk,
        payload: {'data': data},
        replyTo: (envelope['requestId'] ?? envelope['id']).toString(),
      ),
    );
  }

  void _error(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    String code,
    String message,
  ) {
    respond(
      makeEnvelope(
        type: SdkCommands.responseError,
        payload: {'code': code, 'message': message, 'details': null},
        replyTo: (envelope['requestId'] ?? envelope['id']).toString(),
      ),
    );
  }
}

final Provider<SdkEditorDocument> sdkEditorDocumentProvider = Provider(
  SdkEditorDocument.new,
);

/// Resolves documents against the real editor by default.
///
/// Declared as a bare provider that reads the Flutter-backed host lazily; tests
/// override this to inject a fake editor without pulling in code_forge.
final Provider<DocumentHost> documentHostProvider = Provider<DocumentHost>(
  (ref) => ref.read(editorDocumentHostProvider),
);
