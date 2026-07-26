import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_tree/super_tree.dart';
import 'package:pyrite_ide/core/services/file/ui_utils.dart';

Future<FileConflictAction> resolveConflict(
  BuildContext context, {
  required FileConflictAction? policy,
  required String sourcePath,
  required String targetPath,
  required bool isUpload,
  bool canShowDiff = false,
}) {
  if (policy == FileConflictAction.overwriteAll) {
    return Future.value(FileConflictAction.overwrite);
  }
  if (policy == FileConflictAction.skipAll) {
    return Future.value(FileConflictAction.skip);
  }
  return showFileConflictDialog(
    context,
    sourcePath: sourcePath,
    targetPath: targetPath,
    isUpload: isUpload,
    canShowDiff: canShowDiff,
  );
}

TreeNode<FileSystemItem>? getFocusFileNodeFromProvider(
  Ref ref,
  ProviderBase<TreeController<FileSystemItem>> controllerProvider,
) {
  final controller = ref.read(controllerProvider);
  final focusNodeId = controller.selectedNodeId ?? "/";
  final focusNode = controller.findNodeById(focusNodeId);
  if (focusNode?.data is FileItem) return focusNode;
  return null;
}

TreeNode<FileSystemItem>? getFocusFolderNodeFromProvider(
  Ref ref,
  ProviderBase<TreeController<FileSystemItem>> controllerProvider,
) {
  final controller = ref.read(controllerProvider);
  final focusNodeId = controller.selectedNodeId ?? "/";
  final focusNode = controller.findNodeById(focusNodeId);
  if (focusNode?.data is FolderItem) return focusNode;
  final lastSlash = focusNodeId.lastIndexOf('/');
  final parentPath = lastSlash > 0 ? focusNodeId.substring(0, lastSlash) : '/';
  return controller.findNodeById(parentPath);
}

List<TreeNode<FileSystemItem>> getSelectedNodesFromProvider(
  Ref ref,
  ProviderBase<TreeController<FileSystemItem>> controllerProvider, {
  bool topLevelOnly = true,
}) {
  final controller = ref.read(controllerProvider);
  final selected = controller.getSelectedNodesInVisibleOrder(
    topLevelOnly: topLevelOnly,
  );
  if (selected.isNotEmpty) return selected;

  final focusNodeId = controller.selectedNodeId;
  final focusNode = focusNodeId == null
      ? null
      : controller.findNodeById(focusNodeId);
  return focusNode == null ? const [] : [focusNode];
}
