import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:code_forge/code_forge/code_area.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:code_forge/code_forge/find_controller.dart';
import 'package:code_forge/code_forge/styling.dart';
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
import 'package:pyrite_ide/core/services/file/local_tree.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/serial/active_device_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';
import 'package:pyrite_ide/features/edit_core/lsp_text_edits.dart';
import 'package:pyrite_ide/features/edit_core/line_comment.dart';
import 'package:pyrite_ide/features/edit_core/themed_code_forge.dart';

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

  /// Toggles `#` comments over the selected lines, or the caret line when
  /// the selection is collapsed.
  void _toggleLineComment() {
    final controller = widget.editorController;
    if (controller.readOnly || controller.lineCount == 0) return;

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
    final result = toggleLineComments(oldLines);
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
        description: '',
        icon: Icons.format_align_left,
        onPress: () => unawaited(_formatDocument(context, ref)),
      ),
      // Secondary cursors are otherwise only reachable through Alt+Click and
      // Alt+Shift+Down, which is undiscoverable in practice. This is the
      // discoverable entry point into the editor's multi-cursor support.
      CustomContextMenu(
        label: translateForWidget(ref, I18nKey.statusEditorAddCursor),
        description: '',
        icon: Icons.add_comment_outlined,
        // Only visibleAt: the widget prefers it over `visible` when both are
        // present, and _addCursorAtOffset re-checks readOnly before acting.
        visibleAt: (_) => !controller.readOnly,
        onPress: () => _addCursorAtSelection(controller),
        onPressAt: (offset) => _addCursorAtOffset(controller, offset),
      ),
    ];
    if (config == null) return items;
    if (config.capabilities.goToDefinition) {
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
          description: '',
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
    if (config.capabilities.rename) {
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
    items.add(
      CustomContextMenu(
        label: translateForWidget(ref, I18nKey.editorMenuFindReferences),
        description: '',
        icon: Icons.manage_search,
        visibleAt: (offset) => _isSymbolAtOffset(controller, offset),
        onPressAt: (offset) =>
            unawaited(_findReferences(context, ref, textOffset: offset)),
        onPress: () => unawaited(_findReferences(context, ref)),
      ),
    );
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
    final line = controller.lineCount == 0
        ? 0
        : controller.getLineAtOffset(safeOffset);
    final column = controller.lineCount == 0
        ? 0
        : safeOffset - controller.getLineStartOffset(line);
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
    var response = await config.sendRequest(
      method: method,
      params: {
        'textDocument': {'uri': Uri.file(filePath).toString()},
        'position': {'line': line, 'character': character},
      },
    );
    dynamic location = response['result'];
    if (method == 'textDocument/implementation' && !_hasLocation(location)) {
      response = await config.sendRequest(
        method: 'textDocument/definition',
        params: {
          'textDocument': {'uri': Uri.file(filePath).toString()},
          'position': {'line': line, 'character': character},
        },
      );
      location = response['result'];
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
      targetUri.toFilePath(),
      (start['line'] as num?)?.toInt(),
      (start['character'] as num?)?.toInt(),
    );
  }

  bool _hasLocation(dynamic location) {
    if (location is List) location = location.firstOrNull;
    return location is Map &&
        (location['uri'] != null || location['targetUri'] != null);
  }

  /// Opens [targetPath] in an editor tab, places the caret at
  /// ([targetLine], [targetCharacter]) and scrolls the line into view.
  Future<void> revealLspLocation(
    BuildContext context,
    WidgetRef ref,
    String targetPath,
    int? targetLine,
    int? targetCharacter,
  ) async {
    if (targetLine == null || targetCharacter == null) return;
    await ref
        .read(tabbedViewControllerProvider.notifier)
        .openFile(context, file: File(targetPath));
    if (!context.mounted) return;
    final targetController =
        ref
                .read(tabbedViewControllerProvider)
                .selectedTab
                ?.value
                .editorController
            as CodeForgeController?;
    if (targetController == null) return;
    targetController.selection = TextSelection.collapsed(
      offset: targetController.getLineStartOffset(targetLine) + targetCharacter,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        targetController.scrollToLine(targetLine);
      } on StateError {
        // The target tab may have been closed before it was mounted.
      }
    });
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
    );
  }

  /// Finds all references to the symbol at the caret (or [textOffset]) and
  /// shows them in a navigable list dialog.
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
      ref
          .read(ideMessageProvider.notifier)
          .error(
            translateForWidget(
              ref,
              I18nKey.editorFormatFailed,
            ).replaceAll('{error}', error.toString()),
          );
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ReferencesDialog(
        symbol: symbol,
        locations: locations.whereType<Map>().toList(),
        onOpen: (path, rangeStart) async {
          Navigator.of(dialogContext).pop();
          final start = rangeStart is Map ? rangeStart : null;
          await revealLspLocation(
            context,
            ref,
            path,
            start == null ? null : (start['line'] as num?)?.toInt(),
            start == null ? null : (start['character'] as num?)?.toInt(),
          );
        },
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
    final input = TextEditingController();
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translateForWidget(ref, I18nKey.fileActionRename)),
        content: TextField(controller: input, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(translateForWidget(ref, I18nKey.commonCancel)),
          ),
          FilledButton(
            onPressed: () => context.pop(input.text),
            child: Text(translateForWidget(ref, I18nKey.commonConfirm)),
          ),
        ],
      ),
    );
    input.dispose();
    if (newName == null || newName.trim().isEmpty) return;
    final offset = _lspOffset(controller, textOffset);
    final line = controller.getLineAtOffset(offset);
    final character = offset - controller.getLineStartOffset(line);
    final edit = await config.renameSymbol(
      filePath,
      line,
      character,
      newName.trim(),
    );
    if (edit.isNotEmpty) {
      await _applyRenameEdit(ref, controller, edit);
    }
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
      final filePath = uri.toFilePath();
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
  static const double _radius = 8;

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
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: foreground.withAlpha(38)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
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
                    const SizedBox(width: 4),
                    Icon(Icons.search, size: 16, color: foreground),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _textField(
                        controller: controller.findInputController,
                        focusNode: controller.findInputFocusNode,
                        hintText: tr(I18nKey.editorFindHint),
                        onSubmitted: (_) => _shiftHeld
                            ? controller.previous()
                            : controller.next(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _matchCounter(tr),
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
                      Icon(Icons.find_replace, size: 16, color: foreground),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _textField(
                          controller: controller.replaceInputController,
                          focusNode: controller.replaceInputFocusNode,
                          hintText: tr(I18nKey.editorReplaceHint),
                          onSubmitted: (_) => controller.replace(),
                        ),
                      ),
                      const SizedBox(width: 6),
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
          ),
        ),
      ),
    );
  }

  static bool get _shiftHeld => HardwareKeyboard.instance.isShiftPressed;

  Widget _textField({
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
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: foreground.withAlpha(160)),
        ),
      ),
    );
  }

  Widget _matchCounter(String Function(I18nKey) tr) {
    final hasQuery = controller.findInputController.text.isNotEmpty;
    final noResults = hasQuery && controller.matchCount == 0;
    final text = !hasQuery
        ? ''
        : noResults
        ? tr(I18nKey.editorFindNoResults)
        : '${controller.currentMatchIndex + 1}/${controller.matchCount}';
    return Container(
      constraints: const BoxConstraints(minWidth: 44),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: noResults
              ? Colors.redAccent.withAlpha(220)
              : foreground.withAlpha(200),
          fontSize: 11,
        ),
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
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          width: _buttonSize - 2,
          height: _buttonSize - 2,
          margin: const EdgeInsets.only(left: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            color: active ? foreground.withAlpha(36) : Colors.transparent,
            border: Border.all(
              color: active ? foreground.withAlpha(130) : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: foreground.withAlpha(active ? 255 : 150),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ),
      ),
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

/// A parsed `textDocument/references` entry for [_ReferencesDialog].
class _ReferenceLocation {
  const _ReferenceLocation({
    required this.path,
    required this.rangeStart,
    this.line,
    this.character,
  });

  final String path;

  /// Raw LSP `range.start` map, forwarded verbatim when jumping.
  final dynamic rangeStart;
  final int? line;
  final int? character;
}

_ReferenceLocation? _parseReferenceLocation(Map<dynamic, dynamic> location) {
  final uri = (location['uri'] ?? location['targetUri'])?.toString();
  final parsed = uri == null ? null : Uri.tryParse(uri);
  if (parsed == null || parsed.scheme != 'file') return null;
  final range = location['range'] ?? location['targetSelectionRange'];
  final start = range is Map ? range['start'] : null;
  return _ReferenceLocation(
    path: parsed.toFilePath(),
    rangeStart: start,
    line: start is Map ? (start['line'] as num?)?.toInt() : null,
    character: start is Map ? (start['character'] as num?)?.toInt() : null,
  );
}

/// Find-all-references results: a read-only editor preview (the exact same
/// themed [CodeForge] as the main editor) on the left and the reference list
/// on the right.
///
/// Single click previews the reference line's context; double click jumps to
/// it in the real editor. The first reference is previewed by default.
class _ReferencesDialog extends ConsumerStatefulWidget {
  const _ReferencesDialog({
    required this.symbol,
    required this.locations,
    required this.onOpen,
  });

  final String symbol;
  final List<Map<dynamic, dynamic>> locations;
  final Future<void> Function(String path, dynamic rangeStart) onOpen;

  @override
  ConsumerState<_ReferencesDialog> createState() => _ReferencesDialogState();
}

class _ReferencesDialogState extends ConsumerState<_ReferencesDialog> {
  late final CodeForgeController _previewController;
  final Map<String, String?> _contentCache = {};
  late final List<_ReferenceLocation> _items;
  var _selectedIndex = 0;
  var _loadingContent = false;
  String? _failedPath;

  @override
  void initState() {
    super.initState();
    _previewController = CodeForgeController();
    _items = [
      for (final location in widget.locations)
        ?_parseReferenceLocation(location),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _items.isNotEmpty) unawaited(_select(0));
    });
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  /// Returns the referenced file's content, preferring the live buffer of an
  /// open tab (so unsaved edits preview correctly) and caching disk reads.
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
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    setState(() {
      _selectedIndex = index;
      _loadingContent = true;
    });
    final content = await _loadContent(item.path);
    if (!mounted) return;
    if (content == null) {
      setState(() {
        _loadingContent = false;
        _failedPath = item.path;
      });
      return;
    }
    if (_previewController.text != content) {
      _previewController.text = content;
    }
    // Highlight the referenced line and place the caret there.
    _previewController.clearLineDecorations();
    final targetLine = item.line ?? 0;
    try {
      _previewController.addLineDecoration(
        LineDecoration(
          id: 'references-highlight',
          startLine: targetLine,
          endLine: targetLine,
          type: LineDecorationType.background,
          color: Theme.of(context).colorScheme.primary.withAlpha(45),
        ),
      );
    } catch (_) {}
    var offset = _previewController.getLineStartOffset(targetLine);
    offset = (offset + (item.character ?? 0))
        .clamp(0, _previewController.text.length)
        .toInt();
    _previewController.selection = TextSelection.collapsed(offset: offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _previewController.scrollToLine(targetLine);
      } on StateError {
        // Preview not mounted yet.
      }
    });
    setState(() {
      _loadingContent = false;
      _failedPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    // Portrait stacks preview above the list; landscape puts them side by side.
    final isPortrait = screenSize.height > screenSize.width;
    return AlertDialog(
      title: Text(
        translateForWidget(ref, I18nKey.editorReferencesResultTitle)
            .replaceAll('{symbol}', widget.symbol.isEmpty ? '?' : widget.symbol)
            .replaceAll('{count}', widget.locations.length.toString()),
      ),
      content: SizedBox(
        width: min(920.0, screenSize.width * 0.92),
        height: min(isPortrait ? 620.0 : 540.0, screenSize.height * 0.8),
        child: _items.isEmpty
            ? Center(
                child: Text(
                  translateForWidget(ref, I18nKey.editorReferencesEmpty),
                ),
              )
            : isPortrait
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildPreview(context)),
                  const Divider(height: 24),
                  SizedBox(height: 220, child: _buildReferenceList(context)),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildPreview(context)),
                  const VerticalDivider(width: 20),
                  SizedBox(width: 300, child: _buildReferenceList(context)),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text(translateForWidget(ref, I18nKey.commonCancel)),
        ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    final item = _items[_selectedIndex.clamp(0, _items.length - 1)];
    final failedToLoad = _failedPath == item.path;
    return Container(
      // Clip the editor to the rounded shape; the border is drawn via
      // foregroundDecoration so it paints ON TOP of the opaque editor
      // background. A `decoration` border would be painted first and then
      // covered by the child on straight edges, leaving only the corner
      // arcs visible — which looked like a notched corner.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
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
                buildThemedCodeForge(
                  context,
                  ref,
                  controller: _previewController,
                  filePath: item.path,
                  rebuildKey: 'references-preview:${item.path}',
                  readOnly: true,
                ),
                if (_loadingContent)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }

  Widget _buildReferenceList(BuildContext context) {
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final lineLabel = item.line == null ? '?' : '${item.line! + 1}';
        final charLabel = item.character == null ? '?' : '${item.character}';
        return GestureDetector(
          onTap: () => unawaited(_select(index)),
          // Double click closes the dialog and reveals the reference in the
          // real editor ([widget.onOpen] pops the dialog first).
          onDoubleTap: () =>
              unawaited(widget.onOpen(item.path, item.rangeStart)),
          child: ListTile(
            dense: true,
            selected: index == _selectedIndex,
            selectedTileColor: Theme.of(
              context,
            ).colorScheme.primary.withAlpha(30),
            leading: const Icon(Icons.description_outlined, size: 18),
            title: Text(
              item.path.split(RegExp(r'[\\/]')).last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'line $lineLabel:$charLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
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
Future<bool> formatEditorDocument(
  BuildContext context,
  WidgetRef ref,
  CodeForgeController controller, {
  bool quiet = false,
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
  try {
    final edits = await config.formatDocument(filePath);
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
      borderRadius: BorderRadius.circular(16),
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
