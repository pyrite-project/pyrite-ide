import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/main.dart';

void undoAction(WidgetRef ref) {
  if (ref.read(tabbedViewController).selectedTab != null &&
      ref.read(tabbedViewController).selectedTab!.value.type == "file") {
    /*
    CodeForgeController editorController = ref
        .read(tabbedViewController)
        .selectedTab!
        .value
        .editorController!;
    editorController.undo();
    */
  }
}

void redoAction(WidgetRef ref) {
  if (ref.read(tabbedViewController).selectedTab != null &&
      ref.read(tabbedViewController).selectedTab!.value.type == "file") {
    /*
    CodeForgeController editorController = ref
        .read(tabbedViewController)
        .selectedTab!
        .value
        .editorController!;
    editorController.redo();
    */
  }
}

void cutAction(WidgetRef ref) {
  if (ref.read(tabbedViewController).selectedTab != null &&
      ref.read(tabbedViewController).selectedTab!.value.type == "file") {
    CodeForgeController editorController = ref
        .read(tabbedViewController)
        .selectedTab!
        .value
        .editorController!;
    editorController.cut();
  }
}

void copyAction(WidgetRef ref) {
  if (ref.read(tabbedViewController).selectedTab != null &&
      ref.read(tabbedViewController).selectedTab!.value.type == "file") {
    CodeForgeController editorController = ref
        .read(tabbedViewController)
        .selectedTab!
        .value
        .editorController!;
    editorController.copy();
  }
}

void pasteAction(WidgetRef ref) {
  if (ref.read(tabbedViewController).selectedTab != null &&
      ref.read(tabbedViewController).selectedTab!.value.type == "file") {
    CodeForgeController editorController = ref
        .read(tabbedViewController)
        .selectedTab!
        .value
        .editorController!;
    editorController.paste();
  }
}
