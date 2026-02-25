import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/main.dart';
import 'package:re_editor/re_editor.dart';

void undoAction(WidgetRef ref) {
  if (ref.read(tabbedViewController).selectedTab != null &&
      ref.read(tabbedViewController).selectedTab!.value.type == "file") {
    CodeLineEditingController editorController = ref
        .read(tabbedViewController)
        .selectedTab!
        .value
        .editorController!;
    editorController.undo();
  }
}

void redoAction(WidgetRef ref) {
  if (ref.read(tabbedViewController).selectedTab != null &&
      ref.read(tabbedViewController).selectedTab!.value.type == "file") {
    CodeLineEditingController editorController = ref
        .read(tabbedViewController)
        .selectedTab!
        .value
        .editorController!;
    editorController.redo();
  }
}

void cutAction(WidgetRef ref) {
  if (ref.read(tabbedViewController).selectedTab != null &&
      ref.read(tabbedViewController).selectedTab!.value.type == "file") {
    CodeLineEditingController editorController = ref
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
    CodeLineEditingController editorController = ref
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
    CodeLineEditingController editorController = ref
        .read(tabbedViewController)
        .selectedTab!
        .value
        .editorController!;
    editorController.paste();
  }
}

void moveCursorToLineStartAction(WidgetRef ref) {
  if (ref.read(tabbedViewController).selectedTab != null &&
      ref.read(tabbedViewController).selectedTab!.value.type == "file") {
    CodeLineEditingController editorController = ref
        .read(tabbedViewController)
        .selectedTab!
        .value
        .editorController!;
    editorController.moveCursorToLineStart();
  }
}

void moveCursorToLineEndAction(WidgetRef ref) {
  if (ref.read(tabbedViewController).selectedTab != null &&
      ref.read(tabbedViewController).selectedTab!.value.type == "file") {
    CodeLineEditingController editorController = ref
        .read(tabbedViewController)
        .selectedTab!
        .value
        .editorController!;
    editorController.moveCursorToLineEnd();
  }
}

void moveCursorToPageStartAction(WidgetRef ref) {
  if (ref.read(tabbedViewController).selectedTab != null &&
      ref.read(tabbedViewController).selectedTab!.value.type == "file") {
    CodeLineEditingController editorController = ref
        .read(tabbedViewController)
        .selectedTab!
        .value
        .editorController!;
    editorController.moveCursorToPageStart();
  }
}

void moveCursorToPageEndAction(WidgetRef ref) {
  if (ref.read(tabbedViewController).selectedTab != null &&
      ref.read(tabbedViewController).selectedTab!.value.type == "file") {
    CodeLineEditingController editorController = ref
        .read(tabbedViewController)
        .selectedTab!
        .value
        .editorController!;
    editorController.moveCursorToPageEnd();
  }
}
