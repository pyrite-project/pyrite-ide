import 'dart:io';
import 'package:code_forge/LSP/lsp.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';

class EditorControllerMapNotifier
    extends StateNotifier<Map<String, CodeForgeController>> {
  final Ref ref;
  EditorControllerMapNotifier(this.ref) : super({});

  Future<CodeForgeController?> createNewEditorController(File file) async {
    String pattern = "\\";

    if (Platform.isWindows) {
      pattern = "\\";
    } else {
      pattern = "/";
    }
    String initialText = "";
    try {
      initialText = await file.readAsString();
    } on FileSystemException {
      return null;
    }
    final uri = Uri.file(file.path).toString().split(pattern);
    // final fileName = uri.removeLast();
    uri.removeLast();
    final workspacePath = uri.join(pattern);
    CodeForgeController controller = CodeForgeController(
      lspConfig: (ref.read(useLsp))
          ? LspSocketConfig(
              workspacePath: workspacePath,
              languageId: "python",
              serverUrl: "ws://${ref.read(lspWebScoketPath)}",
              disableWarning: ref.read(disableWarning),
              disableError: ref.read(disableError),
            )
          : null,
    );
    controller.text = initialText;
    controller.openedFile = file.path;
    state = {...state, file.path: controller};
    return controller;
  }

  void redo() {
    if (ref.read(tabbedViewControllerProvider).selectedTab != null &&
        ref.read(tabbedViewControllerProvider).selectedTab!.value.type ==
            "file") {}
  }

  void undo() {
    if (ref.read(tabbedViewControllerProvider).selectedTab != null &&
        ref.read(tabbedViewControllerProvider).selectedTab!.value.type ==
            "file") {}
  }

  void cut() {
    if (ref.read(tabbedViewControllerProvider).selectedTab != null &&
        ref.read(tabbedViewControllerProvider).selectedTab!.value.type ==
            "file") {
      CodeForgeController editorController = ref
          .read(tabbedViewControllerProvider)
          .selectedTab!
          .value
          .editorController!;
      editorController.cut();
    }
  }

  void copy() {
    if (ref.read(tabbedViewControllerProvider).selectedTab != null &&
        ref.read(tabbedViewControllerProvider).selectedTab!.value.type ==
            "file") {
      CodeForgeController editorController = ref
          .read(tabbedViewControllerProvider)
          .selectedTab!
          .value
          .editorController!;
      editorController.copy();
    }
  }

  void paste() {
    if (ref.read(tabbedViewControllerProvider).selectedTab != null &&
        ref.read(tabbedViewControllerProvider).selectedTab!.value.type ==
            "file") {
      CodeForgeController editorController = ref
          .read(tabbedViewControllerProvider)
          .selectedTab!
          .value
          .editorController!;
      editorController.paste();
    }
  }
}

final StateNotifierProvider<
  EditorControllerMapNotifier,
  Map<String, CodeForgeController>
>
editorControllerMapProvider = StateNotifierProvider(
  (ref) => EditorControllerMapNotifier(ref),
);
