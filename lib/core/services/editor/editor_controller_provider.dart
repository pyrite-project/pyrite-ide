import 'dart:async';
import 'dart:io';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/editor/code_forge_controller.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_config.dart';
import 'package:pyrite_ide/core/services/editor/lsp_workspace_path.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/workspace_lsp_config_pool.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:path/path.dart' as path;

/// The language id sent to the language server for every document.
///
/// The language id is no longer a setting: this IDE ships one Python language
/// server integration, and the document language shown to the user comes from
/// the per-file grammar in `editor_language.dart` instead. Anything that wants
/// a second language server needs a per-language server mapping, not a single
/// global id.
const String defaultLspLanguageId = 'python';

/// Files larger than this open read-only.
///
/// Multi-megabyte text files are logs or data dumps rather than code; editing
/// a document that size makes every keystroke and caret move traverse the
/// whole buffer. The full content is still loaded — a truncated preview could
/// be written back over the real file on save — but the editor is marked
/// read-only so it is never offered as editable.
const int maxEditableFileLength = 5 * 1024 * 1024;

class EditorControllerMapNotifier
    extends StateNotifier<Map<String, CodeForgeController>> {
  final Ref ref;
  EditorControllerMapNotifier(this.ref) : super({}) {
    ref.listen<bool>(lspDocumentColor, (_, enabled) {
      _updateDocumentColorPicker(enabled);
    });
    ref.listen<bool>(lspShowInlayHints, (_, visible) {
      _updateInlayHintsVisibility(visible);
    });
  }

  /// One language server per workspace root, shared by every open file under
  /// it.
  ///
  /// Each editor used to start its own server, so a session with N tabs kept
  /// N identical processes alive and restored sessions serialized N server
  /// startups. The pool refcounts controllers; [removePath] releases a tab's
  /// seat, and only the last one under a workspace root stops the server.
  ///
  /// Capabilities and stub settings are captured when the workspace's first
  /// file opens and stay fixed until its last file closes — the same
  /// negotiation window a real IDE has with one server per project.
  late final WorkspaceLspConfigPool<LspConfig> _lspConfigPool =
      WorkspaceLspConfigPool<LspConfig>(
        create: _createWorkspaceLspConfig,
        onEvict: (config) => config.dispose(),
      );

  Future<CodeForgeController?> createNewEditorController(
    File file, {
    String? initialText,
  }) async {
    String text = initialText ?? "";
    var openedReadOnly = false;
    if (initialText == null) {
      try {
        if (await file.length() > maxEditableFileLength) {
          openedReadOnly = true;
        }
        text = await file.readAsString();
      } on FileSystemException {
        return null;
      }
    }
    final projectPath = lspWorkspacePathForFile(file, ref.read(fileProvider));

    LspConfig? lspConfig;
    if (ref.read(useLsp) &&
        (path.extension(file.path) == ".py" || ref.read(lspAlwaysStart))) {
      final acquired = await _lspConfigPool.acquire(projectPath);
      lspConfig = acquired.config;
      if (lspConfig != null && acquired.created) {
        unawaited(_sendWorkspaceConfiguration(lspConfig));
      }
    }

    CodeForgeController controller = PyriteCodeForgeController(
      lspConfig: lspConfig,
    );
    // Bind the path before the buffer. The editor widget only assigns
    // `openedFile` itself when it finds the path unset, and that assignment
    // re-reads the file from disk — which would clobber a restored unsaved
    // buffer with the stale on-disk text. The setter's own synchronous read
    // happens here, before `text` replaces it with the intended content; this
    // mirrors the preview pane in lsp_location_dialog, which pre-sets
    // `openedFile` for the same reason.
    controller.openedFile = file.path;
    controller.text = text;
    if (openedReadOnly) {
      controller.readOnly = true;
      ref
          .read(ideMessageProvider.notifier)
          .show(
            translate(
              ref,
              I18nKey.editorFileTooLargeReadOnly,
            ).replaceAll('{path}', file.path),
            type: IdeMessageType.warning,
            duration: const Duration(seconds: 12),
            closeable: true,
          );
    }
    state = {...state, file.path: controller};
    controller.setDocumentColorsEnabled(ref.read(lspDocumentColor));
    if (ref.read(lspShowInlayHints)) {
      unawaited(_showInlayHintsWhenReady(controller));
    }
    return controller;
  }

  /// Builds a fresh LSP configuration for [workspacePath].
  ///
  /// Runs at most once per workspace at a time; the pool hands the result to
  /// every controller opened under the same root. Returning null (no
  /// executable configured, or the server failed to start) leaves the file's
  /// editor fully offline.
  Future<LspConfig?> _createWorkspaceLspConfig(String workspacePath) async {
    final type = ref.read(lspType);
    final capabilities = LspClientCapabilities(
      semanticHighlighting: ref.read(lspSemanticHighlighting),
      codeCompletion: ref.read(lspCodeCompletion),
      hoverInfo: ref.read(lspHoverInfo),
      codeAction: ref.read(lspCodeAction),
      signatureHelp: ref.read(lspSignatureHelp),
      documentColor: ref.read(lspDocumentColor),
      documentHighlight: ref.read(lspDocumentHighlight),
      codeFolding: ref.read(lspCodeFolding),
      inlayHint: ref.read(lspShowInlayHints),
      goToDefinition: ref.read(lspGoToDefinition),
      rename: ref.read(lspRename),
    );
    final stubsConfig = buildLspStubsConfig(
      ref.read,
      workspacePath: workspacePath,
    );
    if (stubsConfig.paths.isNotEmpty) {
      ref
          .read(ideOutputLogProvider.notifier)
          .add(
            IdeOutputSource.ide,
            'LSP stubs paths: ${stubsConfig.paths.join(Platform.pathSeparator)}',
          );
    }
    if (stubsConfig.virtualEnvironment.isNotEmpty) {
      ref
          .read(ideOutputLogProvider.notifier)
          .add(
            IdeOutputSource.ide,
            'LSP virtual environment: ${stubsConfig.virtualEnvironment}',
          );
    }
    if (type == LspType.webSocket) {
      return LspSocketConfig(
        workspacePath: workspacePath,
        languageId: defaultLspLanguageId,
        serverUrl: "ws://${ref.read(lspWebSocketPath)}",
        capabilities: capabilities,
        initializationOptions: stubsConfig.initializationOptions,
        workspaceConfiguration: stubsConfig.workspaceConfiguration,
        disableWarning: ref.read(disableWarning),
        disableError: ref.read(disableError),
      );
    }
    if (type == LspType.stdio) {
      final executable = ref.read(lspStdioExecutable).trim();
      if (executable.isEmpty) return null;
      final argsStr = ref.read(lspStdioArgs).trim();
      final args = argsStr.split(' ').where((s) => s.isNotEmpty).toList();
      try {
        return await LspStdioConfig.start(
          executable: executable,
          args: args,
          workspacePath: workspacePath,
          languageId: defaultLspLanguageId,
          capabilities: capabilities,
          initializationOptions: stubsConfig.initializationOptions,
          workspaceConfiguration: stubsConfig.workspaceConfiguration,
          environment: stubsConfig.environment,
          disableWarning: ref.read(disableWarning),
          disableError: ref.read(disableError),
        );
      } catch (e) {
        debugPrint('LSP stdio start failed: $e');
        ref
            .read(ideOutputLogProvider.notifier)
            .add(
              IdeOutputSource.ide,
              translate(
                ref,
                I18nKey.lspStartFailedOutput,
              ).replaceAll('{error}', e.toString()),
            );
        return null;
      }
    }
    return null;
  }

  void _updateInlayHintsVisibility(bool visible) {
    for (final controller in state.values) {
      if (visible) {
        unawaited(_showInlayHintsWhenReady(controller));
      } else {
        controller.hideInlayHints();
      }
    }
  }

  void _updateDocumentColorPicker(bool enabled) {
    for (final controller in state.values) {
      controller.setDocumentColorsEnabled(enabled, force: enabled);
    }
  }

  Future<void> _showInlayHintsWhenReady(CodeForgeController controller) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      if (!ref.read(lspShowInlayHints)) return;
      final lspConfig = controller.lspConfig;
      if (lspConfig?.isInitialized == true && controller.openedFile != null) {
        await controller.showInlayHints(readOnly: false);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _sendWorkspaceConfiguration(LspConfig lspConfig) async {
    if (lspConfig.workspaceConfiguration.isEmpty) return;
    for (var attempt = 0; attempt < 30; attempt++) {
      if (lspConfig.isInitialized) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!lspConfig.isInitialized) return;
    try {
      ref
          .read(ideOutputLogProvider.notifier)
          .add(
            IdeOutputSource.ide,
            'LSP workspace configuration: ${lspConfig.workspaceConfiguration}',
          );
      await lspConfig.sendNotification(
        method: 'workspace/didChangeConfiguration',
        params: {'settings': lspConfig.workspaceConfiguration},
      );
    } catch (error) {
      debugPrint('LSP workspace configuration failed: $error');
    }
  }

  UndoRedoController createNewUndoRedoController() {
    return UndoRedoController();
  }

  void movePath(String oldPath, String newPath) {
    if (oldPath == newPath) return;
    final controller = state[oldPath];
    if (controller == null) return;
    final next = Map<String, CodeForgeController>.from(state)
      ..remove(oldPath)
      ..[newPath] = controller;
    state = next;
  }

  /// Drops the controller registered for [filePath] from the map.
  ///
  /// Disposing the controller itself is left to the caller so tab teardown
  /// stays in one place. The controller's seat on its workspace's shared
  /// language server is released here; the server is stopped only when the
  /// last controller under that workspace root goes away.
  void removePath(String filePath) {
    if (!state.containsKey(filePath)) return;
    _lspConfigPool.release(state[filePath]?.lspConfig);
    state = Map<String, CodeForgeController>.from(state)..remove(filePath);
  }

  void redo() {
    if (ref.read(tabbedViewControllerProvider).selectedTab != null &&
        ref.read(tabbedViewControllerProvider).selectedTab!.value.type ==
            "file") {
      getSelectedUndoRedoController()?.redo();
    }
  }

  void undo() {
    if (ref.read(tabbedViewControllerProvider).selectedTab != null &&
        ref.read(tabbedViewControllerProvider).selectedTab!.value.type ==
            "file") {
      getSelectedUndoRedoController()?.undo();
    }
  }

  void cut() {
    if (ref.read(tabbedViewControllerProvider).selectedTab != null &&
        ref.read(tabbedViewControllerProvider).selectedTab!.value.type ==
            "file") {
      getSelectedController()?.cut();
    }
  }

  void copy() {
    if (ref.read(tabbedViewControllerProvider).selectedTab != null &&
        ref.read(tabbedViewControllerProvider).selectedTab!.value.type ==
            "file") {
      getSelectedController()?.copy();
    }
  }

  void paste() {
    if (ref.read(tabbedViewControllerProvider).selectedTab != null &&
        ref.read(tabbedViewControllerProvider).selectedTab!.value.type ==
            "file") {
      getSelectedController()?.paste();
    }
  }

  CodeForgeController? getSelectedController() {
    return ref
        .read(tabbedViewControllerProvider)
        .selectedTab
        ?.value
        .editorController;
  }

  UndoRedoController? getSelectedUndoRedoController() {
    debugPrint(
      ref
          .read(tabbedViewControllerProvider)
          .selectedTab
          ?.value
          .undoRedoController,
    );
    return ref
        .read(tabbedViewControllerProvider)
        .selectedTab
        ?.value
        .undoRedoController;
  }
}

final StateNotifierProvider<
  EditorControllerMapNotifier,
  Map<String, CodeForgeController>
>
editorControllerMapProvider = StateNotifierProvider(
  (ref) => EditorControllerMapNotifier(ref),
);
