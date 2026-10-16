import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';

final lspInitializationProvider =
    FutureProvider.family<bool, CodeForgeController>((ref, controller) async {
      if (controller.lspConfig == null) return false;
      await controller.lspConfig!.initialize();
      return true;
    });

final lspState = Provider<AsyncValue<bool>?>((ref) {
  // Follows the focused group so the status bar reports the editor the user is
  // looking at, not whichever group happens to be the primary one.
  final tabManager = ref.watch(activeEditorControllerProvider);
  // Tabs can be dragged in from the console strip, so a selected tab is not
  // necessarily a document.
  final value = editorTabValueOf(tabManager.selectedTab);
  if (value?.type != 'file') return null;
  final controller = value!.editorController;
  if (controller == null) return null;
  return ref.watch(lspInitializationProvider(controller));
});
