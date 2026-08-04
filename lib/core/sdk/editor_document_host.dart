import 'dart:async';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/app/routes.dart' show edit, routes;
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/sdk/api/document_api.dart';
import 'package:pyrite_ide/core/sdk/document_registry.dart';
import 'package:pyrite_ide/core/sdk/document_service.dart';
import 'package:pyrite_ide/core/sdk/environment_notifier_provider.dart';
import 'package:pyrite_ide/core/sdk/environment_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:tabbed_view/tabbed_view.dart';

/// [DocumentAccess] backed by a live [CodeForgeController].
class _ControllerAccess implements DocumentAccess {
  _ControllerAccess(this._controller, this._filePath);

  final CodeForgeController _controller;
  final String _filePath;

  @override
  int get revision => _controller.contentVersion;

  @override
  String get text => _controller.text;

  @override
  int get lineCount => _controller.lineCount;

  @override
  ({int start, int end}) get selection {
    final sel = _controller.selection;
    return (start: sel.start, end: sel.end);
  }

  @override
  ({int line, int column}) get cursor {
    final offset = _controller.selection.baseOffset.clamp(
      0,
      _controller.text.length,
    );
    final line = _controller.getLineAtOffset(offset);
    final column = offset - _controller.getLineStartOffset(line);
    return (line: line, column: column);
  }

  @override
  Future<List<dynamic>>? documentSymbols() {
    final lsp = _controller.lspConfig;
    if (lsp == null) return null;
    return lsp.getDocumentSymbols(_filePath);
  }
}

/// Reveals a location after the editor render object has attached its scrolling
/// callback. Compact layouts temporarily unmount editors while another page is
/// visible, so the first failed attempt can trigger navigation and then retry.
@visibleForTesting
Future<void> retryEditorReveal({
  required void Function() reveal,
  FutureOr<void> Function()? onEditorUnavailable,
  Future<void> Function()? waitForRetry,
  int maxAttempts = 120,
}) async {
  final wait =
      waitForRetry ??
      () => Future<void>.delayed(const Duration(milliseconds: 16));
  var prepared = false;

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      reveal();
      return;
    } on StateError catch (error) {
      if (!error.toString().contains('Editor is not initialized')) rethrow;
      if (!prepared) {
        prepared = true;
        await onEditorUnavailable?.call();
      }
    }
    await wait();
  }

  throw StateError('Editor did not initialize before reveal timed out');
}

@visibleForTesting
bool layoutNeedsDedicatedEditorRoute(LayoutMode layoutMode) =>
    layoutMode != LayoutMode.desktop;

Future<void> _revealControllerWhenReady(
  CodeForgeController controller, {
  required int line,
  int? column,
  FutureOr<void> Function()? onEditorUnavailable,
}) async {
  if (line < 0 || line >= controller.lineCount) return;
  await retryEditorReveal(
    reveal: () {
      controller.scrollToLine(line);
      final lineStart = controller.getLineStartOffset(line);
      final offset = column == null
          ? lineStart
          : (lineStart + column).clamp(0, controller.findLineEnd(lineStart));
      controller.setSelectionSilently(TextSelection.collapsed(offset: offset));
    },
    onEditorUnavailable: onEditorUnavailable,
  );
}

/// Bridges the real editor tab model to [PluginDocumentService] and serves the
/// document query APIs.
///
/// It listens to [tabbedViewControllerProvider], keeps the document registry in
/// sync, attaches a per-controller listener to split content vs selection
/// changes, and emits lifecycle events onto the plugin event bus.
class EditorDocumentHost implements DocumentHost {
  EditorDocumentHost(this._ref) {
    _service = PluginDocumentService(
      emit: (topic, payload) =>
          _ref.read(pluginEventBusProvider).emit(topic, payload),
    );
    _subscription = _ref.listen<TabbedViewController>(
      tabbedViewControllerProvider,
      (_, next) => _onTabsChanged(next),
      fireImmediately: true,
    );
  }

  final Ref _ref;
  late final PluginDocumentService _service;
  late final ProviderSubscription<TabbedViewController> _subscription;

  /// Per-controller listeners, so we can detach on close.
  final Map<CodeForgeController, VoidCallback> _listeners = {};
  final Map<CodeForgeController, int> _lastVersion = {};

  @override
  DocumentRegistry get registry => _service.registry;

  @override
  String? get activeDocumentId => registry.active?.documentId;

  @override
  DocumentAccess? access(String documentId) {
    final document = registry.byId(documentId);
    final controller = document?.handle;
    if (controller is! _DocumentHandle) return null;
    return _ControllerAccess(controller.controller, controller.filePath);
  }

  @override
  Future<void> reveal(
    String documentId, {
    required int line,
    int? column,
  }) async {
    final document = registry.byId(documentId);
    final handle = document?.handle;
    if (handle is! _DocumentHandle) {
      throw StateError('Document is no longer open');
    }

    final tabs = _ref.read(tabbedViewControllerProvider).tabs;
    final index = tabs.indexOf(handle.tab);
    if (index < 0) throw StateError('Document tab is no longer open');
    if (!identical(
      _ref.read(tabbedViewControllerProvider).selectedTab,
      handle.tab,
    )) {
      _ref
          .read(tabbedViewControllerProvider.notifier)
          .onTabTap(handle.tab, index);
    }

    await _revealControllerWhenReady(
      handle.controller,
      line: line,
      column: column,
      onEditorUnavailable: () {
        final layoutMode = _ref
            .read(environmentNotifierProvider)
            .snapshot
            .layoutMode;
        if (layoutNeedsDedicatedEditorRoute(layoutMode) &&
            !routes.state.matchedLocation.startsWith(edit)) {
          routes.go(edit);
        }
      },
    );
  }

  void _onTabsChanged(TabbedViewController controller) {
    final snapshots = <DocumentSnapshot>[];
    final selected = controller.selectedTab;
    for (final tab in controller.tabs) {
      final value = tab.value;
      if (value is! TabDataValue || value.type != 'file') continue;
      final editor = value.editorController;
      if (editor == null) continue;
      final handle = _handleFor(tab, value, editor);
      snapshots.add(
        DocumentSnapshot(
          handle: handle,
          filePath: value.filePath,
          isSaved: value.isSaved,
          isActive: identical(tab, selected),
          languageId: _languageFor(value.filePath),
          revision: editor.contentVersion,
        ),
      );
      _attachListener(handle, editor);
    }
    _service.syncDocuments(snapshots);
    _pruneListeners();
  }

  /// A stable handle keyed by the tab identity (per scout guidance: TabData is
  /// reused across controller rebuilds, so it is a stable document key).
  final Map<TabData, _DocumentHandle> _handles = {};

  _DocumentHandle _handleFor(
    TabData tab,
    TabDataValue value,
    CodeForgeController editor,
  ) {
    final existing = _handles[tab];
    if (existing != null && identical(existing.controller, editor)) {
      return existing;
    }
    final handle = _DocumentHandle(tab, editor, value.filePath);
    _handles[tab] = handle;
    return handle;
  }

  void _attachListener(_DocumentHandle handle, CodeForgeController editor) {
    if (_listeners.containsKey(editor)) return;
    _lastVersion[editor] = editor.contentVersion;
    void listener() {
      final version = editor.contentVersion;
      final lastVersion = _lastVersion[editor] ?? version;
      if (version != lastVersion) {
        _lastVersion[editor] = version;
        _service.notifyContentChanged(
          handle,
          revision: version,
          changedRange: editor.dirtyRegion == null
              ? null
              : (
                  start: editor.dirtyRegion!.start,
                  end: editor.dirtyRegion!.end,
                ),
        );
      } else if (editor.selectionOnly) {
        final sel = editor.selection;
        _service.notifySelectionChanged(handle, start: sel.start, end: sel.end);
      }
    }

    editor.addListener(listener);
    _listeners[editor] = listener;
  }

  /// Detaches listeners for controllers no longer backing an open document.
  void _pruneListeners() {
    final live = {
      for (final document in registry.all)
        if (document.handle is _DocumentHandle)
          (document.handle as _DocumentHandle).controller,
    };
    _listeners.removeWhere((editor, listener) {
      if (live.contains(editor)) return false;
      editor.removeListener(listener);
      _lastVersion.remove(editor);
      return true;
    });
    _handles.removeWhere((tab, handle) => !live.contains(handle.controller));
  }

  String? _languageFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.py') || lower.endsWith('.pyi')) return 'python';
    if (lower.endsWith('.dart')) return 'dart';
    if (lower.endsWith('.md')) return 'markdown';
    if (lower.endsWith('.json')) return 'json';
    return null;
  }

  void dispose() {
    for (final entry in _listeners.entries) {
      entry.key.removeListener(entry.value);
    }
    _listeners.clear();
    _lastVersion.clear();
    _handles.clear();
    _service.clear();
    _subscription.close();
  }
}

/// Opaque registry handle wrapping the controller and its file path.
class _DocumentHandle {
  _DocumentHandle(this.tab, this.controller, this.filePath);

  final TabData tab;
  final CodeForgeController controller;
  final String filePath;
}

final Provider<EditorDocumentHost> editorDocumentHostProvider = Provider((ref) {
  final host = EditorDocumentHost(ref);
  ref.onDispose(host.dispose);
  return host;
});
