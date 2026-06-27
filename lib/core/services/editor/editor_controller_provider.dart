import 'dart:io';
import 'package:code_forge/code_forge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
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
    // controller.openedFile = file.path;
    controller.text = text;
    state = {...state, file.path: controller};
    return controller;
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
    print(
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
