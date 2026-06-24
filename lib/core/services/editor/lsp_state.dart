import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';

final lspInitializationProvider =
    FutureProvider.family<bool, CodeForgeController>((ref, controller) async {
      if (controller.lspConfig == null) return false;
      await controller.lspConfig!.initialize();
      return true;
    });

final lspState = Provider<AsyncValue<bool>?>((ref) {
  final tabManager = ref.watch(tabbedViewControllerProvider);
  final selectedTab = tabManager.selectedTab;
  if (selectedTab?.value.type != 'file') return null;
  final controller = (selectedTab!.value as TabDataValue).editorController!;
  return ref.watch(lspInitializationProvider(controller));
});
