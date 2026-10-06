import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:code_forge/code_forge/code_area.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:code_forge/code_forge/find_controller.dart';
import 'package:code_forge/code_forge/undo_redo.dart';
import 'package:code_forge/code_forge/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3_floating_toolbar/m3_floating_toolbar.dart';
import 'package:m3_floating_toolbar/m3_floating_toolbar_action.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_tree.dart';
import 'package:pyrite_ide/core/services/file/board_provider.dart';
import 'package:pyrite_ide/core/services/file/canonical_path.dart';
import 'package:pyrite_ide/core/services/file/local_tree.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/serial/active_device_provider.dart';
import 'package:pyrite_ide/shared/dialog_form_fields.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';
import 'package:pyrite_ide/features/edit_core/editor_language.dart';
import 'package:pyrite_ide/features/edit_core/line_comment.dart';
import 'package:pyrite_ide/features/edit_core/lsp_context_menu_actions.dart';
import 'package:pyrite_ide/features/edit_core/lsp_location_dialog.dart';
import 'package:pyrite_ide/features/edit_core/lsp_text_edits.dart';
import 'package:pyrite_ide/features/edit_core/themed_code_forge.dart';
import 'package:pyrite_ide/core/constants/corner_radius.dart';

class EditCore extends ConsumerStatefulWidget {
  const EditCore({
    super.key,
    required this.file,
    required this.editorController,
    this.undoController,
  });
  final File file;
  final CodeForgeController editorController;
  final UndoRedoController? undoController;

  @override
  ConsumerState<EditCore> createState() => _EditCoreState();
}

class _EditCoreState extends ConsumerState<EditCore> {
  late FindController _findController;

  @override
  void initState() {
    super.initState();
    // Providers must exist before build watches them; creating them here
    // keeps build free of side effects.
    ensurePendingFileProviders(widget.file.path);
    _findController = FindController(widget.editorController);
  }

  @override
  void didUpdateWidget(covariant EditCore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editorController != widget.editorController) {
      _findController.dispose();
      _findController = FindController(widget.editorController);
    }
  }

  @override
  void dispose() {
    _findController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingUploadProviderMap[widget.file.path]!);
    final pendingDownload = ref.watch(
      pendingDownloadProviderMap[widget.file.path]!,
    );
    final confirmAct = ref.watch(confirmShortcutProvider);
    final cancelAct = ref.watch(cancelShortcutProvider);

    final bindings = <ShortcutActivator, VoidCallback>{
      SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
        saveFile(context, ref);
      },
      SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
        saveFile(context, ref);
      },
      SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () {
        ref.read(fileProvider.notifier).saveCurrentFileAs();
      },
      SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true): () {
        ref.read(fileProvider.notifier).saveCurrentFileAs();
      },
      SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
        ref.read(tabbedViewControllerProvider.notifier).createFile();
      },
      SingleActivator(LogicalKeyboardKey.keyN, meta: true): () {
        ref.read(tabbedViewControllerProvider.notifier).createFile();
      },
      SingleActivator(LogicalKeyboardKey.keyO, control: true): () {
        ref.read(tabbedViewControllerProvider.notifier).openFile(context);
      },
      SingleActivator(LogicalKeyboardKey.keyO, meta: true): () {
        ref.read(tabbedViewControllerProvider.notifier).openFile(context);
      },
      SingleActivator(LogicalKeyboardKey.keyU, control: true): () {
        ref.read(fileProvider.notifier).uploadSelectedLocalFileItem(context);
      },
      SingleActivator(LogicalKeyboardKey.keyU, meta: true): () {
        ref.read(fileProvider.notifier).uploadSelectedLocalFileItem(context);
      },
      SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
        runCurrentFile(context, ref);
      },
      SingleActivator(LogicalKeyboardKey.keyR, meta: true): () {
        runCurrentFile(context, ref);
      },
      SingleActivator(LogicalKeyboardKey.f12): () {
        _goToDefinition(context, ref);
      },
      // The engine declares these keys but returns a handled event for them
      // whether or not the host supplied a handler, so the meta variants are
      // bound here rather than in CodeForgeKeyboardShortcuts: that table has
      // one activator per action and cannot express "F12 or Cmd+F12".
      if (usesCommandShortcut)
        const SingleActivator(LogicalKeyboardKey.f12, meta: true): () {
          _goToDefinition(context, ref);
        },
      if (usesCommandShortcut)
        const SingleActivator(
          LogicalKeyboardKey.f12,
          meta: true,
          shift: true,
        ): () {
          unawaited(_findReferences(context, ref));
        },
      if (usesCommandShortcut)
        const SingleActivator(
          LogicalKeyboardKey.f12,
          meta: true,
          control: true,
        ): () {
          unawaited(
            _goToDefinition(
              context,
              ref,
              method: 'textDocument/implementation',
            ),
          );
        },
      SingleActivator(LogicalKeyboardKey.keyG, control: true): () {
        _goToLine(context, ref);
      },
      SingleActivator(LogicalKeyboardKey.keyG, meta: true): () {
        _goToLine(context, ref);
      },
      SingleActivator(LogicalKeyboardKey.f2): () {
        _renameSymbol(context, ref);
      },
      SingleActivator(LogicalKeyboardKey.f3): () {
        _findController.next();
      },
      SingleActivator(LogicalKeyboardKey.f3, shift: true): () {
        _findController.previous();
      },
      for (final activator in findActivators())
        activator: () {
          _openFind();
        },
      for (final activator in replaceActivators())
        activator: () {
          _openFind(replace: true);
        },
      for (final activator in toggleCommentActivators())
        activator: () {
          _toggleLineComment();
        },
    };

    if (pending != null || pendingDownload != null) {
      // A recording that cannot be parsed is dropped rather than bound to a
      // wrong key, so the confirm action stays unreachable instead of firing
      // on Enter.
      final confirmActivator = stringToActivator(confirmAct);
      if (confirmActivator != null) {
        bindings[confirmActivator] = () => _handleConfirm(context, ref);
      }
      final cancelActivator = stringToActivator(cancelAct);
      if (cancelActivator != null) {
        bindings[cancelActivator] = () => _handleCancel(context, ref);
      }
    }

    return Focus(
      canRequestFocus: false,
      child: CallbackShortcuts(
        bindings: bindings,
        child: Stack(
          children: [
            body(context, ref),
            if (pending != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: M3FloatingToolbar(
                    actions: [
                      M3FloatingToolbarAction(
                        icon: Icons.close,
                        label: translateForWidget(ref, I18nKey.commonCancel),
                        onPressed: () => _handleCancel(context, ref),
                        semanticLabel: translateForWidget(
                          ref,
                          I18nKey.commonCancel,
                        ),
                      ),
                      M3FloatingToolbarAction(
                        icon: Icons.cloud_upload,
                        label: translateForWidget(
                          ref,
                          I18nKey.editorConfirmUpload,
                        ),
                        onPressed: () => _confirmUpload(ref, pending, context),
                        semanticLabel: translateForWidget(
                          ref,
                          I18nKey.editorConfirmUpload,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (pendingDownload != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: M3FloatingToolbar(
                    actions: [
                      M3FloatingToolbarAction(
                        icon: Icons.close,
                        label: translateForWidget(ref, I18nKey.commonCancel),
                        onPressed: () => _handleCancel(context, ref),
                        semanticLabel: translateForWidget(
                          ref,
                          I18nKey.commonCancel,
                        ),
                      ),
                      M3FloatingToolbarAction(
                        icon: Icons.cloud_download,
                        label: translateForWidget(
                          ref,
                          I18nKey.editorConfirmDownload,
                        ),
                        onPressed: () =>
                            _confirmDownload(ref, pendingDownload, context),
                        semanticLabel: translateForWidget(
                          ref,
                          I18nKey.editorConfirmDownload,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget body(BuildContext context, WidgetRef ref) {
    return buildThemedCodeForge(
      context,
      ref,
      controller: widget.editorController,
      filePath: widget.file.path,
      rebuildKey: activeEditorRebuildKey(context, ref),
      undoController: widget.undoController,
      findController: _findController,
      customContextMenuItems: _editorContextMenuItems(ref),
      onModifierTap: (offset) =>
          unawaited(_goToDefinition(context, ref, textOffset: offset)),
      onToggleBlockComment: _toggleBlockComment,
      onFormatDocument: () => unawaited(_formatDocument(context, ref)),
      onFindReferences: () => unawaited(_findReferences(context, ref)),
      onGoToImplementation: () => unawaited(
        _goToDefinition(context, ref, method: 'textDocument/implementation'),
      ),
      finderBuilder: (context, controller) {
        final theme = resolveActiveThemeForSurface(context, ref);
        final colors = editorSurfaceColors(context, theme);
        return _EditorFindBar(
          controller: controller,
          foreground: colors.foreground,
          background: colors.background,
        );
      },
      contextMenuBuilder: (context, details) {
        return _EditorContextMenu(details: details);
      },
    );
  }

  void _openFind({bool replace = false}) {
    // Carry the current selection into the query, VSCode-style.
    final selection = widget.editorController.selection;
    if (!selection.isCollapsed &&
        selection.start >= 0 &&
        selection.end <= widget.editorController.text.length) {
      final selected = widget.editorController.text.substring(
        selection.start,
        selection.end,
      );
      if (selected.isNotEmpty && !selected.contains('\n')) {
        _findController.findInputController.text = selected;
      }
    }
    _findController
      ..isActive = true
      ..isReplaceMode = replace;
  }

  /// Asks for a line number and moves the caret there, VSCode-style.
  ///
  /// The dialog is prefilled with the caret's line so correcting a nearby
  /// line costs one edit; the jump follows the same scroll-then-select order
  /// the plugin `go_to_line` command uses.
  Future<void> _goToLine(BuildContext context, WidgetRef ref) async {
    final controller = widget.editorController;
    final lineCount = controller.lineCount;
    if (lineCount == 0) return;
    final caretOffset = controller.selection.extentOffset.clamp(
      0,
      controller.length,
    );
    final caretLine = controller.getLineAtOffset(caretOffset);

    final rawLine = await showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _GoToLineDialog(initialLine: caretLine + 1, lineCount: lineCount),
    );
    if (rawLine == null) return;
    final line = (int.tryParse(rawLine) ?? 0) - 1;
    if (line < 0 || line >= lineCount) return;
    try {
      controller.scrollToLine(line);
    } on StateError {
      // The editor was not mounted (tab closed while the dialog was open).
      return;
    }
    controller.setSelectionSilently(
      TextSelection.collapsed(offset: controller.getLineStartOffset(line)),
    );
    controller.focusNode?.requestFocus();
  }

  /// Toggles line comments over the selected lines, or the caret line when
  /// the selection is collapsed.
  ///
  /// The marker follows the file's grammar (`#`, `//`, `--`); grammars without
  /// a usable line comment (XML, Markdown, JSON) leave the shortcut inert.
  void _toggleLineComment() {
    final controller = widget.editorController;
    if (controller.readOnly || controller.lineCount == 0) return;
    final marker = resolveEditorLanguage(
      controller.openedFile,
    ).lineCommentMarker;
    if (marker == null) return;

    final selection = controller.selection;
    var startLine = controller.getLineAtOffset(selection.start);
    var endLine = controller.getLineAtOffset(selection.end);
    // A selection ending exactly at a line start does not include that line.
    if (!selection.isCollapsed &&
        endLine > startLine &&
        selection.end == controller.getLineStartOffset(endLine)) {
      endLine--;
    }

    final blockStart = controller.getLineStartOffset(startLine);
    final oldLines = [
      for (var line = startLine; line <= endLine; line++)
        controller.getLineText(line),
    ];
    final result = toggleLineComments(oldLines, marker: marker);
    if (result == null) return;

    int mapOffset(int offset) {
      var remaining = offset - blockStart;
      var index = 0;
      while (index < oldLines.length - 1 &&
          remaining > oldLines[index].length) {
        remaining -= oldLines[index].length + 1;
        index++;
      }
      var shift = 0;
      for (var i = 0; i < index; i++) {
        shift += result.deltas[i];
      }
      final newLength = oldLines[index].length + result.deltas[index];
      var local = remaining + result.deltas[index];
      if (local < 0) local = 0;
      if (local > newLength) local = newLength;
      return blockStart + shift + local;
    }

    var blockEnd = blockStart - 1;
    for (final line in oldLines) {
      blockEnd += line.length + 1;
    }
    controller.replaceRange(blockStart, blockEnd, result.lines.join('\n'));
    controller.setSelectionSilently(
      TextSelection(
        baseOffset: mapOffset(selection.baseOffset),
        extentOffset: mapOffset(selection.extentOffset),
      ),
    );
  }

  /// Toggles a paired block comment over the selected lines, or the caret line
  /// when the selection is collapsed.
  ///
  /// Deliberately separate from [_toggleLineComment] rather than a fallback
  /// from it: for JSON there is no block comment *and* no line comment, so
  /// guessing would insert a delimiter that breaks the file. A grammar with
  /// only a line comment (`#` in Python) leaves this key inert rather than
  /// reaching for the line toggle behind the user's back.
  void _toggleBlockComment() {
    final controller = widget.editorController;
    if (controller.readOnly || controller.lineCount == 0) return;
    final delimiters = resolveEditorLanguage(
      controller.openedFile,
    ).blockCommentDelimiters;
    if (delimiters == null) return;

    final tabSize = ref.read(editorTabSize);
    controller.toggleBlockComment(
      start: delimiters.start,
      end: delimiters.end,
      // Match what the user actually types rather than a hardcoded four spaces:
      // re-indenting a block to a different width than the rest of the file is
      // a diff they did not ask for.
      indentUnit: ref.read(editorUseSpaceAsTab) ? ' ' * tabSize : '\t',
    );
  }

  List<CustomContextMenu> _editorContextMenuItems(WidgetRef ref) {
    final controller = widget.editorController;
    final config = controller.lspConfig;
    final items = <CustomContextMenu>[
      CustomContextMenu(
        label: translateForWidget(ref, I18nKey.editorMenuSearch),
        description: findShortcutLabel(),
        icon: Icons.search,
        onPress: _openFind,
      ),
      CustomContextMenu(
        label: translateForWidget(ref, I18nKey.editorMenuToggleComment),
        description: toggleCommentShortcutLabel(),
        icon: Icons.comment_outlined,
        onPress: _toggleLineComment,
      ),
      CustomContextMenu(
        label: translateForWidget(ref, I18nKey.editorMenuFormatDocument),
        description: formatDocumentShortcutLabel(),
        icon: Icons.format_align_left,
        onPress: () => unawaited(_formatDocument(context, ref)),
      ),
      // Only offered when the grammar has a paired delimiter: offering a
      // disabled-looking item for JSON would suggest the editor is missing a
      // feature when the file format genuinely has no block comment.
      if (resolveEditorLanguage(controller.openedFile).blockCommentDelimiters !=
          null)
        CustomContextMenu(
          label: translateForWidget(ref, I18nKey.editorMenuToggleBlockComment),
          description: toggleBlockCommentShortcutLabel(),
          icon: Icons.format_quote,
          onPress: _toggleBlockComment,
        ),
      // Secondary cursors are otherwise only reachable through Alt+Click and
      // Alt+Shift+Down, which is undiscoverable in practice. This is the
      // discoverable entry point into the editor's multi-cursor support.
      CustomContextMenu(
        label: translateForWidget(ref, I18nKey.statusEditorAddCursor),
        description: addCursorShortcutLabel(),
        icon: Icons.add_comment_outlined,
        // Only visibleAt: the widget prefers it over `visible` when both are
        // present, and _addCursorAtOffset re-checks readOnly before acting.
        visibleAt: (_) => !controller.readOnly,
        onPress: () => _addCursorAtSelection(controller),
        onPressAt: (offset) => _addCursorAtOffset(controller, offset),
      ),
    ];
    // Read the switches themselves rather than the config's capability
    // snapshot: the menu is assembled during build, so watching is what makes
    // an entry appear or disappear the moment the user flips the switch, on a
    // file that is already open.
    final lspActions = lspContextMenuActions(
      hasLanguageServer: config != null,
      goToDefinition: ref.watch(lspGoToDefinition),
      rename: ref.watch(lspRename),
    );
    if (lspActions.contains(EditorLspMenuAction.goToDefinition)) {
      items.add(
        CustomContextMenu(
          label: translateForWidget(ref, I18nKey.editorMenuGoToDefinition),
          description: goToDefinitionShortcutLabel(),
          icon: Icons.arrow_outward,
          visibleAt: (offset) => _isSymbolAtOffset(controller, offset),
          onPressAt: (offset) =>
              unawaited(_goToDefinition(context, ref, textOffset: offset)),
          onPress: () => unawaited(_goToDefinition(context, ref)),
        ),
      );
      items.add(
        CustomContextMenu(
          label: translateForWidget(ref, I18nKey.editorMenuGoToImplementation),
          description: goToImplementationShortcutLabel(),
          icon: Icons.arrow_forward,
          visibleAt: (offset) => _isSymbolAtOffset(controller, offset),
          onPressAt: (offset) => unawaited(
            _goToDefinition(
              context,
              ref,
              method: 'textDocument/implementation',
              textOffset: offset,
            ),
          ),
          onPress: () => unawaited(
            _goToDefinition(
              context,
              ref,
              method: 'textDocument/implementation',
            ),
          ),
        ),
      );
    }
    if (lspActions.contains(EditorLspMenuAction.rename)) {
      items.add(
        CustomContextMenu(
          label: translateForWidget(ref, I18nKey.fileActionRename),
          description: renameShortcutLabel(),
          icon: Icons.drive_file_rename_outline,
          visibleAt: (offset) => _isSymbolAtOffset(controller, offset),
          onPressAt: (offset) =>
              unawaited(_renameSymbol(context, ref, textOffset: offset)),
          onPress: () => unawaited(_renameSymbol(context, ref)),
        ),
      );
    }
    if (lspActions.contains(EditorLspMenuAction.findReferences)) {
      items.add(
        CustomContextMenu(
          label: translateForWidget(ref, I18nKey.editorMenuFindReferences),
          description: findReferencesShortcutLabel(),
          icon: Icons.manage_search,
          visibleAt: (offset) => _isSymbolAtOffset(controller, offset),
          onPressAt: (offset) =>
              unawaited(_findReferences(context, ref, textOffset: offset)),
          onPress: () => unawaited(_findReferences(context, ref)),
        ),
      );
    }
    return items;
  }

  /// Adds a secondary cursor at the caret, or at the start of the selection
  /// when one is active.
  void _addCursorAtSelection(CodeForgeController controller) {
    final selection = controller.selection;
    final anchor = selection.isCollapsed
        ? selection.extentOffset
        : selection.start;
    _addCursorAtOffset(controller, anchor);
  }

  void _addCursorAtOffset(CodeForgeController controller, int offset) {
    if (controller.readOnly) return;
    final safeOffset = offset.clamp(0, controller.length).toInt();
    // An empty document has no line to query, so fall through with line 0.
    final hasLines = controller.lineCount > 0;
    final line = hasLines ? controller.getLineAtOffset(safeOffset) : 0;
    final column = hasLines
        ? safeOffset - controller.getLineStartOffset(line)
        : 0;
    controller.addMultiCursor(line, column);
  }

  bool _isSymbolAtOffset(CodeForgeController controller, int offset) {
    if (offset < 0 || offset > controller.length) return false;
    final symbolOffset = offset == controller.length && offset > 0
        ? offset - 1
        : offset;
    return symbolOffset < controller.length &&
        RegExp(r'[A-Za-z0-9_]').hasMatch(controller.text[symbolOffset]);
  }

  int _lspOffset(CodeForgeController controller, [int? contextOffset]) {
    if (contextOffset != null && contextOffset >= 0) {
      final selection = controller.selection;
      if (!selection.isCollapsed &&
          contextOffset >= selection.start &&
          contextOffset <= selection.end) {
        return selection.start;
      }
      return contextOffset.clamp(0, controller.length).toInt();
    }
    return controller.selection.isCollapsed
        ? controller.selection.extentOffset
        : controller.selection.start;
  }

  Future<void> _goToDefinition(
    BuildContext context,
    WidgetRef ref, {
    String method = 'textDocument/definition',
    int? textOffset,
  }) async {
    final controller = widget.editorController;
    final config = controller.lspConfig;
    final filePath = controller.openedFile;
    if (config == null ||
        filePath == null ||
        !config.capabilities.goToDefinition) {
      return;
    }
    final offset = _lspOffset(controller, textOffset);
    final line = controller.getLineAtOffset(offset);
    final character = offset - controller.getLineStartOffset(line);
    final params = {
      'textDocument': {'uri': Uri.file(filePath).toString()},
      'position': {'line': line, 'character': character},
    };
    dynamic location;
    try {
      var response = await config.sendRequest(method: method, params: params);
      if (method == 'textDocument/implementation' &&
          !_hasLocation(response['result'])) {
        response = await config.sendRequest(
          method: 'textDocument/definition',
          params: params,
        );
      }
      location = response['result'];
    } catch (error) {
      // A dead or unresponsive language server throws here; without this
      // guard the failure dies inside the unawaited future and F12 appears
      // to do nothing.
      if (!context.mounted) return;
      _showLspRequestError(ref, error);
      return;
    }
    if (location is List) location = location.firstOrNull;
    if (location is! Map) return;
    final uri = (location['uri'] ?? location['targetUri'])?.toString();
    final range =
        location['range'] ??
        location['targetSelectionRange'] ??
        location['targetRange'];
    if (uri == null || range is! Map || !context.mounted) return;
    final targetUri = Uri.tryParse(uri);
    if (targetUri == null || targetUri.scheme != 'file') return;
    final start = range['start'];
    if (start is! Map) return;
    await revealLspLocation(
      context,
      ref,
      canonicalLocalPath(targetUri.toFilePath()),
      (start['line'] as num?)?.toInt(),
      (start['character'] as num?)?.toInt(),
    );
  }

  bool _hasLocation(dynamic location) {
    if (location is List) location = location.firstOrNull;
    return location is Map &&
        (location['uri'] != null || location['targetUri'] != null);
  }

  /// Formats the current document via `textDocument/formatting`.
  ///
  /// When [quiet] is set (format-on-save), success feedback and
  /// "no formatter" notices are suppressed; only hard failures surface.
  Future<bool> _formatDocument(
    BuildContext context,
    WidgetRef ref, {
    bool quiet = false,
  }) async {
    return formatEditorDocument(
      context,
      ref,
      widget.editorController,
      quiet: quiet,
      // An explicit format request means "what I have selected"; the
      // format-on-save path leaves this off and always formats the file.
      selectionOnly: true,
    );
  }

  /// Finds all references to the symbol at the caret (or [textOffset]) and
  /// shows them in the shared jump-to-location window.
  Future<void> _findReferences(
    BuildContext context,
    WidgetRef ref, {
    int? textOffset,
  }) async {
    final controller = widget.editorController;
    final config = controller.lspConfig;
    final filePath = controller.openedFile;
    if (config == null || filePath == null) return;
    final offset = _lspOffset(controller, textOffset);
    final line = controller.getLineAtOffset(offset);
    final character = offset - controller.getLineStartOffset(line);

    List<dynamic> locations;
    try {
      locations = await config.getReferences(filePath, line, character);
    } catch (error) {
      if (!context.mounted) return;
      _showLspRequestError(ref, error);
      return;
    }
    if (!context.mounted) return;
    if (locations.isEmpty) {
      ref
          .read(ideMessageProvider.notifier)
          .show(translateForWidget(ref, I18nKey.editorReferencesEmpty));
      return;
    }
    final symbol = symbolAtOffset(controller.text, offset);
    final entries = [
      for (final location in locations.whereType<Map>())
        ?LspLocationEntry.fromLspMap(location),
    ];
    await showLspLocationDialog(
      context,
      ref,
      titleBuilder: (ref) =>
          translateForWidget(ref, I18nKey.editorReferencesResultTitle)
              .replaceAll('{symbol}', symbol.isEmpty ? '?' : symbol)
              .replaceAll('{count}', entries.length.toString()),
      entries: entries,
      onOpen: (entry) => revealLspLocation(
        context,
        ref,
        entry.path,
        entry.line,
        entry.character,
      ),
    );
  }

  Future<void> _renameSymbol(
    BuildContext context,
    WidgetRef ref, {
    int? textOffset,
  }) async {
    final controller = widget.editorController;
    final config = controller.lspConfig;
    final filePath = controller.openedFile;
    if (config == null || filePath == null || !config.capabilities.rename) {
      return;
    }
    // Prefill the dialog with the symbol being renamed so the user edits the
    // name in place instead of retyping it.
    final offset = _lspOffset(controller, textOffset);
    final currentName = symbolAtOffset(controller.text, offset);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => DialogFormFields(
        initialValues: [currentName],
        selectAll: true,
        builder: (context, c) => AlertDialog(
          title: Text(translateForWidget(ref, I18nKey.fileActionRename)),
          content: TextField(controller: c[0], autofocus: true),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: Text(translateForWidget(ref, I18nKey.commonCancel)),
            ),
            FilledButton(
              onPressed: () => context.pop(c[0].text),
              child: Text(translateForWidget(ref, I18nKey.commonConfirm)),
            ),
          ],
        ),
      ),
    );
    if (newName == null || newName.trim().isEmpty) return;
    final line = controller.getLineAtOffset(offset);
    final character = offset - controller.getLineStartOffset(line);
    try {
      final edit = await config.renameSymbol(
        filePath,
        line,
        character,
        newName.trim(),
      );
      if (edit.isNotEmpty) {
        await _applyRenameEdit(ref, controller, edit);
      }
    } catch (error) {
      if (!context.mounted) return;
      _showLspRequestError(ref, error);
    }
  }

  /// Surfaces a failed LSP request as an error message.
  ///
  /// Shared by the definition, rename and references flows so a dead or
  /// unresponsive language server fails visibly instead of leaving the
  /// shortcut to look broken.
  void _showLspRequestError(WidgetRef ref, Object error) {
    ref
        .read(ideMessageProvider.notifier)
        .error(
          translateForWidget(
            ref,
            I18nKey.editorLspRequestFailed,
          ).replaceAll('{error}', error.toString()),
        );
  }

  Future<void> _applyRenameEdit(
    WidgetRef ref,
    CodeForgeController currentController,
    Map<String, dynamic> edit,
  ) async {
    final changes = <String, List<dynamic>>{};
    final rawChanges = edit['changes'];
    if (rawChanges is Map) {
      for (final entry in rawChanges.entries) {
        if (entry.key is String && entry.value is List) {
          changes
              .putIfAbsent(entry.key as String, () => [])
              .addAll(entry.value as List);
        }
      }
    }
    final documentChanges = edit['documentChanges'];
    if (documentChanges is List) {
      for (final change in documentChanges.whereType<Map>()) {
        final document = change['textDocument'];
        final uri = document is Map ? document['uri'] : null;
        final edits = change['edits'];
        if (uri is String && edits is List) {
          changes.putIfAbsent(uri, () => []).addAll(edits);
        }
      }
    }

    final controllers = ref.read(editorControllerMapProvider);
    for (final entry in changes.entries) {
      final uri = Uri.tryParse(entry.key);
      if (uri == null || uri.scheme != 'file') continue;
      // Canonical spelling so open tabs are found by path even when the
      // server spells the drive differently than the file picker did.
      final filePath = canonicalLocalPath(uri.toFilePath());
      final targetUri = Uri.file(filePath).toString();
      final controller = currentController.openedFile == filePath
          ? currentController
          : controllers[filePath];
      late final String updatedContent;
      if (controller != null) {
        await controller.applyWorkspaceEdit({
          'edit': {
            'changes': {targetUri: entry.value},
          },
        });
        updatedContent = controller.text;
      } else {
        final file = File(filePath);
        if (!await file.exists()) continue;
        final original = await file.readAsString();
        updatedContent = applyLspTextEdits(original, entry.value);
        if (updatedContent != original) {
          await file.writeAsString(updatedContent);
        }
      }
      if (filePath != currentController.openedFile) {
        await currentController.lspConfig?.syncDocument(
          filePath,
          updatedContent,
        );
      }
    }
  }

  void _handleConfirm(BuildContext context, WidgetRef ref) {
    final pending = ref.read(pendingUploadProviderMap[widget.file.path]!);
    if (pending != null) {
      _confirmUpload(ref, pending, context);
      return;
    }
    final pendingDownload = ref.read(
      pendingDownloadProviderMap[widget.file.path]!,
    );
    if (pendingDownload != null) {
      _confirmDownload(ref, pendingDownload, context);
    }
  }

  void _handleCancel(BuildContext context, WidgetRef ref) {
    ref
        .read(editorControllerMapProvider.notifier)
        .getSelectedController()
        ?.clearGitDiffDecorations();
    // print(ref.read(editorControllerMapProvider));

    ref.read(pendingUploadProviderMap[widget.file.path]!.notifier).state = null;
    ref.read(pendingDownloadProviderMap[widget.file.path]!.notifier).state =
        null;
    if (context.mounted) context.go('/file');
  }

  Future<void> _confirmUpload(
    WidgetRef ref,
    PendingUpload pending,
    BuildContext context,
  ) async {
    try {
      ref
          .read(editorControllerMapProvider.notifier)
          .getSelectedController()
          ?.clearGitDiffDecorations();
      final currentContent = pending.content;
      await ref
          .read(boardProvider)
          .ops
          .writeFile(pending.targetPath, currentContent);
      ref
          .read(tabbedViewControllerProvider.notifier)
          .warnOpenFilesOverwritten(
            boardFiles: true,
            filePaths: [pending.targetPath],
          );
      ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();

      ref
          .read(ideMessageProvider.notifier)
          .success(
            translateForWidget(
              ref,
              I18nKey.editorUploadedToDevice,
            ).replaceAll('{path}', pending.targetPath),
          );
    } catch (error) {
      ref
          .read(ideMessageProvider.notifier)
          .error(
            translateForWidget(
              ref,
              I18nKey.editorUploadFailed,
            ).replaceAll('{error}', error.toString()),
          );
    } finally {
      ref.read(pendingUploadProviderMap[widget.file.path]!.notifier).state =
          null;
      if (context.mounted) context.go('/file');
    }
  }

  Future<void> _confirmDownload(
    WidgetRef ref,
    PendingDownload pending,
    BuildContext context,
  ) async {
    try {
      final currentContent = pending.content;
      await File(pending.localPath).writeAsString(currentContent);
      ref
          .read(tabbedViewControllerProvider.notifier)
          .warnOpenFilesOverwritten(
            boardFiles: false,
            filePaths: [pending.localPath],
          );
      ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
      ref
          .read(editorControllerMapProvider.notifier)
          .getSelectedController()
          ?.clearGitDiffDecorations();

      ref
          .read(ideMessageProvider.notifier)
          .success(
            translateForWidget(
              ref,
              I18nKey.editorDownloadedToLocal,
            ).replaceAll('{path}', pending.localPath),
          );
    } catch (error) {
      ref
          .read(ideMessageProvider.notifier)
          .error(
            translateForWidget(
              ref,
              I18nKey.editorDownloadFailed,
            ).replaceAll('{error}', error.toString()),
          );
    } finally {
      ref.read(pendingDownloadProviderMap[widget.file.path]!.notifier).state =
          null;
      if (context.mounted) context.go('/file');
    }
  }
}

/// Asks for a line number and pops the accepted value as a string.
///
/// The input controller is owned by [DialogFormFields] rather than by the
/// caller, because `showDialog` completes the instant the route is popped -
/// *before* the exit animation and the dialog's teardown have run. A caller
/// that disposes its controller as soon as the future resolves disposes one
/// the [TextField] is still listening to.
///
/// The Ctrl+G prompt.
///
/// Controller ownership is delegated to [DialogFormFields] for the reason
/// documented there; this widget only owns the validation message, which
/// needs a [setState] of its own.
class _GoToLineDialog extends ConsumerStatefulWidget {
  const _GoToLineDialog({required this.initialLine, required this.lineCount});

  /// One-based line the field starts on.
  final int initialLine;

  /// Total lines in the document, used to validate and to word the message.
  final int lineCount;

  @override
  ConsumerState<_GoToLineDialog> createState() => _GoToLineDialogState();
}

class _GoToLineDialogState extends ConsumerState<_GoToLineDialog> {
  String? _errorText;

  /// Pops with the accepted value, or shows the range error in place.
  void _submit(TextEditingController input) {
    final line = int.tryParse(input.text.trim());
    if (line == null || line < 1 || line > widget.lineCount) {
      setState(() {
        _errorText = translateForWidget(
          ref,
          I18nKey.editorGoToLineInvalid,
        ).replaceAll('{lines}', '${widget.lineCount}');
      });
      return;
    }
    context.pop(input.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return DialogFormFields(
      initialValues: ['${widget.initialLine}'],
      selectAll: true,
      builder: (context, c) => AlertDialog(
        title: Text(translateForWidget(ref, I18nKey.editorGoToLine)),
        content: TextField(
          controller: c[0],
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: translateForWidget(
              ref,
              I18nKey.editorGoToLineHint,
            ).replaceAll('{lines}', '${widget.lineCount}'),
            errorText: _errorText,
          ),
          onSubmitted: (_) => _submit(c[0]),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(translateForWidget(ref, I18nKey.commonCancel)),
          ),
          FilledButton(
            onPressed: () => _submit(c[0]),
            child: Text(
              translateForWidget(ref, I18nKey.editorJumpGoToLocation),
            ),
          ),
        ],
      ),
    );
  }
}

/// One option button (Aa / ab / .*) in the find bar.
///
/// The hover fill, the active fill and the border are all painted by the same
/// [BoxDecoration] on the same square, so no state can draw a rectangle offset
/// from the others. The gap between neighbouring buttons comes from padding
/// around that square rather than a margin on it.
class _FindBarToggle extends StatefulWidget {
  const _FindBarToggle({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final bool active;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  State<_FindBarToggle> createState() => _FindBarToggleState();
}

class _FindBarToggleState extends State<_FindBarToggle> {
  static const double _size = _EditorFindBar._buttonSize - 2;

  /// Sibling toggles share the find bar's inset, so every button in the row has
  /// the same corner radius.
  static const double _inset = _EditorFindBar._inset;

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // `container: true` prevents adjacent toolbar buttons from merging this
    // tooltip's semantics anchor into one shared node. See
    // flutter/flutter#182444.
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        container: true,
        child: Padding(
          // Separates adjacent toggles without shrinking the painted square.
          padding: const EdgeInsets.only(left: 2),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onPressed,
              child: Container(
                width: _size,
                height: _size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: context.nestedCorners(_inset),
                  color: widget.active
                      ? widget.foreground.withAlpha(36)
                      : _hovered
                      ? widget.foreground.withAlpha(20)
                      : Colors.transparent,
                  // Hover reuses the border slot so it can never paint a
                  // second, offset rectangle next to the active one.
                  border: Border.all(
                    color: widget.active
                        ? widget.foreground.withAlpha(130)
                        : _hovered
                        ? widget.foreground.withAlpha(90)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.foreground.withAlpha(
                      widget.active ? 255 : 150,
                    ),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// VSCode-style floating find widget: a compact rounded panel that hovers over
/// the top-right corner of the editor viewport instead of pushing content down.
class _EditorFindBar extends ConsumerWidget implements PreferredSizeWidget {
  const _EditorFindBar({
    required this.controller,
    required this.foreground,
    required this.background,
  });

  final FindController controller;
  final Color foreground;
  final Color background;

  static const double _rowHeight = 32;
  static const double _buttonSize = 28;

  /// Horizontal inset between the find bar surface and its children. Nested
  /// surfaces derive their radius from this so their arcs stay concentric
  /// with the bar.
  static const double _inset = 8;

  /// Minimum width of the match counter, used while it shows a result.
  static const double _matchCounterMinWidth = 34;

  /// Horizontal breathing room around the match counter text.
  static const double _matchCounterPadding = 6;

  /// Size of the leading search/replace icon in both rows.
  static const double _leadingIconSize = 16;

  /// Gap between the leading button and the leading icon.
  static const double _gapAfterLeadingButton = 4;

  /// Gap between the leading icon and the input, and between the input and
  /// whatever follows it.
  static const double _gapAroundField = 6;

  /// Leading offset of both input rows: the leading button plus its gap, the
  /// leading icon and the gap that separates it from the input. The replace
  /// row has no leading button, so it pads that slot instead, which keeps both
  /// inputs starting at the same x position.
  static const double _leadingWidth =
      _buttonSize + _gapAfterLeadingButton + _leadingIconSize + _gapAroundField;

  /// Width of everything between the find input and the right edge except the
  /// match counter: the gap in front of it plus the six trailing buttons
  /// (three option toggles and three nav buttons). The counter's measured
  /// width is added at build time.
  static const double _trailingWidth = _gapAroundField + _buttonSize * 6;

  @override
  Size get preferredSize => Size.fromHeight(controller.isReplaceMode ? 80 : 44);

  Color get _elevatedBackground =>
      Color.alphaBlend(foreground.withAlpha(14), background).withAlpha(255);

  Color get _fieldBackground => Color.alphaBlend(
    foreground.withAlpha(12),
    _elevatedBackground,
  ).withAlpha(255);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String tr(I18nKey key) => translateForWidget(ref, key);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // F3 cycles matches while the find bar has keyboard focus.
        if (event.logicalKey == LogicalKeyboardKey.f3) {
          HardwareKeyboard.instance.isShiftPressed
              ? controller.previous()
              : controller.next();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          controller.isActive = false;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: _elevatedBackground,
        elevation: 8,
        shadowColor: Colors.black.withAlpha(90),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: context.outerCorners,
          side: BorderSide(color: foreground.withAlpha(38)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _EditorFindBar._inset,
            vertical: 6,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final counter = _matchCounter(tr);
              // Both inputs get the same width so their left and right edges
              // line up, independent of how wide the trailing buttons are. The
              // counter only reserves the width its text needs, so both inputs
              // grow into the space it leaves free.
              final fieldWidth = max(
                0.0,
                constraints.maxWidth -
                    _leadingWidth -
                    counter.width -
                    _trailingWidth,
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: _rowHeight,
                    child: Row(
                      children: [
                        _iconButton(
                          icon: controller.isReplaceMode
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          tooltip: tr(
                            controller.isReplaceMode
                                ? I18nKey.editorFindHideReplace
                                : I18nKey.editorFindShowReplace,
                          ),
                          onPressed: controller.toggleReplaceMode,
                        ),
                        const SizedBox(width: _gapAfterLeadingButton),
                        Icon(
                          Icons.search,
                          size: _leadingIconSize,
                          color: foreground,
                        ),
                        const SizedBox(width: _gapAroundField),
                        SizedBox(
                          width: fieldWidth,
                          child: _textField(
                            context,
                            controller: controller.findInputController,
                            focusNode: controller.findInputFocusNode,
                            hintText: tr(I18nKey.editorFindHint),
                            onSubmitted: (_) => _shiftHeld
                                ? controller.previous()
                                : controller.next(),
                          ),
                        ),
                        const SizedBox(width: _gapAroundField),
                        counter.widget,
                        _toggle(
                          label: 'Aa',
                          tooltip: tr(I18nKey.editorFindCaseSensitive),
                          active: controller.caseSensitive,
                          onPressed: controller.toggleCaseSensitive,
                        ),
                        _toggle(
                          label: 'ab',
                          tooltip: tr(I18nKey.editorFindWholeWord),
                          active: controller.matchWholeWord,
                          onPressed: controller.toggleMatchWholeWord,
                        ),
                        _toggle(
                          label: '.*',
                          tooltip: tr(I18nKey.editorFindRegex),
                          active: controller.isRegex,
                          onPressed: controller.toggleRegex,
                        ),
                        _navButton(
                          icon: Icons.keyboard_arrow_up,
                          tooltip: tr(I18nKey.editorFindPrevious),
                          onPressed: controller.previous,
                        ),
                        _navButton(
                          icon: Icons.keyboard_arrow_down,
                          tooltip: tr(I18nKey.editorFindNext),
                          onPressed: controller.next,
                        ),
                        _navButton(
                          icon: Icons.close,
                          tooltip: tr(I18nKey.editorFindClose),
                          onPressed: () => controller.isActive = false,
                        ),
                      ],
                    ),
                  ),
                  if (controller.isReplaceMode)
                    SizedBox(
                      height: _rowHeight,
                      child: Row(
                        children: [
                          // Pads the slot the find row's leading button uses so
                          // the two inputs share the same left edge.
                          const SizedBox(
                            width: _buttonSize + _gapAfterLeadingButton,
                          ),
                          Icon(
                            Icons.find_replace,
                            size: _leadingIconSize,
                            color: foreground,
                          ),
                          const SizedBox(width: _gapAroundField),
                          SizedBox(
                            width: fieldWidth,
                            child: _textField(
                              context,
                              controller: controller.replaceInputController,
                              focusNode: controller.replaceInputFocusNode,
                              hintText: tr(I18nKey.editorReplaceHint),
                              onSubmitted: (_) => controller.replace(),
                            ),
                          ),
                          // The replace row has fewer trailing buttons, so the
                          // leftover width is left blank.
                          const Spacer(),
                          const SizedBox(width: _gapAroundField),
                          _iconButton(
                            icon: Icons.check,
                            tooltip: tr(I18nKey.editorReplaceApply),
                            onPressed: controller.matchCount > 0
                                ? controller.replace
                                : null,
                          ),
                          _iconButton(
                            icon: Icons.done_all,
                            tooltip: tr(I18nKey.editorReplaceAll),
                            onPressed: controller.matchCount > 0
                                ? controller.replaceAll
                                : null,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static bool get _shiftHeld => HardwareKeyboard.instance.isShiftPressed;

  Widget _textField(
    BuildContext context, {
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required ValueChanged<String> onSubmitted,
  }) {
    final borderColor = foreground.withAlpha(46);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: 1,
      style: TextStyle(color: foreground, fontSize: 13),
      cursorColor: foreground,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: _fieldBackground,
        hintText: hintText,
        hintStyle: TextStyle(color: foreground.withAlpha(110), fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        enabledBorder: OutlineInputBorder(
          borderRadius: context.nestedCorners(_EditorFindBar._inset),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: context.nestedCorners(_EditorFindBar._inset),
          borderSide: BorderSide(color: foreground.withAlpha(160)),
        ),
      ),
    );
  }

  /// Builds the match counter together with the width it occupies so the
  /// caller can size the find input against it.
  ({double width, Widget widget}) _matchCounter(String Function(I18nKey) tr) {
    final hasQuery = controller.findInputController.text.isNotEmpty;
    final noResults = hasQuery && controller.matchCount == 0;
    final text = !hasQuery
        ? ''
        : noResults
        ? tr(I18nKey.editorFindNoResults)
        : '${controller.currentMatchIndex + 1}/${controller.matchCount}';
    final color = noResults
        ? Colors.redAccent.withAlpha(220)
        : foreground.withAlpha(200);
    final textStyle = TextStyle(color: color, fontSize: 11);
    if (text.isEmpty) {
      return (width: 0, widget: const SizedBox.shrink());
    }
    // Measure the label so the counter never reserves more room than it uses.
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = max(
      _matchCounterMinWidth,
      painter.width + _matchCounterPadding,
    );
    painter.dispose();
    return (
      width: width,
      widget: Container(
        width: width,
        alignment: Alignment.center,
        child: Text(text, textAlign: TextAlign.center, style: textStyle),
      ),
    );
  }

  /// Small square toggle (Aa / ab / .*) styled like VSCode option buttons.
  Widget _toggle({
    required String label,
    required String tooltip,
    required bool active,
    required VoidCallback onPressed,
  }) {
    return _FindBarToggle(
      label: label,
      tooltip: tooltip,
      active: active,
      foreground: foreground,
      onPressed: onPressed,
    );
  }

  Widget _navButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return _iconButton(icon: icon, tooltip: tooltip, onPressed: onPressed);
  }

  Widget _iconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      color: foreground.withAlpha(215),
      disabledColor: foreground.withAlpha(70),
      hoverColor: foreground.withAlpha(26),
      focusColor: Colors.transparent,
      highlightColor: foreground.withAlpha(40),
      splashRadius: _buttonSize / 2,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: _buttonSize,
        height: _buttonSize,
      ),
    );
  }
}

Future<void> runCurrentFile(BuildContext context, WidgetRef ref) async {
  final controller = ref
      .read(editorControllerMapProvider.notifier)
      .getSelectedController();
  if (controller == null) {
    ref
        .read(ideMessageProvider.notifier)
        .error(translateForWidget(ref, I18nKey.editorNoRunnableFile));
    return;
  }

  final stdoutDecoder = const Utf8Decoder(allowMalformed: true)
      .startChunkedConversion(
        StringConversionSink.fromStringSink(
          _TerminalStringSink(writeReplOutput),
        ),
      );
  final stderrDecoder = const Utf8Decoder(allowMalformed: true)
      .startChunkedConversion(
        StringConversionSink.fromStringSink(
          _TerminalStringSink(writeReplOutput),
        ),
      );
  var started = false;
  beginReplRunOutput();

  try {
    await saveFile(context, ref, quiet: true);
    ref.read(consolePageShow.notifier).state = true;
    await runPythonOnActiveDeviceStreaming(
      ref,
      controller.text,
      onStarted: () {
        started = true;
        ref
            .read(ideMessageProvider.notifier)
            .success(
              translateForWidget(
                ref,
                I18nKey.editorRunningFile,
              ).replaceAll('{path}', controller.openedFile ?? ''),
            );
      },
      onStdout: stdoutDecoder.add,
      onStderr: stderrDecoder.add,
    );
  } catch (error) {
    if (!started) {
      writeReplOutput(
        "\r\n${translateForWidget(ref, I18nKey.editorRunFailedTerminal).replaceAll('{error}', error.toString())}\r\n",
      );
    }
    ref
        .read(ideMessageProvider.notifier)
        .error(
          translateForWidget(
            ref,
            I18nKey.editorRunFailed,
          ).replaceAll('{error}', error.toString()),
        );
  } finally {
    stdoutDecoder.close();
    stderrDecoder.close();
    finishReplRunOutput();
  }
}

class _TerminalStringSink implements StringSink {
  const _TerminalStringSink(this.writeText);

  final void Function(String text) writeText;

  @override
  void write(Object? object) {
    writeText(object?.toString() ?? '');
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    writeText(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    writeText(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? object = '']) {
    writeText('${object ?? ''}\n');
  }
}

Future<void> saveFile(
  BuildContext context,
  WidgetRef ref, {
  quiet = false,
}) async {
  // Optional format-on-save; failures surface as messages but never block
  // saving the file.
  if (ref.read(editorFormatOnSave)) {
    final controller = ref
        .read(editorControllerMapProvider.notifier)
        .getSelectedController();
    if (controller != null) {
      await formatEditorDocument(context, ref, controller, quiet: true);
    }
  }

  await ref.read(fileProvider.notifier).saveCurrentFile();

  if (!quiet) {
    ref
        .read(ideMessageProvider.notifier)
        .success(translateForWidget(ref, I18nKey.statusSavedCurrentFile));
  }
}

/// Formats [controller]'s document through its LSP server.
///
/// Returns true when formatting was applied. With [quiet] (format-on-save)
/// success feedback and "no formatter available" notices are suppressed so
/// saving stays silent; only hard failures surface as error messages.
///
/// With [selectionOnly] and a non-collapsed selection, the selection is sent
/// as a range instead of the whole document — the VSCode behaviour, where
/// formatting a whole file because four lines are selected is a surprise. It
/// is deliberately off for format-on-save: a save should normalise the file the
/// user is actually keeping, not just the part they happened to have selected.
Future<bool> formatEditorDocument(
  BuildContext context,
  WidgetRef ref,
  CodeForgeController controller, {
  bool quiet = false,
  bool selectionOnly = false,
}) async {
  final config = controller.lspConfig;
  final filePath = controller.openedFile;
  if (config == null || filePath == null) {
    if (!quiet && context.mounted) {
      ref
          .read(ideMessageProvider.notifier)
          .info(translateForWidget(ref, I18nKey.editorFormatUnavailable));
    }
    return false;
  }
  // The formatter is told the user's own settings rather than a hardcoded
  // width, so formatting does not reindent the file against their preference.
  final tabSize = ref.read(editorTabSize);
  final insertSpaces = ref.read(editorUseSpaceAsTab);
  try {
    final selection = controller.selection;
    final useRange =
        selectionOnly && !selection.isCollapsed && controller.lineCount > 0;
    final List<dynamic> edits;
    if (useRange) {
      final startLine = controller.getLineAtOffset(selection.start);
      final endLine = controller.getLineAtOffset(selection.end);
      edits = await config.formatRange(
        filePath: filePath,
        startLine: startLine,
        startCharacter:
            selection.start - controller.getLineStartOffset(startLine),
        endLine: endLine,
        endCharacter: selection.end - controller.getLineStartOffset(endLine),
        tabSize: tabSize,
        insertSpaces: insertSpaces,
      );
    } else {
      edits = await config.formatDocument(
        filePath,
        tabSize: tabSize,
        insertSpaces: insertSpaces,
      );
    }
    if (edits.isEmpty) {
      if (!quiet && context.mounted) {
        ref
            .read(ideMessageProvider.notifier)
            .info(translateForWidget(ref, I18nKey.editorFormatUnavailable));
      }
      return false;
    }
    await controller.applyWorkspaceEdit({
      'edit': {
        'changes': {Uri.file(filePath).toString(): edits},
      },
    });
    if (!quiet && context.mounted) {
      ref
          .read(ideMessageProvider.notifier)
          .success(
            translateForWidget(
              ref,
              I18nKey.editorFormattedDocument,
            ).replaceAll('{path}', filePath),
          );
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      ref
          .read(ideMessageProvider.notifier)
          .error(
            translateForWidget(
              ref,
              I18nKey.editorFormatFailed,
            ).replaceAll('{error}', error.toString()),
          );
    }
    return false;
  }
}

class _EditorContextMenu extends ConsumerWidget {
  const _EditorContextMenu({required this.details});

  final CodeForgeContextMenuDetails details;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isTouch = details.isMobile;
    final screenSize = MediaQuery.sizeOf(context);
    final modifier = usesCommandShortcut ? 'Cmd' : 'Ctrl';
    final maxWidth = isTouch
        ? min(320.0, max(0.0, screenSize.width - 16))
        : 280.0;
    final menu = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (details.hasSelection && !details.readOnly)
          _menuItem(
            icon: Icons.cut,
            label: translateForWidget(ref, I18nKey.menuCut),
            shortcut: '$modifier+X',
            onTap: () {
              details.controller.cut();
              details.close();
            },
          ),

        if (details.hasSelection)
          _menuItem(
            icon: Icons.copy,
            label: translateForWidget(ref, I18nKey.menuCopy),
            shortcut: '$modifier+C',
            onTap: () {
              details.controller.copy();
              details.close();
            },
          ),

        if (!details.readOnly)
          _menuItem(
            icon: Icons.paste,
            label: translateForWidget(ref, I18nKey.menuPaste),
            shortcut: '$modifier+V',
            onTap: () async {
              await details.controller.paste();
              details.close();
            },
          ),

        _menuItem(
          icon: Icons.select_all,
          label: translateForWidget(ref, I18nKey.menuSelectAll),
          shortcut: '$modifier+A',
          onTap: () {
            details.controller.selectAll();
            details.close();
          },
        ),

        if (details.items.isNotEmpty) const Divider(height: 1),

        for (final item in details.items)
          _menuItem(
            icon: item.icon,
            label: item.label,
            shortcut: item.description,
            onTap: () {
              details.onItemPressed(item);
            },
          ),
      ],
    );

    return Material(
      elevation: 8,
      color: colorScheme.surfaceContainer,
      borderRadius: context.outerCorners,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: isTouch ? min(200.0, maxWidth) : 200,
          maxWidth: maxWidth,
          maxHeight: isTouch
              ? min(420.0, max(180.0, screenSize.height * 0.6))
              : double.infinity,
        ),
        child: isTouch
            ? SingleChildScrollView(child: menu)
            : IntrinsicWidth(child: menu),
      ),
    );
  }

  Widget _menuItem({
    required String label,
    required String shortcut,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: details.isMobile ? 16 : 12,
          vertical: details.isMobile ? 12 : 9,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: icon == null
                  ? null
                  : Icon(icon, size: details.isMobile ? 20 : 16),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (!details.isMobile && shortcut.isNotEmpty) ...[
              const SizedBox(width: 24),
              Text(shortcut, style: const TextStyle(fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}
