import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';

final Provider undoAction = Provider((ref) {
  if (ref.read(tabbedViewControllerProvider).selectedTab != null &&
      ref.read(tabbedViewControllerProvider).selectedTab!.value.type ==
          "file") {}
});

final Provider redoAction = Provider((ref) {
  if (ref.read(tabbedViewControllerProvider).selectedTab != null &&
      ref.read(tabbedViewControllerProvider).selectedTab!.value.type ==
          "file") {}
});

final Provider cutAction = Provider((ref) {
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
});

final Provider copyAction = Provider((ref) {
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
});

final Provider pasteAction = Provider((ref) {
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
});
