import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';

final lspInitializationProvider =
    FutureProvider.family<bool, CodeForgeController>((ref, controller) async {
      if (controller.lspConfig == null) return false;
      await controller.lspConfig!.initialize();
      return true;
    });

final lspState = Provider<AsyncValue<bool>?>((ref) {
  // Follows the focused group's selected tab, so the status bar reports the
  // editor the user is looking at -- and moves when they switch tabs inside a
  // group, which changes the group in place.
  final value = ref.watch(activeEditorTabProvider).value;
  final controller = value?.type == 'file' ? value?.editorController : null;
  if (controller == null) return null;
  return ref.watch(lspInitializationProvider(controller));
});
