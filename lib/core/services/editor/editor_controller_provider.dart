import 'dart:async';
import 'dart:io';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_config.dart';
import 'package:pyrite_ide/core/services/editor/lsp_workspace_path.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:path/path.dart' as path;

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

  Future<CodeForgeController?> createNewEditorController(
    File file, {
    String? initialText,
  }) async {
    String text = initialText ?? "";
    if (initialText == null) {
      try {
        text = await file.readAsString();
      } on FileSystemException {
        return null;
      }
    }
    final projectPath = lspWorkspacePathForFile(file, ref.read(fileProvider));
    final languageId = ref.read(lspLanguageId).trim();

    LspConfig? lspConfig;
    if (ref.read(useLsp) &&
        languageId.isNotEmpty &&
        (path.extension(file.path) == ".py" || ref.read(lspAlwaysStart))) {
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
        workspacePath: projectPath,
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
        lspConfig = LspSocketConfig(
          workspacePath: projectPath,
          languageId: languageId,
          serverUrl: "ws://${ref.read(lspWebSocketPath)}",
          capabilities: capabilities,
          initializationOptions: stubsConfig.initializationOptions,
          workspaceConfiguration: stubsConfig.workspaceConfiguration,
          disableWarning: ref.read(disableWarning),
          disableError: ref.read(disableError),
        );
      } else if (type == LspType.stdio) {
        final executable = ref.read(lspStdioExecutable).trim();
        if (executable.isNotEmpty) {
          final argsStr = ref.read(lspStdioArgs).trim();
          final args = argsStr.split(' ').where((s) => s.isNotEmpty).toList();
          try {
            lspConfig = await LspStdioConfig.start(
              executable: executable,
              args: args,
              workspacePath: projectPath,
              languageId: languageId,
              capabilities: capabilities,
              initializationOptions: stubsConfig.initializationOptions,
              workspaceConfiguration: stubsConfig.workspaceConfiguration,
              environment: stubsConfig.environment,
              disableWarning: ref.read(disableWarning),
              disableError: ref.read(disableError),
            );
          } catch (e) {
            debugPrint('LSP stdio start failed: $e');
          }
        }
      }
    }

    CodeForgeController controller = CodeForgeController(lspConfig: lspConfig);
    if (lspConfig != null) {
      unawaited(_sendWorkspaceConfiguration(lspConfig));
    }
    // controller.openedFile = file.path;
    controller.text = text;
    state = {...state, file.path: controller};
    controller.setDocumentColorsEnabled(ref.read(lspDocumentColor));
    if (ref.read(lspShowInlayHints)) {
      unawaited(_showInlayHintsWhenReady(controller));
    }
    return controller;
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
