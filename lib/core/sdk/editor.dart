import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:code_forge/code_forge.dart';

abstract class SdkEditorCommands {
  // Text Content
  static const String getText = 'sdk.editor.get_text';
  static const String setText = 'sdk.editor.set_text';
  static const String getLineCount = 'sdk.editor.get_line_count';
  static const String getLineText = 'sdk.editor.get_line_text';
  static const String getSelectedText = 'sdk.editor.get_selected_text';
  static const String insertText = 'sdk.editor.insert_text';
  static const String replaceRange = 'sdk.editor.replace_range';
  static const String clear = 'sdk.editor.clear';

  // Cursor & Selection
  static const String getCursorPosition = 'sdk.editor.get_cursor_position';
  static const String setCursorPosition = 'sdk.editor.set_cursor_position';
  static const String getSelection = 'sdk.editor.get_selection';
  static const String setSelection = 'sdk.editor.set_selection';
  static const String selectAll = 'sdk.editor.select_all';
  static const String goToLine = 'sdk.editor.go_to_line';

  // Clipboard
  static const String copy = 'sdk.editor.copy';
  static const String cut = 'sdk.editor.cut';
  static const String paste = 'sdk.editor.paste';

  // Undo / Redo
  static const String undo = 'sdk.editor.undo';
  static const String redo = 'sdk.editor.redo';
  static const String canUndo = 'sdk.editor.can_undo';
  static const String canRedo = 'sdk.editor.can_redo';

  // Search
  static const String find = 'sdk.editor.find';
  static const String findRegex = 'sdk.editor.find_regex';
  static const String clearSearch = 'sdk.editor.clear_search';

  // Tab Management
  static const String openFile = 'sdk.editor.open_file';
  static const String closeTab = 'sdk.editor.close_tab';
  static const String getCurrentTab = 'sdk.editor.get_current_tab';
  static const String listTabs = 'sdk.editor.list_tabs';

  // Decorations
  static const String setGhostText = 'sdk.editor.set_ghost_text';
  static const String clearGhostText = 'sdk.editor.clear_ghost_text';
  static const String scrollToLine = 'sdk.editor.scroll_to_line';
}

class SdkEditor extends StateNotifier<PluginRunManager?> {
  final Ref ref;
  SdkEditor(this.ref) : super(null);

  void bind(PluginRunManager runManager) {
    state = runManager;

    // Text Content
    runManager.registerHandler(SdkEditorCommands.getText, _handleGetText);
    runManager.registerHandler(SdkEditorCommands.setText, _handleSetText);
    runManager.registerHandler(SdkEditorCommands.getLineCount, _handleGetLineCount);
    runManager.registerHandler(SdkEditorCommands.getLineText, _handleGetLineText);
    runManager.registerHandler(SdkEditorCommands.getSelectedText, _handleGetSelectedText);
    runManager.registerHandler(SdkEditorCommands.insertText, _handleInsertText);
    runManager.registerHandler(SdkEditorCommands.replaceRange, _handleReplaceRange);
    runManager.registerHandler(SdkEditorCommands.clear, _handleClear);

    // Cursor & Selection
    runManager.registerHandler(SdkEditorCommands.getCursorPosition, _handleGetCursorPosition);
    runManager.registerHandler(SdkEditorCommands.setCursorPosition, _handleSetCursorPosition);
    runManager.registerHandler(SdkEditorCommands.getSelection, _handleGetSelection);
    runManager.registerHandler(SdkEditorCommands.setSelection, _handleSetSelection);
    runManager.registerHandler(SdkEditorCommands.selectAll, _handleSelectAll);
    runManager.registerHandler(SdkEditorCommands.goToLine, _handleGoToLine);

    // Clipboard
    runManager.registerHandler(SdkEditorCommands.copy, _handleCopy);
    runManager.registerHandler(SdkEditorCommands.cut, _handleCut);
    runManager.registerHandler(SdkEditorCommands.paste, _handlePaste);

    // Undo / Redo
    runManager.registerHandler(SdkEditorCommands.undo, _handleUndo);
    runManager.registerHandler(SdkEditorCommands.redo, _handleRedo);
    runManager.registerHandler(SdkEditorCommands.canUndo, _handleCanUndo);
    runManager.registerHandler(SdkEditorCommands.canRedo, _handleCanRedo);

    // Search
    runManager.registerHandler(SdkEditorCommands.find, _handleFind);
    runManager.registerHandler(SdkEditorCommands.findRegex, _handleFindRegex);
    runManager.registerHandler(SdkEditorCommands.clearSearch, _handleClearSearch);

    // Tab Management
    runManager.registerHandler(SdkEditorCommands.openFile, _handleOpenFile);
    runManager.registerHandler(SdkEditorCommands.closeTab, _handleCloseTab);
    runManager.registerHandler(SdkEditorCommands.getCurrentTab, _handleGetCurrentTab);
    runManager.registerHandler(SdkEditorCommands.listTabs, _handleListTabs);

    // Decorations
    runManager.registerHandler(SdkEditorCommands.setGhostText, _handleSetGhostText);
    runManager.registerHandler(SdkEditorCommands.clearGhostText, _handleClearGhostText);
    runManager.registerHandler(SdkEditorCommands.scrollToLine, _handleScrollToLine);
  }

  void _respondOk(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond, {
    dynamic data,
  }) {
    respond({
      'version': '0.0',
      'id': '',
      'type': 'sdk.response.ok',
      'payload': {'data': data},
      'reply_to': envelope['id'],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _respondError(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    String message,
  ) {
    respond({
      'version': '0.0',
      'id': '',
      'type': 'sdk.response.error',
      'payload': {'message': message},
      'reply_to': envelope['id'],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  CodeForgeController? _getController() {
    return ref.read(editorControllerMapProvider.notifier).getSelectedController();
  }

  // ── Text Content ──

  void _handleGetText(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    _respondOk(envelope, respond, data: controller.text);
  }

  void _handleSetText(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final text = payload['text']?.toString() ?? '';
    controller.text = text;
    _respondOk(envelope, respond);
  }

  void _handleGetLineCount(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    _respondOk(envelope, respond, data: controller.lineCount);
  }

  void _handleGetLineText(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final line = payload['line'] as int? ?? 0;
    if (line < 0 || line >= controller.lineCount) {
      _respondError(envelope, respond, '行号越界');
      return;
    }
    _respondOk(envelope, respond, data: controller.getLineText(line));
  }

  void _handleGetSelectedText(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final selection = controller.selection;
    if (!selection.isCollapsed) {
      final start = selection.start;
      final end = selection.end;
      final text = controller.text.substring(
        start.clamp(0, controller.text.length),
        end.clamp(0, controller.text.length),
      );
      _respondOk(envelope, respond, data: text);
    } else {
      _respondOk(envelope, respond, data: '');
    }
  }

  void _handleInsertText(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final text = payload['text']?.toString() ?? '';
    controller.insertAtCurrentCursor(text);
    _respondOk(envelope, respond);
  }

  void _handleReplaceRange(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final start = payload['start'] as int? ?? 0;
    final end = payload['end'] as int? ?? 0;
    final text = payload['text']?.toString() ?? '';
    controller.replaceRange(start, end, text);
    _respondOk(envelope, respond);
  }

  void _handleClear(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    controller.text = '';
    _respondOk(envelope, respond);
  }

  // ── Cursor & Selection ──

  void _handleGetCursorPosition(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final offset = controller.selection.baseOffset;
    final line = controller.getLineAtOffset(offset);
    final lineStart = controller.getLineStartOffset(line);
    final column = offset - lineStart;
    _respondOk(envelope, respond, data: {'line': line, 'column': column});
  }

  void _handleSetCursorPosition(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final line = payload['line'] as int? ?? 0;
    final column = payload['column'] as int? ?? 0;
    final lineStart = controller.getLineStartOffset(line);
    final lineEnd = controller.findLineEnd(lineStart);
    final offset = (lineStart + column).clamp(0, lineEnd);
    controller.setSelectionSilently(TextSelection.collapsed(offset: offset));
    _respondOk(envelope, respond);
  }

  void _handleGetSelection(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final sel = controller.selection;
    _respondOk(envelope, respond, data: {
      'start': sel.start,
      'end': sel.end,
    });
  }

  void _handleSetSelection(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final start = payload['start'] as int? ?? 0;
    final end = payload['end'] as int? ?? 0;
    final len = controller.text.length;
    controller.setSelectionSilently(TextSelection(
      baseOffset: start.clamp(0, len),
      extentOffset: end.clamp(0, len),
    ));
    _respondOk(envelope, respond);
  }

  void _handleSelectAll(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    controller.selectAll();
    _respondOk(envelope, respond);
  }

  void _handleGoToLine(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final line = payload['line'] as int? ?? 0;
    if (line < 0 || line >= controller.lineCount) {
      _respondError(envelope, respond, '行号越界');
      return;
    }
    controller.scrollToLine(line);
    final lineStart = controller.getLineStartOffset(line);
    controller.setSelectionSilently(TextSelection.collapsed(offset: lineStart));
    _respondOk(envelope, respond);
  }

  // ── Clipboard ──

  void _handleCopy(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    controller.copy();
    _respondOk(envelope, respond);
  }

  void _handleCut(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    controller.cut();
    _respondOk(envelope, respond);
  }

  void _handlePaste(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    await controller.paste();
    _respondOk(envelope, respond);
  }

  // ── Undo / Redo ──

  void _handleUndo(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    ref.read(editorControllerMapProvider.notifier).undo();
    _respondOk(envelope, respond);
  }

  void _handleRedo(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    ref.read(editorControllerMapProvider.notifier).redo();
    _respondOk(envelope, respond);
  }

  void _handleCanUndo(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final undoCtrl = ref.read(editorControllerMapProvider.notifier).getSelectedUndoRedoController();
    _respondOk(envelope, respond, data: undoCtrl?.canUndo ?? false);
  }

  void _handleCanRedo(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final undoCtrl = ref.read(editorControllerMapProvider.notifier).getSelectedUndoRedoController();
    _respondOk(envelope, respond, data: undoCtrl?.canRedo ?? false);
  }

  // ── Search ──

  void _handleFind(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final word = payload['word']?.toString() ?? '';
    final matchCase = payload['match_case'] == true;
    final wholeWord = payload['whole_word'] == true;
    controller.findWord(word, matchCase: matchCase, matchWholeWord: wholeWord);
    _respondOk(envelope, respond, data: controller.searchHighlights.length);
  }

  void _handleFindRegex(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final pattern = payload['pattern']?.toString() ?? '';
    try {
      controller.findRegex(RegExp(pattern));
      _respondOk(envelope, respond, data: controller.searchHighlights.length);
    } catch (e) {
      _respondError(envelope, respond, '正则表达式错误: $e');
    }
  }

  void _handleClearSearch(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    controller.clearSearchHighlights();
    _respondOk(envelope, respond);
  }

  // ── Tab Management ──

  void _handleOpenFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();
    if (filePath == null) {
      _respondError(envelope, respond, '缺少 path 参数');
      return;
    }
    final file = File(filePath);
    if (!file.existsSync()) {
      _respondError(envelope, respond, '文件不存在');
      return;
    }
    final context = appContext;
    if (context != null && context.mounted) {
      await ref
          .read(tabbedViewControllerProvider.notifier)
          .openFile(context, file: file);
    }
    _respondOk(envelope, respond);
  }

  void _handleCloseTab(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['path']?.toString();
    if (filePath == null) {
      _respondError(envelope, respond, '缺少 path 参数');
      return;
    }
    final tabs = ref.read(tabbedViewControllerProvider).tabs;
    for (int i = 0; i < tabs.length; i++) {
      final value = tabs[i].value;
      if (value is TabDataValue && value.filePath == filePath) {
        ref.read(tabbedViewControllerProvider.notifier).afterTabClose(i, tabs[i]);
        break;
      }
    }
    _respondOk(envelope, respond);
  }

  void _handleGetCurrentTab(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final tabs = ref.read(tabbedViewControllerProvider);
    final selected = tabs.selectedTab;
    if (selected == null || selected.value is! TabDataValue) {
      _respondOk(envelope, respond, data: null);
      return;
    }
    final value = selected.value as TabDataValue;
    _respondOk(envelope, respond, data: {
      'path': value.filePath,
      'name': value.file?.path.split(RegExp(r'[/\\]')).last,
    });
  }

  void _handleListTabs(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final tabs = ref.read(tabbedViewControllerProvider).tabs;
    final result = <Map<String, String?>>[];
    for (final tab in tabs) {
      if (tab.value is TabDataValue) {
        final value = tab.value as TabDataValue;
        result.add({
          'path': value.filePath,
          'name': value.file?.path.split(RegExp(r'[/\\]')).last,
        });
      }
    }
    _respondOk(envelope, respond, data: result);
  }

  // ── Decorations ──

  void _handleSetGhostText(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final text = payload['text']?.toString() ?? '';
    final line = payload['line'] as int? ?? 0;
    final column = payload['column'] as int? ?? 0;
    controller.setGhostText(GhostText(
      text: text,
      line: line,
      column: column,
    ));
    _respondOk(envelope, respond);
  }

  void _handleClearGhostText(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    controller.clearGhostText();
    _respondOk(envelope, respond);
  }

  void _handleScrollToLine(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final controller = _getController();
    if (controller == null) {
      _respondError(envelope, respond, '没有打开的编辑器');
      return;
    }
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final line = payload['line'] as int? ?? 0;
    controller.scrollToLine(line);
    _respondOk(envelope, respond);
  }

  @override
  void dispose() {
    // Text Content
    state?.unregisterHandler(SdkEditorCommands.getText);
    state?.unregisterHandler(SdkEditorCommands.setText);
    state?.unregisterHandler(SdkEditorCommands.getLineCount);
    state?.unregisterHandler(SdkEditorCommands.getLineText);
    state?.unregisterHandler(SdkEditorCommands.getSelectedText);
    state?.unregisterHandler(SdkEditorCommands.insertText);
    state?.unregisterHandler(SdkEditorCommands.replaceRange);
    state?.unregisterHandler(SdkEditorCommands.clear);
    // Cursor & Selection
    state?.unregisterHandler(SdkEditorCommands.getCursorPosition);
    state?.unregisterHandler(SdkEditorCommands.setCursorPosition);
    state?.unregisterHandler(SdkEditorCommands.getSelection);
    state?.unregisterHandler(SdkEditorCommands.setSelection);
    state?.unregisterHandler(SdkEditorCommands.selectAll);
    state?.unregisterHandler(SdkEditorCommands.goToLine);
    // Clipboard
    state?.unregisterHandler(SdkEditorCommands.copy);
    state?.unregisterHandler(SdkEditorCommands.cut);
    state?.unregisterHandler(SdkEditorCommands.paste);
    // Undo / Redo
    state?.unregisterHandler(SdkEditorCommands.undo);
    state?.unregisterHandler(SdkEditorCommands.redo);
    state?.unregisterHandler(SdkEditorCommands.canUndo);
    state?.unregisterHandler(SdkEditorCommands.canRedo);
    // Search
    state?.unregisterHandler(SdkEditorCommands.find);
    state?.unregisterHandler(SdkEditorCommands.findRegex);
    state?.unregisterHandler(SdkEditorCommands.clearSearch);
    // Tab Management
    state?.unregisterHandler(SdkEditorCommands.openFile);
    state?.unregisterHandler(SdkEditorCommands.closeTab);
    state?.unregisterHandler(SdkEditorCommands.getCurrentTab);
    state?.unregisterHandler(SdkEditorCommands.listTabs);
    // Decorations
    state?.unregisterHandler(SdkEditorCommands.setGhostText);
    state?.unregisterHandler(SdkEditorCommands.clearGhostText);
    state?.unregisterHandler(SdkEditorCommands.scrollToLine);
    super.dispose();
  }
}

final StateNotifierProvider<SdkEditor, PluginRunManager?>
sdkEditorProvider = StateNotifierProvider(
  (ref) => SdkEditor(ref),
);
