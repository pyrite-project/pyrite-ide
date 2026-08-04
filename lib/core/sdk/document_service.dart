import 'package:pyrite_ide/core/sdk/document_registry.dart';

/// Editor document topics, emitted by [PluginDocumentService] onto the bus.
abstract class DocumentTopics {
  static const String activeChanged = 'editor.activeDocument.changed';
  static const String opened = 'editor.document.opened';
  static const String changed = 'editor.document.changed';
  static const String saved = 'editor.document.saved';
  static const String closed = 'editor.document.closed';
  static const String selectionChanged = 'editor.document.selection.changed';
}

/// A snapshot of one open document, produced by the Flutter wiring from the
/// real tab model and fed to [PluginDocumentService.syncDocuments].
class DocumentSnapshot {
  const DocumentSnapshot({
    required this.handle,
    required this.filePath,
    required this.isSaved,
    required this.isActive,
    this.languageId,
    this.revision,
  });

  final Object handle;
  final String filePath;
  final bool isSaved;
  final bool isActive;
  final String? languageId;
  final int? revision;
}

/// Read-only access to one document's content, used to serve the query APIs
/// without exposing the editor controller to plugins.
///
/// [documentSymbols] returns null when the language service is unavailable so
/// the API can report a distinct `unavailable` state rather than an empty
/// result.
abstract class DocumentAccess {
  int get revision;
  String get text;
  int get lineCount;
  ({int start, int end}) get selection;
  ({int line, int column}) get cursor;
  Future<List<dynamic>>? documentSymbols();
}

/// Host-side document service: keeps the [DocumentRegistry] in sync with the
/// editor and emits document lifecycle events onto the plugin event bus.
///
/// This class is deliberately free of Flutter and editor dependencies so the
/// diffing and event logic can be unit-tested in isolation. The wiring layer
/// feeds it [DocumentSnapshot]s and content/selection notifications.
class PluginDocumentService {
  PluginDocumentService({
    required void Function(String topic, Map<String, dynamic> payload) emit,
    DocumentRegistry? registry,
  }) : _emit = emit,
       registry = registry ?? DocumentRegistry();

  final void Function(String topic, Map<String, dynamic> payload) _emit;
  final DocumentRegistry registry;

  final Map<String, bool> _savedState = {};
  String? _activeDocumentId;

  /// Reconciles the registry against the current set of open documents,
  /// emitting opened/closed/saved/activeDocument.changed as the set changes.
  ///
  /// [snapshots] must contain only real editor documents (the wiring filters
  /// out non-file tabs). Called on every tab-model change.
  void syncDocuments(List<DocumentSnapshot> snapshots) {
    final liveHandles = {for (final s in snapshots) s.handle};

    // Closed: registered handles no longer present.
    for (final document in registry.all.toList()) {
      if (!liveHandles.contains(document.handle)) {
        registry.unregister(document.handle);
        _savedState.remove(document.documentId);
        _emit(DocumentTopics.closed, {
          'documentId': document.documentId,
          'filePath': document.filePath,
        });
      }
    }

    DocumentSnapshot? activeSnapshot;
    for (final snapshot in snapshots) {
      final existed = registry.byHandle(snapshot.handle) != null;
      final document = registry.register(
        handle: snapshot.handle,
        filePath: snapshot.filePath,
        languageId: snapshot.languageId,
      );
      if (!existed) {
        _savedState[document.documentId] = snapshot.isSaved;
        _emit(DocumentTopics.opened, {
          'documentId': document.documentId,
          'filePath': document.filePath,
          'languageId': ?document.languageId,
          'revision': ?snapshot.revision,
        });
      } else {
        // Detect a save: dirty -> clean transition.
        final wasSaved = _savedState[document.documentId] ?? true;
        if (!wasSaved && snapshot.isSaved) {
          _emit(DocumentTopics.saved, {
            'documentId': document.documentId,
            'filePath': document.filePath,
            'revision': ?snapshot.revision,
          });
        }
        _savedState[document.documentId] = snapshot.isSaved;
      }
      if (snapshot.isActive) activeSnapshot = snapshot;
    }

    _updateActive(activeSnapshot);
  }

  void _updateActive(DocumentSnapshot? activeSnapshot) {
    final handle = activeSnapshot?.handle;
    registry.setActive(handle);
    final active = registry.active;
    if (active?.documentId == _activeDocumentId) return;
    _activeDocumentId = active?.documentId;
    _emit(DocumentTopics.activeChanged, {
      'documentId': active?.documentId,
      'filePath': ?active?.filePath,
      'languageId': ?active?.languageId,
      'revision': ?activeSnapshot?.revision,
    });
  }

  /// Emits an incremental content change for [handle].
  ///
  /// [changedRange] is the dirty region (start/end offsets) so plugins receive
  /// the changed span rather than the whole document body.
  void notifyContentChanged(
    Object handle, {
    required int revision,
    ({int start, int end})? changedRange,
  }) {
    final document = registry.byHandle(handle);
    if (document == null) return;
    _emit(DocumentTopics.changed, {
      'documentId': document.documentId,
      'revision': revision,
      'changes': [
        if (changedRange != null)
          {'start': changedRange.start, 'end': changedRange.end},
      ],
    });
  }

  void notifySelectionChanged(
    Object handle, {
    required int start,
    required int end,
  }) {
    final document = registry.byHandle(handle);
    if (document == null) return;
    _emit(DocumentTopics.selectionChanged, {
      'documentId': document.documentId,
      'selection': {'start': start, 'end': end},
    });
  }

  void clear() {
    registry.clear();
    _savedState.clear();
    _activeDocumentId = null;
  }
}
