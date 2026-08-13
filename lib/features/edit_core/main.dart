import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:pyrite_ide/core/constants/editor_themes.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
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
import 'package:re_highlight/languages/python.dart';

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
    if (pendingUploadProviderMap[widget.file.path] == null) {
      pendingUploadProviderMap[widget.file.path] = StateProvider((ref) => null);
    }
    if (pendingDownloadProviderMap[widget.file.path] == null) {
      pendingDownloadProviderMap[widget.file.path] = StateProvider(
        (ref) => null,
      );
    }
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
      SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
        _openFind();
      },
      SingleActivator(LogicalKeyboardKey.keyH, meta: true): () {
        _openFind(replace: true);
      },
    };

    if (pending != null || pendingDownload != null) {
      bindings[stringToActivator(confirmAct)] = () =>
          _handleConfirm(context, ref);
      bindings[stringToActivator(cancelAct)] = () =>
          _handleCancel(context, ref);
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
                        semanticLabel: '',
                      ),
                      M3FloatingToolbarAction(
                        icon: Icons.cloud_upload,
                        label: translateForWidget(
                          ref,
                          I18nKey.editorConfirmUpload,
                        ),
                        onPressed: () => _confirmUpload(ref, pending, context),
                        semanticLabel: '',
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
                        semanticLabel: '',
                      ),
                      M3FloatingToolbarAction(
                        icon: Icons.cloud_download,
                        label: translateForWidget(
                          ref,
                          I18nKey.editorConfirmDownload,
                        ),
                        onPressed: () =>
                            _confirmDownload(ref, pendingDownload, context),
                        semanticLabel: '',
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
    final themeKey = ref.watch(editorThemeKey);
    final entry = findEditorThemeByKey(themeKey) ?? editorThemes.first;
    final brightness = Theme.of(context).brightness;
    final surface = Theme.of(context).scaffoldBackgroundColor;
    final activeThemeId = ref.watch(activePluginThemeId);
    final registry = ref.watch(dataRegistryProvider);
    final pluginTheme = activeThemeId == null
        ? null
        : registry.getThemeById(activeThemeId);
    final editorStyles = pluginTheme?.editorStyles(brightness);
    final pluginEditorThemeActive = pluginTheme?.hasEditorStyles ?? false;
    final resolvedTheme = applySurfaceBackground(
      resolveActiveEditorTheme(
        entry,
        brightness,
        pluginStyles: editorStyles,
        pluginThemeActive: pluginEditorThemeActive,
      ),
      surface,
    );
    final editorForeground =
        resolvedTheme['root']?.color ?? Theme.of(context).colorScheme.onSurface;
    final editorBackground = resolvedTheme['root']?.backgroundColor ?? surface;
    final hoverBackground = Color.alphaBlend(
      editorForeground.withAlpha(18),
      editorBackground,
    ).withAlpha(255);
    return CodeForge(
      key: ValueKey(
        '${pluginEditorThemeActive ? '' : themeKey}_${activeThemeId ?? ''}_${editorStyles}_${brightness.name}_${surface.toARGB32()}',
      ),
      filePath: widget.file.path,
      editorTheme: resolvedTheme,
      findController: _findController,
      customContextMenuItems: _editorContextMenuItems(ref),
      onModifierTap: (offset) =>
          unawaited(_goToDefinition(context, ref, textOffset: offset)),
      finderBuilder: (_, controller) => _EditorFindBar(
        controller: controller,
        foreground: editorForeground,
        background: editorBackground,
      ),
      hoverDetailsStyle: HoverDetailsStyle(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: editorForeground.withAlpha(80)),
        ),
        backgroundColor: hoverBackground,
        focusColor: Theme.of(context).colorScheme.primary.withAlpha(50),
        hoverColor: Theme.of(context).colorScheme.primary.withAlpha(25),
        splashColor: Theme.of(context).colorScheme.primary.withAlpha(50),
        textStyle: TextStyle(
          color: editorForeground,
          fontSize: ref.watch(editorFontSize),
          fontFamily: editorTextFonts[ref.watch(editorTextFontProvider)],
        ),
      ),
      language: langPython,
      controller: widget.editorController,
      undoController: widget.undoController,
      matchHighlightStyle: const MatchHighlightStyle(
        currentMatchStyle: TextStyle(backgroundColor: Color(0xFFFFA726)),
        otherMatchStyle: TextStyle(backgroundColor: Color(0x55FFFF00)),
      ),
      textStyle: TextStyle(
        fontSize: ref.watch(editorFontSize),
        fontFamily: editorTextFonts[ref.watch(editorTextFontProvider)],
      ),
      lineWrap: ref.watch(editorWordWrap),
      enableFolding: ref.watch(editorCodeFolding),
      enableGuideLines: ref.watch(editorGuideLines),
      enableLocalSuggestions: ref.watch(editorLocalSuggestions),
      enableKeyboardSuggestions: ref.watch(editorKeyboardSuggestions),
      enableGutter: ref.watch(editorLineNumber),
      enableGutterDivider: ref.watch(editorGutterDivider),
      useSpaceAsTab: ref.watch(editorUseSpaceAsTab),
      tabSize: ref.watch(editorTabSize),
      gutterBuilder: GutterBuilder(
        builder: (lineNumber, lineText) => '$lineNumber',
        includeReplacedIndex: false,
      ),
      contextMenuBuilder: (context, details) {
        return _EditorContextMenu(details: details);
      },
    );
  }

  void _openFind({bool replace = false}) {
    _findController
      ..isActive = true
      ..isReplaceMode = replace;
  }

  List<CustomContextMenu> _editorContextMenuItems(WidgetRef ref) {
    final controller = widget.editorController;
    final config = controller.lspConfig;
    final items = <CustomContextMenu>[
      CustomContextMenu(
        label: '搜索',
        description: 'Ctrl+F',
        icon: Icons.search,
        onPress: _openFind,
      ),
    ];
    if (config == null) return items;
    if (config.capabilities.goToDefinition) {
      items.add(
        CustomContextMenu(
          label: '跳转到实现',
          description: 'LSP',
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
          description: 'F2',
          icon: Icons.drive_file_rename_outline,
          visibleAt: (offset) => _isSymbolAtOffset(controller, offset),
          onPressAt: (offset) =>
              unawaited(_renameSymbol(context, ref, textOffset: offset)),
          onPress: () => unawaited(_renameSymbol(context, ref)),
        ),
      );
    }
    return items;
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
    final targetPath = targetUri.toFilePath();
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
    final start = range['start'];
    if (targetController == null || start is! Map) return;
    final targetLine = (start['line'] as num?)?.toInt();
    final targetCharacter = (start['character'] as num?)?.toInt();
    if (targetLine == null || targetCharacter == null) return;
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

  bool _hasLocation(dynamic location) {
    if (location is List) location = location.firstOrNull;
    return location is Map &&
        (location['uri'] != null || location['targetUri'] != null);
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
      await controller.applyWorkspaceEdit(
        edit.containsKey('changes') ? {'edit': edit} : edit,
      );
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
    } catch (_) {
      ref
          .read(ideMessageProvider.notifier)
          .error(translateForWidget(ref, I18nKey.editorUploadFailed));
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
    } catch (_) {
      ref
          .read(ideMessageProvider.notifier)
          .error(translateForWidget(ref, I18nKey.editorDownloadFailed));
    } finally {
      ref.read(pendingDownloadProviderMap[widget.file.path]!.notifier).state =
          null;
      if (context.mounted) context.go('/file');
    }
  }
}

class _EditorFindBar extends StatelessWidget implements PreferredSizeWidget {
  const _EditorFindBar({
    required this.controller,
    required this.foreground,
    required this.background,
  });

  final FindController controller;
  final Color foreground;
  final Color background;

  @override
  Size get preferredSize => Size.fromHeight(controller.isReplaceMode ? 76 : 40);

  @override
  Widget build(BuildContext context) {
    final border = foreground.withAlpha(70);
    return Material(
      color: background,
      child: SizedBox(
        height: preferredSize.height,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FindBarRow(
              children: [
                _button(
                  controller.isReplaceMode
                      ? Icons.expand_more
                      : Icons.chevron_right,
                  controller.isReplaceMode ? '隐藏替换' : '显示替换',
                  controller.toggleReplaceMode,
                  enabled: true,
                ),
                Icon(Icons.search, size: 18, color: foreground),
                const SizedBox(width: 6),
                Expanded(
                  child: _textField(
                    controller: controller.findInputController,
                    focusNode: controller.findInputFocusNode,
                    border: border,
                    onSubmitted: (_) => controller.next(),
                  ),
                ),
                _matchCounter(),
                _button(Icons.keyboard_arrow_up, '上一个', controller.previous),
                _button(Icons.keyboard_arrow_down, '下一个', controller.next),
                _button(
                  Icons.close,
                  '关闭',
                  () => controller.isActive = false,
                  enabled: true,
                ),
              ],
            ),
            if (controller.isReplaceMode)
              _FindBarRow(
                children: [
                  const SizedBox(width: 32),
                  Icon(Icons.find_replace, size: 18, color: foreground),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _textField(
                      controller: controller.replaceInputController,
                      focusNode: controller.replaceInputFocusNode,
                      border: border,
                      onSubmitted: (_) => controller.replace(),
                    ),
                  ),
                  const SizedBox(width: 52),
                  _button(Icons.find_replace, '替换', controller.replace),
                  _button(Icons.done_all, '全部替换', controller.replaceAll),
                  const SizedBox(width: 32),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required Color border,
    required ValueChanged<String> onSubmitted,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: 1,
      style: TextStyle(color: foreground, fontSize: 13),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: foreground.withAlpha(150)),
        ),
      ),
    );
  }

  Widget _matchCounter() {
    return SizedBox(
      width: 52,
      child: Text(
        controller.matchCount == 0
            ? '0/0'
            : '${controller.currentMatchIndex + 1}/${controller.matchCount}',
        textAlign: TextAlign.center,
        style: TextStyle(color: foreground, fontSize: 12),
      ),
    );
  }

  Widget _button(
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    bool? enabled,
  }) {
    final isEnabled = enabled ?? controller.matchCount > 0;
    return IconButton(
      tooltip: tooltip,
      onPressed: isEnabled ? onPressed : null,
      icon: Icon(icon, size: 18),
      color: foreground,
      disabledColor: foreground.withAlpha(70),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    );
  }
}

class _FindBarRow extends StatelessWidget {
  const _FindBarRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 4),
          ...children,
          const SizedBox(width: 4),
        ],
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
  await ref.read(fileProvider.notifier).saveCurrentFile();

  if (!quiet) {
    ref
        .read(ideMessageProvider.notifier)
        .success(translateForWidget(ref, I18nKey.statusSavedCurrentFile));
  }
}

class _EditorContextMenu extends StatelessWidget {
  const _EditorContextMenu({required this.details});

  final CodeForgeContextMenuDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      elevation: 8,
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (details.hasSelection && !details.readOnly)
                _menuItem(
                  icon: Icons.cut,
                  label: '剪切',
                  shortcut: 'Ctrl+X',
                  onTap: () {
                    details.controller.cut();
                    details.close();
                  },
                ),

              if (details.hasSelection)
                _menuItem(
                  icon: Icons.copy,
                  label: '复制',
                  shortcut: 'Ctrl+C',
                  onTap: () {
                    details.controller.copy();
                    details.close();
                  },
                ),

              if (!details.readOnly)
                _menuItem(
                  icon: Icons.paste,
                  label: '粘贴',
                  shortcut: 'Ctrl+V',
                  onTap: () async {
                    await details.controller.paste();
                    details.close();
                  },
                ),

              _menuItem(
                icon: Icons.select_all,
                label: '全选',
                shortcut: 'Ctrl+A',
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
          ),
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: icon == null ? null : Icon(icon, size: 16),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (shortcut.isNotEmpty) ...[
              const SizedBox(width: 24),
              Text(shortcut, style: const TextStyle(fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}
