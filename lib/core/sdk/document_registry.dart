/// A document tracked by the host and exposed to plugins.
///
/// [documentId] is minted by the registry and stays stable for the lifetime of
/// one open document; closing and reopening the same file yields a new id, so a
/// plugin can never confuse two distinct editing sessions of the same path.
class RegisteredDocument {
  const RegisteredDocument({
    required this.documentId,
    required this.handle,
    required this.filePath,
    this.languageId,
  });

  final String documentId;

  /// Opaque host-side identity of the open document (e.g. the editor tab).
  /// The registry never inspects it; the wiring layer maps it back to a
  /// controller.
  final Object handle;
  final String filePath;
  final String? languageId;

  Map<String, dynamic> toJson({int? revision, bool isActive = false}) => {
    'documentId': documentId,
    'filePath': filePath,
    'languageId': ?languageId,
    'revision': ?revision,
    'isActive': isActive,
  };
}

/// Assigns stable ids to open documents and tracks which one is active.
///
/// This is a pure model with no editor dependency so it can be unit-tested in
/// isolation. The wiring layer (T13-b) keeps it in sync with the real tab
/// model and resolves [RegisteredDocument.handle] back to a live controller.
class DocumentRegistry {
  DocumentRegistry({String Function()? idFactory})
    : _idFactory = idFactory ?? _defaultIdFactory;

  final String Function() _idFactory;
  final Map<Object, RegisteredDocument> _byHandle = {};
  final Map<String, RegisteredDocument> _byId = {};
  Object? _activeHandle;

  static int _counter = 0;
  static String _defaultIdFactory() => 'doc-${++_counter}';

  /// Registers [handle] if new and returns its document. Re-registering an
  /// existing handle returns the same document (id is minted once), updating
  /// the path and language when they change.
  RegisteredDocument register({
    required Object handle,
    required String filePath,
    String? languageId,
  }) {
    final existing = _byHandle[handle];
    if (existing != null) {
      final pathChanged = existing.filePath != filePath;
      final languageChanged =
          languageId != null && languageId != existing.languageId;
      if (!pathChanged && !languageChanged) return existing;
      final updated = RegisteredDocument(
        documentId: existing.documentId,
        handle: handle,
        filePath: filePath,
        // A move or rename keeps the same open document but changes what its
        // path -- and possibly its language -- resolves to. The snapshot's
        // language wins when the path changed, including null: renaming a
        // .py tab to .txt must drop the stale 'python'.
        languageId: languageId,
      );
      _byHandle[handle] = updated;
      _byId[updated.documentId] = updated;
      return updated;
    }
    final document = RegisteredDocument(
      documentId: _idFactory(),
      handle: handle,
      filePath: filePath,
      languageId: languageId,
    );
    _byHandle[handle] = document;
    _byId[document.documentId] = document;
    return document;
  }

  /// Removes [handle] if present and returns the document that was dropped.
  RegisteredDocument? unregister(Object handle) {
    final removed = _byHandle.remove(handle);
    if (removed != null) _byId.remove(removed.documentId);
    if (identical(_activeHandle, handle)) _activeHandle = null;
    return removed;
  }

  RegisteredDocument? byId(String documentId) => _byId[documentId];
  RegisteredDocument? byHandle(Object handle) => _byHandle[handle];

  /// The active document, or null when no tracked document is focused.
  RegisteredDocument? get active {
    final handle = _activeHandle;
    return handle == null ? null : _byHandle[handle];
  }

  /// Marks [handle] active. A handle that is not registered clears the active
  /// document rather than pointing at something plugins can't query.
  void setActive(Object? handle) {
    if (handle == null || !_byHandle.containsKey(handle)) {
      _activeHandle = _byHandle.containsKey(handle) ? handle : null;
      return;
    }
    _activeHandle = handle;
  }

  Iterable<RegisteredDocument> get all => _byHandle.values;
  int get length => _byHandle.length;

  void clear() {
    _byHandle.clear();
    _byId.clear();
    _activeHandle = null;
  }
}
