import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:code_forge/LSP/lsp.dart';
import 'package:code_forge/code_forge/code_area.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:code_forge/code_forge/styling.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/canonical_path.dart';
import 'package:pyrite_ide/features/edit_core/themed_code_forge.dart';
import 'package:pyrite_ide/core/constants/corner_radius.dart';

/// One jumpable place in a file: a file path plus an optional LSP
/// line/character position inside it.
///
/// This is the single currency the picker dialog understands, so callers do
/// not each have to know how a reference, a definition or a diagnostic spells
/// its location. Callers that do have raw LSP maps can use
/// [LspLocationEntry.fromLspMap].
class LspLocationEntry {
  const LspLocationEntry({
    required this.path,
    this.line,
    this.character,
    this.title,
    this.subtitle,
    this.icon = Icons.description_outlined,
    this.iconColor,
    this.severityRank = 0,
  });

  final String path;
  final int? line;
  final int? character;

  /// Primary list label. Defaults to the file name.
  final String? title;

  /// Secondary list label. Defaults to `line N:C`.
  final String? subtitle;

  final IconData icon;
  final Color? iconColor;

  /// Sort key for callers that mix severities in one list (diagnostics):
  /// lower sorts first, so errors land above warnings. A presentation hint
  /// only; [LspLocationDialog] itself never reorders its input.
  final int severityRank;

  /// Builds an entry from a raw `textDocument/references` /
  /// `textDocument/definition` style location map.
  ///
  /// Returns null for anything that is not a `file:` URI, which is how a
  /// server saying "no location" is filtered out.
  static LspLocationEntry? fromLspMap(Map<dynamic, dynamic> location) {
    final uri = (location['uri'] ?? location['targetUri'])?.toString();
    final parsed = uri == null ? null : Uri.tryParse(uri);
    if (parsed == null || parsed.scheme != 'file') return null;
    final range =
        location['range'] ??
        location['targetSelectionRange'] ??
        location['targetRange'];
    final start = range is Map ? range['start'] : null;
    return LspLocationEntry(
      // Servers on Windows commonly spell the drive lowercase; the entry path
      // is matched against open tabs, which spell it the way the picker did.
      path: canonicalLocalPath(parsed.toFilePath()),
      line: start is Map ? (start['line'] as num?)?.toInt() : null,
      character: start is Map ? (start['character'] as num?)?.toInt() : null,
    );
  }
}

/// Opens [path] in an editor tab, places the caret at ([line], [character])
/// and scrolls it into view.
///
/// Shared by go-to-definition, find-references and the diagnostic picker so
/// every "jump to a place in code" path lands the caret the same way.
Future<void> revealLspLocation(
  BuildContext context,
  WidgetRef ref,
  String path,
  int? line,
  int? character,
) async {
  if (line == null || character == null) return;
  await ref
      .read(tabbedViewControllerProvider.notifier)
      .openFile(context, file: File(path));
  if (!context.mounted) return;
  final targetController =
      ref.read(tabbedViewControllerProvider).selectedTab?.value.editorController
          as CodeForgeController?;
  if (targetController == null) return;
  final offset = (targetController.getLineStartOffset(line) + character).clamp(
    0,
    targetController.length,
  );
  targetController.selection = TextSelection.collapsed(offset: offset);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      targetController.scrollToLine(line);
    } on StateError {
      // The target tab may have been closed before it was mounted.
    }
  });
}

/// Shows the shared "pick a place in code" dialog.
///
/// The dialog embeds a read-only editor preview (the exact same themed
/// [CodeForge] as the main editor) next to a list of [entries]. Landscape puts
/// them side by side, portrait stacks the preview above the list. A single
/// click previews a line's context; the "go" action or a double click jumps
/// to it in the real editor. The first entry is previewed on open.
///
/// Returns when the dialog closes. Jumping is delegated to [onOpen], which
/// runs after the dialog has been popped.
Future<void> showLspLocationDialog(
  BuildContext context,
  WidgetRef ref, {
  required String Function(WidgetRef ref) titleBuilder,
  required List<LspLocationEntry> entries,
  required Future<void> Function(LspLocationEntry entry) onOpen,
  I18nKey emptyKey = I18nKey.editorReferencesEmpty,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => LspLocationDialog(
      titleBuilder: titleBuilder,
      entries: entries,
      emptyKey: emptyKey,
      onOpen: (entry) async {
        Navigator.of(dialogContext).pop();
        await onOpen(entry);
      },
    ),
  );
}

/// The unified jump window: a read-only editor preview plus a selectable list
/// of locations. Used by find-references and by the status bar's error count.
class LspLocationDialog extends ConsumerStatefulWidget {
  const LspLocationDialog({
    super.key,
    required this.titleBuilder,
    required this.entries,
    required this.onOpen,
    this.emptyKey = I18nKey.editorReferencesEmpty,
  });

  final String Function(WidgetRef ref) titleBuilder;
  final List<LspLocationEntry> entries;
  final Future<void> Function(LspLocationEntry entry) onOpen;
  final I18nKey emptyKey;

  @override
  ConsumerState<LspLocationDialog> createState() => _LspLocationDialogState();
}

class _LspLocationDialogState extends ConsumerState<LspLocationDialog> {
  late final CodeForgeController _previewController;
  late final _PreviewLspMirror _lspMirror;
  final Map<String, String?> _contentCache = {};
  var _selectedIndex = 0;
  var _loadingContent = false;
  String? _failedPath;
  String? _previewPath;

  @override
  void initState() {
    super.initState();
    _previewController = CodeForgeController();
    _lspMirror = _PreviewLspMirror(_previewController);
    // Tabs come and go while the dialog is open, so the preview's source of
    // LSP data has to be re-resolved whenever the controller map changes.
    ref.listenManual(editorControllerMapProvider, (_, _) => _syncLspSource());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.entries.isNotEmpty) unawaited(_select(0));
    });
  }

  @override
  void dispose() {
    _lspMirror.dispose();
    _previewController.dispose();
    super.dispose();
  }

  /// Points the preview at the tab that owns [_previewPath], so the preview can
  /// copy its diagnostics and semantic tokens, and lends it that tab's language
  /// server connection for hover. See [_PreviewLspMirror] and
  /// [_applyPreviewLspConfig].
  void _syncLspSource() {
    if (!mounted) return;
    final path = _previewPath;
    final source = path == null
        ? null
        : ref.read(editorControllerMapProvider)[path];
    // Config first, mirror second, and the order matters: assigning
    // `openedFile` clears the diagnostic list, so a mirror that published
    // before that would be wiped. Publishing afterwards is what makes the
    // squiggles survive the path change.
    _applyPreviewLspConfig(path, source?.lspConfig);
    _lspMirror.attach(source);
  }

  /// Gives the preview a working `lspConfig` without letting it open or close
  /// documents on the language server.
  ///
  /// Hover is the one LSP feature that cannot be mirrored: it needs a live
  /// `textDocument/hover` request, and [LspConfig.getHover] answers with an
  /// empty string whenever there is no config. So the preview borrows the very
  /// same [LspConfig] instance the open tab already uses - which keeps one
  /// server connection per tab and spawns no extra language server - and only
  /// issues read-only requests with it.
  ///
  /// Sharing is only safe because the preview never syncs the document, and the
  /// ordering below is what guarantees that. Everything that writes to the
  /// server goes through the `openedFile` setter or the typing debounce:
  ///
  ///  * The config is detached *before* `openedFile` changes. Had it still been
  ///    attached, the setter would have sent `didClose` for the previous file on
  ///    that file's own connection - the one its real editor tab is using -
  ///    which takes that tab's diagnostics down with it.
  ///  * `openedFile` is pre-set while detached, so the editor widget finds it
  ///    already equal to its `filePath` and skips its own assignment instead of
  ///    firing `didOpen` for a document that is already open on that server.
  ///
  /// The `if` also keeps the file re-read in the setter from clobbering the
  /// live buffer when only the tab map changed and the previewed path did not.
  void _applyPreviewLspConfig(String? path, LspConfig? config) {
    if (path == null) {
      _previewController.lspConfig = null;
      return;
    }
    if (_previewController.openedFile != path) {
      _previewController.lspConfig = null;
      try {
        _previewController.openedFile = path;
      } catch (_) {
        // Missing or unreadable file; the preview falls back to its
        // "unavailable" message and never gets as far as requesting hover.
      }
    }
    _previewController.lspConfig = config;
  }

  /// Returns the file's content, preferring the live buffer of an open tab
  /// (so unsaved edits preview correctly) and caching disk reads.
  Future<String?> _loadContent(String path) async {
    if (_contentCache.containsKey(path)) return _contentCache[path];
    final liveBuffer = ref.read(editorControllerMapProvider)[path];
    if (liveBuffer != null) {
      return _contentCache[path] = liveBuffer.text;
    }
    try {
      final file = File(path);
      if (!await file.exists()) return _contentCache[path] = null;
      return _contentCache[path] = await file.readAsString();
    } catch (_) {
      return _contentCache[path] = null;
    }
  }

  Future<void> _select(int index) async {
    if (index < 0 || index >= widget.entries.length) return;
    final entry = widget.entries[index];
    setState(() {
      _selectedIndex = index;
      _loadingContent = true;
      _previewPath = entry.path;
    });
    _syncLspSource();
    final content = await _loadContent(entry.path);
    if (!mounted) return;
    if (content == null) {
      setState(() {
        _loadingContent = false;
        _failedPath = entry.path;
      });
      return;
    }
    _showPreviewContent(entry, content);
    setState(() {
      _loadingContent = false;
      _failedPath = null;
    });
  }

  /// Puts [content] into the preview, highlights [entry]'s line and places the
  /// caret there.
  void _showPreviewContent(LspLocationEntry entry, String content) {
    if (_previewController.text != content) {
      _previewController.text = content;
    }
    _previewController.clearLineDecorations();
    final targetLine = entry.line ?? 0;
    try {
      _previewController.addLineDecoration(
        LineDecoration(
          id: 'lsp-location-highlight',
          startLine: targetLine,
          endLine: targetLine,
          type: LineDecorationType.background,
          color: Theme.of(context).colorScheme.primary.withAlpha(45),
        ),
      );
    } catch (_) {}
    var offset = _previewController.getLineStartOffset(targetLine);
    offset = (offset + (entry.character ?? 0))
        .clamp(0, _previewController.text.length)
        .toInt();
    _previewController.selection = TextSelection.collapsed(offset: offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _previewController.scrollToLine(targetLine);
      } on StateError {
        // Preview not mounted yet.
      }
      // Changing the previewed path remounts the editor, and a remount makes
      // the controller re-read the file - which drops the mirrored
      // diagnostics. Restore them once the new editor exists.
      if (mounted) _lspMirror.resync();
    });
  }

  void _openSelected() {
    if (widget.entries.isEmpty) return;
    unawaited(widget.onOpen(widget.entries[_selectedIndex]));
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    // Portrait stacks preview above the list; landscape puts them side by side.
    final isPortrait = screenSize.height > screenSize.width;
    return AlertDialog(
      title: Text(widget.titleBuilder(ref)),
      content: SizedBox(
        width: min(920.0, screenSize.width * 0.92),
        height: min(isPortrait ? 620.0 : 540.0, screenSize.height * 0.8),
        child: widget.entries.isEmpty
            ? Center(child: Text(translateForWidget(ref, widget.emptyKey)))
            : isPortrait
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildPreview(context)),
                  const Divider(height: 24),
                  SizedBox(height: 220, child: _buildList(context)),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildPreview(context)),
                  const VerticalDivider(width: 20),
                  SizedBox(width: 300, child: _buildList(context)),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text(translateForWidget(ref, I18nKey.commonCancel)),
        ),
        if (widget.entries.isNotEmpty)
          FilledButton(
            onPressed: _openSelected,
            child: Text(
              translateForWidget(ref, I18nKey.editorJumpGoToLocation),
            ),
          ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    final entry =
        widget.entries[_selectedIndex.clamp(0, widget.entries.length - 1)];
    final failedToLoad = _failedPath == entry.path;
    return Container(
      // Clip the editor to the rounded shape; the border is drawn via
      // foregroundDecoration so it paints ON TOP of the opaque editor
      // background. A `decoration` border would be painted first and then
      // covered by the child on straight edges, leaving only the corner
      // arcs visible - which looked like a notched corner.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: context.outerCorners),
      foregroundDecoration: BoxDecoration(
        borderRadius: context.outerCorners,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: failedToLoad
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  translateForWidget(
                    ref,
                    I18nKey.editorReferencesPreviewUnavailable,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Stack(
              children: [
                // The editor only reads a new diagnostic list when it is
                // rebuilt, so the rebuild is driven by the mirror's revision
                // instead of by the (never changing) controller text.
                ValueListenableBuilder<int>(
                  valueListenable: _lspMirror.revision,
                  builder: (context, _, _) => buildThemedCodeForge(
                    context,
                    ref,
                    controller: _previewController,
                    filePath: entry.path,
                    rebuildKey: 'lsp-location-preview:${entry.path}',
                    readOnly: true,
                    // `readOnly` already blocks editing, but not the context
                    // menu. Swallowing the menu here keeps the preview
                    // strictly non-interactive.
                    contextMenuBuilder: (context, details) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => details.close(),
                      );
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                if (_loadingContent)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }

  Widget _buildList(BuildContext context) {
    return ListView.builder(
      itemCount: widget.entries.length,
      itemBuilder: (context, index) {
        final entry = widget.entries[index];
        return GestureDetector(
          onTap: () => unawaited(_select(index)),
          // Double click closes the dialog and jumps ([widget.onOpen] pops
          // the dialog first).
          onDoubleTap: () => unawaited(widget.onOpen(entry)),
          child: ListTile(
            dense: true,
            selected: index == _selectedIndex,
            selectedTileColor: Theme.of(
              context,
            ).colorScheme.primary.withAlpha(30),
            leading: Icon(entry.icon, size: 18, color: entry.iconColor),
            title: Text(
              entry.title ?? _fileNameOf(entry.path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              entry.subtitle ?? _defaultSubtitle(entry),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }

  String _defaultSubtitle(LspLocationEntry entry) {
    final line = entry.line == null ? '?' : '${entry.line! + 1}';
    final character = entry.character == null ? '?' : '${entry.character}';
    return '${_fileNameOf(entry.path)}  $line:$character';
  }
}

/// The file name of [path], accepting either path separator.
String _fileNameOf(String path) => path.split(RegExp(r'[\\/]')).last;

/// Mirrors the LSP decorations of an open tab onto the read-only preview.
///
/// The preview controller is deliberately created *without* an `LspConfig`.
/// A second client would `didOpen` the same document again, and moving the
/// preview to another file would `didClose` the one the real editor is using,
/// taking that tab's diagnostics down with it. So instead the preview copies
/// what the already-connected tab already knows: the diagnostics behind the
/// error/warning squiggles, and the semantic tokens.
class _PreviewLspMirror {
  _PreviewLspMirror(this._preview);

  final CodeForgeController _preview;

  /// Bumped when the mirrored data changes, so that the preview editor is
  /// rebuilt and picks the new diagnostic list up.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  CodeForgeController? _source;
  List<LspErrors>? _diagnostics;
  List<LspSemanticToken>? _tokens;
  bool _publishScheduled = false;
  bool _disposed = false;

  /// The highest semantic token version published to the preview so far.
  ///
  /// Tracked as an observed high-water mark instead of a plain counter because
  /// the preview editor publishes viewport tokens on its own (it borrows a real
  /// `lspConfig` for hover, and `_scheduleVisibleSemanticTokens` writes through
  /// the controller). Those writes carry the controller's own version, which
  /// this class never sees, so incrementing a local counter from zero would
  /// start below a version the renderer had already applied - and the renderer
  /// silently drops any version older than the last one it took.
  int _semanticVersion = 0;

  /// Mirrors [source]'s LSP data, or clears the preview when it is null.
  void attach(CodeForgeController? source) {
    if (identical(source, _source)) return;
    _source?.displayChanges.removeListener(_sync);
    _source?.semanticTokens.removeListener(_sync);
    _source = source;
    _source?.displayChanges.addListener(_sync);
    _source?.semanticTokens.addListener(_sync);
    _sync();
  }

  /// Re-publishes the mirrored data even when it is unchanged, for the case
  /// where the editor dropped it behind our back.
  void resync() {
    _sync(force: true);
  }

  void _sync({bool force = false}) {
    final source = _source;
    final diagnostics = source?.diagnostics;
    final tokens = source?.semanticTokens.value.$1;
    // `displayChanges` also fires on every caret move, so only a real change
    // of the mirrored data may rebuild the preview.
    if (!force &&
        identical(diagnostics, _diagnostics) &&
        identical(tokens, _tokens)) {
      return;
    }
    _diagnostics = diagnostics;
    _tokens = tokens;
    if (_publishScheduled) return;
    _publishScheduled = true;

    void publish() {
      _publishScheduled = false;
      if (_disposed) return;
      _preview.diagnosticsNotifier.value = _diagnostics ?? const [];
      // The version has to be strictly increasing or the renderer drops the
      // write (it ignores any version older than the last one it applied), and
      // it is counted from whatever the preview controller has already handed
      // out rather than from a counter private to this class: the preview
      // borrows a real `lspConfig` for hover, so the editor itself also
      // publishes viewport tokens through `publishSemanticTokens`, which
      // increments the same sequence. A private counter would collide with
      // those and the two publishers would overwrite each other.
      // Stay above every version the preview has already published, whichever
      // of the two publishers wrote it.
      _semanticVersion = _preview.semanticTokens.value.$2 + 1;
      _preview.semanticTokens.value = (_tokens, _semanticVersion);
      revision.value++;
    }

    // Both notifiers are read by the editor widget, which repaints through
    // `setState`; apply them outside the build phase, exactly as the
    // controller's own `displayChanges` does.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      publish();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => publish());
    }
  }

  void dispose() {
    _disposed = true;
    _source?.displayChanges.removeListener(_sync);
    _source?.semanticTokens.removeListener(_sync);
    _source = null;
    revision.dispose();
  }
}
