import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_outline.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:code_forge/code_forge.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/features/edit_core/lsp_location_dialog.dart';

/// Outline of the symbols in the file the editor is currently showing.
///
/// The behavior mirrors the debug-enhanced plugin's outline: the language
/// server answers `textDocument/documentSymbol` first, and when it is not
/// running or reports no symbols the panel falls back to scanning the source
/// for `class`/`def` definitions ([scanPythonOutline]), so a Python file
/// stays navigable without a server. Edits refresh the tree after a short
/// debounce and saving refreshes it immediately, like the plugin does.
///
/// The panel follows the focused editor group's selected tab rather than
/// owning a file of its own, so switching tabs — or focus, across a split —
/// updates it without any coordination.
class EditorOutlinePanel extends ConsumerStatefulWidget {
  const EditorOutlinePanel({super.key});

  @override
  ConsumerState<EditorOutlinePanel> createState() => _EditorOutlinePanelState();
}

/// Why the panel shows a failure placeholder instead of a tree.
enum _OutlineFailureKind {
  /// Reading the source itself failed.
  error,

  /// The document text is not reachable (no editor backing the tab).
  sourceUnavailable,

  /// The source exceeds the fallback scan's size limits.
  tooLarge,
}

class _EditorOutlinePanelState extends ConsumerState<EditorOutlinePanel> {
  /// Lines whose children are hidden. Keyed by line rather than node identity
  /// so the state survives a refresh that re-parses the same document.
  final Set<int> _collapsedLines = <int>{};

  /// Outline for the file it was loaded from, plus that path.
  ///
  /// Holding the path next to the tree is what lets the panel tell "no symbols
  /// in this file" from "the answer for the previous file is still on screen".
  ({String path, List<DocumentOutlineNode> roots})? _outline;

  String? _loadingPath;

  /// A failed load for a path; only shown while that path is still selected.
  ({String path, _OutlineFailureKind kind, String detail})? _failure;

  /// Guards against out-of-order answers: only the newest request may publish.
  int _requestEpoch = 0;

  /// Edit refresh, debounced like the plugin's document-change handler.
  Timer? _editDebounce;

  /// The controller a change listener is attached to, with the content
  /// version seen at attach time, so selection-only notifications are skipped.
  CodeForgeController? _listenedController;
  VoidCallback? _controllerListener;
  int? _listenedVersion;

  /// The path and controller the outline currently targets, kept for the
  /// debounced edit refresh and the row context menu.
  String? _activePath;
  CodeForgeController? _activeController;

  /// Save tracking: the plugin refreshes the outline when the document is
  /// saved, and a save changes no content, so the trigger is the tab's saved
  /// flag flipping back to true.
  String? _saveWatchedPath;
  bool _saveWatchedSaved = true;

  /// The most recent file tab the panel has seen.
  ///
  /// The outline follows the selected tab, and selecting an outline tab in
  /// the editor bar selects no file at all — there the panel keeps showing
  /// the last file's outline instead of claiming no file is open.
  TabDataValue? _lastFileTab;

  @override
  void dispose() {
    _editDebounce?.cancel();
    _detachControllerListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The outline follows the tab the user is working on: the focused group's
    // selected tab. Watching that provider — rather than one group's
    // controller — is what makes a focus switch between split groups load
    // that group's file, and a selection change inside a group do the same.
    final tab = ref.watch(activeEditorTabProvider).tab;
    final value = tab?.value;
    final fileTab = value is TabDataValue && value.type == 'file'
        ? value
        : null;
    if (fileTab != null) _lastFileTab = fileTab;
    final target = fileTab ?? _lastFileTab;
    if (target == null) {
      return _EmptyState(
        icon: Icons.account_tree_outlined,
        message: translateForWidget(ref, I18nKey.editorOutlineUnavailable),
      );
    }
    final path = target.filePath;
    final controller = target.editorController;
    _syncWatchers(path, target, controller);
    if (_outline?.path != path &&
        _loadingPath != path &&
        _failure?.path != path) {
      _scheduleLoad(path, controller);
    }

    final failure = _failure?.path == path ? _failure : null;
    final roots = failure == null && _outline?.path == path
        ? _outline!.roots
        : const <DocumentOutlineNode>[];
    final rows = _flattenAll(roots);

    Widget body;
    if (failure != null) {
      final isError = failure.kind == _OutlineFailureKind.error;
      final message = switch (failure.kind) {
        _OutlineFailureKind.error => translateForWidgetWithReplacements(
          ref,
          I18nKey.editorOutlineError,
          {'error': failure.detail},
        ),
        _OutlineFailureKind.sourceUnavailable => translateForWidget(
          ref,
          I18nKey.editorOutlineSourceUnavailable,
        ),
        _OutlineFailureKind.tooLarge => translateForWidget(
          ref,
          I18nKey.editorOutlineTooLarge,
        ),
      };
      body = _EmptyState(
        icon: isError ? Icons.error_outline : Icons.account_tree_outlined,
        isError: isError,
        message: message,
      );
    } else if (rows.isEmpty) {
      body = _EmptyState(
        icon: Icons.account_tree_outlined,
        message: translateForWidget(
          ref,
          _loadingPath == path
              ? I18nKey.editorOutlineLoading
              : I18nKey.editorOutlineEmpty,
        ),
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          final node = row.node;
          return _OutlineRow(
            node: node,
            depth: row.depth,
            collapsed: _collapsedLines.contains(node.line),
            onToggle: node.hasChildren
                ? () => setState(() {
                    if (!_collapsedLines.remove(node.line)) {
                      _collapsedLines.add(node.line);
                    }
                  })
                : null,
            onTap: () => revealLspLocation(
              context,
              ref,
              path,
              node.line,
              node.character,
            ),
            onContextMenu: (details) =>
                _showRowMenu(details, node, path, controller),
          );
        },
      );
    }

    return Column(
      children: [
        _Header(
          path: path,
          busy: _loadingPath == path,
          onRefresh: () => _scheduleLoad(path, controller, force: true),
        ),
        const Divider(height: 1),
        Expanded(child: body),
        if (rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                translateForWidget(
                  ref,
                  I18nKey.editorOutlineCount,
                ).replaceAll('{count}', '${rows.length}'),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }

  /// Flattens [roots] honoring the collapse set.
  ///
  /// A local copy of the tree's own flatten is not used here because the panel
  /// needs to collapse at any depth while the tree helper walks a single root.
  List<({DocumentOutlineNode node, int depth})> _flattenAll(
    List<DocumentOutlineNode> roots,
  ) {
    final rows = <({DocumentOutlineNode node, int depth})>[];
    void walk(DocumentOutlineNode node, int depth) {
      rows.add((node: node, depth: depth));
      if (_collapsedLines.contains(node.line)) return;
      for (final child in node.children) {
        walk(child, depth + 1);
      }
    }

    for (final root in roots) {
      walk(root, 0);
    }
    return rows;
  }

  /// Keeps the controller listener and the save watch in step with the tab
  /// that is currently on screen.
  void _syncWatchers(
    String path,
    TabDataValue value,
    CodeForgeController? controller,
  ) {
    _activePath = path;
    _activeController = controller;

    if (!identical(controller, _listenedController)) {
      _detachControllerListener();
      if (controller != null) {
        void listener() => _onControllerChanged(controller);
        _controllerListener = listener;
        _listenedController = controller;
        _listenedVersion = controller.contentVersion;
        controller.addListener(listener);
      }
    }

    if (_saveWatchedPath != path) {
      _saveWatchedPath = path;
      _saveWatchedSaved = value.isSaved;
    } else if (!_saveWatchedSaved && value.isSaved) {
      _saveWatchedSaved = true;
      _scheduleLoad(path, controller, force: true);
    } else {
      _saveWatchedSaved = value.isSaved;
    }
  }

  void _detachControllerListener() {
    final listener = _controllerListener;
    final controller = _listenedController;
    if (listener != null && controller != null) {
      controller.removeListener(listener);
    }
    _controllerListener = null;
    _listenedController = null;
    _listenedVersion = null;
  }

  /// Content changed in the watched editor: schedule the debounced refresh.
  ///
  /// The controller notifies for selection and repaint changes too, so the
  /// content version — not the notification itself — decides whether the
  /// outline is stale.
  void _onControllerChanged(CodeForgeController controller) {
    final version = controller.contentVersion;
    if (version == _listenedVersion) return;
    _listenedVersion = version;
    final path = _activePath;
    if (path == null) return;
    _editDebounce?.cancel();
    _editDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || _activePath != path) return;
      _scheduleLoad(path, _activeController, force: true);
    });
  }

  /// Requests the outline for [path], once per path unless [force] is set.
  ///
  /// The request is fired from build, so the guard matters: without it every
  /// rebuild that arrives before the answer would start another request.
  void _scheduleLoad(
    String path,
    CodeForgeController? controller, {
    bool force = false,
  }) {
    if (!force &&
        (_loadingPath == path ||
            _outline?.path == path ||
            _failure?.path == path)) {
      return;
    }
    _loadingPath = path;
    if (_failure?.path == path) _failure = null;
    unawaited(_load(path, controller));
  }

  /// Loads the outline for [path]: the language server first, the regex scan
  /// of the source when the server has nothing — the plugin's order.
  Future<void> _load(String path, CodeForgeController? controller) async {
    // Yield once: _scheduleLoad can fire from build (tab switch), and a file
    // with no language server would otherwise reach setState inside that
    // same build pass.
    await Future<void>.delayed(Duration.zero);
    final epoch = ++_requestEpoch;

    final lsp = controller?.lspConfig;
    if (lsp != null) {
      try {
        final symbols = await lsp.getDocumentSymbols(path);
        if (!mounted || epoch != _requestEpoch) return;
        final roots = parseDocumentOutline(symbols);
        if (roots.isNotEmpty) {
          setState(() {
            _outline = (path: path, roots: roots);
            _failure = null;
            _loadingPath = null;
          });
          return;
        }
        // An empty answer falls through to the source scan: a server that
        // has not parsed the file yet also reports "no symbols", and the
        // plugin trusts neither that nor a dead service.
      } catch (_) {
        // A dead or unhandshaked server is the in-process spelling of the
        // plugin's "service unavailable": scan the source instead of
        // surfacing an error.
      }
    }

    if (!mounted || epoch != _requestEpoch) return;
    _scanSource(epoch, path, controller);
  }

  void _scanSource(int epoch, String path, CodeForgeController? controller) {
    final String? text;
    try {
      text = controller?.text;
    } catch (error) {
      if (!mounted || epoch != _requestEpoch) return;
      setState(() {
        _failure = (
          path: path,
          kind: _OutlineFailureKind.error,
          detail: '$error',
        );
        _loadingPath = null;
      });
      return;
    }
    if (!mounted || epoch != _requestEpoch) return;
    if (text == null) {
      setState(() {
        _failure = (
          path: path,
          kind: _OutlineFailureKind.sourceUnavailable,
          detail: '',
        );
        _loadingPath = null;
      });
      return;
    }
    try {
      final roots = scanPythonOutline(text);
      if (!mounted || epoch != _requestEpoch) return;
      setState(() {
        _outline = (path: path, roots: roots);
        _failure = null;
        _loadingPath = null;
      });
    } on OutlineSourceTooLarge {
      if (!mounted || epoch != _requestEpoch) return;
      setState(() {
        _failure = (path: path, kind: _OutlineFailureKind.tooLarge, detail: '');
        _loadingPath = null;
      });
    }
  }

  /// The plugin's row context menu: jump to the symbol, or refresh the tree.
  Future<void> _showRowMenu(
    TapUpDetails details,
    DocumentOutlineNode node,
    String path,
    CodeForgeController? controller,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(details.globalPosition, details.globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'reveal',
          child: Row(
            children: [
              const Icon(Icons.open_in_new, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  translateForWidgetWithReplacements(
                    ref,
                    I18nKey.editorOutlineReveal,
                    {'name': node.name},
                  ),
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              const Icon(Icons.refresh, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  translateForWidget(ref, I18nKey.editorOutlineRefresh),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'reveal') {
      await revealLspLocation(context, ref, path, node.line, node.character);
    } else if (action == 'refresh') {
      _scheduleLoad(path, controller, force: true);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.path,
    required this.busy,
    required this.onRefresh,
  });

  final String path;
  final bool busy;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = path.split(RegExp(r'[/\\]')).last;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: [
          Icon(Icons.account_tree_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            tooltip: translateInContext(context, I18nKey.editorOutlineRefresh),
            onPressed: busy ? null : onRefresh,
            icon: busy
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _OutlineRow extends StatelessWidget {
  const _OutlineRow({
    required this.node,
    required this.depth,
    required this.collapsed,
    required this.onToggle,
    required this.onTap,
    required this.onContextMenu,
  });

  final DocumentOutlineNode node;
  final int depth;
  final bool collapsed;
  final VoidCallback? onToggle;
  final VoidCallback onTap;
  final GestureTapUpCallback onContextMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onSecondaryTapUp: onContextMenu,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: 4 + depth * 12,
          end: 8,
          top: 2,
          bottom: 2,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: node.hasChildren
                  ? InkWell(
                      onTap: onToggle,
                      borderRadius: BorderRadius.circular(4),
                      child: Icon(
                        collapsed
                            ? Icons.chevron_right
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : null,
            ),
            Icon(_kindIcon(node.kind), size: 14, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (node.detail.isNotEmpty)
              Flexible(
                child: Text(
                  node.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            Text(
              '${node.line + 1}',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _kindIcon(int kind) {
    return switch (kind) {
      5 || 23 || 10 || 11 => Icons.category_outlined,
      6 || 9 => Icons.functions,
      12 => Icons.play_arrow_outlined,
      13 || 14 => Icons.data_object,
      7 || 8 => Icons.label_outline,
      _ => Icons.subject,
    };
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 28,
              color: isError ? scheme.error : scheme.outline,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
