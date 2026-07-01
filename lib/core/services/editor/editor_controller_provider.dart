import 'dart:async';
import 'dart:io';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_config.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/settings.dart';

class EditorControllerMapNotifier
    extends StateNotifier<Map<String, CodeForgeController>> {
  final Ref ref;
  EditorControllerMapNotifier(this.ref) : super({});

  Future<CodeForgeController?> createNewEditorController(
    File file, {
    String? initialText,
  }) async {
    String pattern = "\\";

    if (Platform.isWindows) {
      pattern = "\\";
    } else {
      pattern = "/";
    }
    String text = initialText ?? "";
    if (initialText == null) {
      try {
        text = await file.readAsString();
      } on FileSystemException {
        return null;
      }
    }
    final uri = Uri.file(file.path).toString().split(pattern);
    // final fileName = uri.removeLast();
    uri.removeLast();
    final projectPath = uri.join(pattern);

    LspConfig? lspConfig;
    if (ref.read(useLsp)) {
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
        inlayHint: ref.read(lspInlayHint),
        goToDefinition: ref.read(lspGoToDefinition),
        rename: ref.read(lspRename),
      );
      final stubsConfig = buildLspStubsConfig(ref);
      if (stubsConfig.paths.isNotEmpty) {
        ref.read(ideOutputLogProvider.notifier).add(
          IdeOutputSource.ide,
          'LSP stubs paths: ${stubsConfig.paths.join(Platform.pathSeparator)}',
        );
      }
      if (type == LspType.webSocket) {
        lspConfig = LspSocketConfig(
          workspacePath: projectPath,
          languageId: "python",
          serverUrl: "ws://${ref.read(lspWebSocketPath)}",
          capabilities: capabilities,
          initializationOptions: stubsConfig.initializationOptions,
          workspaceConfiguration: stubsConfig.workspaceConfiguration,
          disableWarning: ref.read(disableWarning),
          disableError: ref.read(disableError),
        );
      } else if (type == LspType.stdio) {
        final executable = ref.read(lspStdioExecutable);
        if (executable.isNotEmpty) {
          final argsStr = ref.read(lspStdioArgs);
          final args = argsStr
              .split(' ')
              .where((s) => s.isNotEmpty)
              .toList();
          try {
            lspConfig = await LspStdioConfig.start(
              executable: executable,
              args: args,
              workspacePath: projectPath,
              languageId: "python",
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

    CodeForgeController controller = CodeForgeController(
      lspConfig: lspConfig,
    );
    if (lspConfig != null) {
      unawaited(_sendWorkspaceConfiguration(lspConfig));
    }
    // controller.openedFile = file.path;
    controller.text = text;
    state = {...state, file.path: controller};
    return controller;
  }

  Future<void> _sendWorkspaceConfiguration(LspConfig lspConfig) async {
    if (lspConfig.workspaceConfiguration.isEmpty) return;
    for (var attempt = 0; attempt < 30; attempt++) {
      if (lspConfig.isInitialized) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!lspConfig.isInitialized) return;
    try {
      ref.read(ideOutputLogProvider.notifier).add(
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
