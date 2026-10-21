import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_outline.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:code_forge/code_forge.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/features/edit_core/lsp_location_dialog.dart';

/// Outline of the symbols in the file the editor is currently showing.
///
/// The language server has answered `textDocument/documentSymbol` since the
/// client was written, but nothing in the IDE ever asked for it: the only
/// consumer was the plugin SDK. A hierarchical symbol list is the cheapest
/// way to make a long Python file navigable, and it needs no new server work
/// — just a request and a list.
///
/// The panel follows the selected tab rather than owning a file of its own, so
/// switching tabs updates it without any coordination.
class EditorOutlinePanel extends ConsumerStatefulWidget {
  const EditorOutlinePanel({super.key});

  @override
  ConsumerState<EditorOutlinePanel> createState() => _EditorOutlinePanelState();
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tab = ref.watch(tabbedViewControllerProvider).selectedTab;
    final value = tab?.value;
    final path = value is TabDataValue && value.type == 'file'
        ? value.filePath
        : null;
    final controller = value is TabDataValue ? value.editorController : null;

    if (path == null) {
      return _EmptyState(
        icon: Icons.account_tree_outlined,
        message: translateForWidget(ref, I18nKey.editorOutlineUnavailable),
      );
    }
    if (_outline?.path != path) {
      _scheduleLoad(path, controller);
    }

    final roots = _outline?.path == path
        ? _outline!.roots
        : const <DocumentOutlineNode>[];
    final rows = _flattenAll(roots);

    return Column(
      children: [
        _Header(
          path: path,
          busy: _loadingPath == path,
          onRefresh: () => _scheduleLoad(path, controller, force: true),
        ),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? _EmptyState(
                  icon: Icons.account_tree_outlined,
                  message: translateForWidget(
                    ref,
                    _loadingPath == path
                        ? I18nKey.editorOutlineLoading
                        : I18nKey.editorOutlineEmpty,
                  ),
                )
              : ListView.builder(
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
                    );
                  },
                ),
        ),
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

  /// Requests the outline for [path], once per path unless [force] is set.
  ///
  /// The request is fired from build, so the guard matters: without it every
  /// rebuild that arrives before the answer would start another request.
  void _scheduleLoad(
    String path,
    CodeForgeController? controller, {
    bool force = false,
  }) {
    if (!force && (_loadingPath == path || _outline?.path == path)) return;
    _loadingPath = path;
    unawaited(_load(path, controller));
  }

  Future<void> _load(String path, CodeForgeController? controller) async {
    final lsp = controller?.lspConfig;
    if (lsp == null) {
      if (!mounted) return;
      setState(() {
        _outline = (path: path, roots: const []);
        _loadingPath = null;
      });
      return;
    }
    try {
      final symbols = await lsp.getDocumentSymbols(path);
      if (!mounted || _loadingPath != path) return;
      setState(() {
        _outline = (path: path, roots: parseDocumentOutline(symbols));
        _loadingPath = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _outline = (path: path, roots: const []);
        _loadingPath = null;
      });
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
            tooltip: '',
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
  });

  final DocumentOutlineNode node;
  final int depth;
  final bool collapsed;
  final VoidCallback? onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
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
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: scheme.outline),
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
