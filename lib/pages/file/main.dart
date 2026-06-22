import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/board_manager/utils.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart' as board;
import 'package:pyrite_ide/core/services/file/board_workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:pyrite_ide/core/services/file/local_workspace_provider.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:super_context_menu/super_context_menu.dart';
import 'package:super_tree/super_tree.dart';

class ProjectFiles extends ConsumerWidget {
  const ProjectFiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = buildWorkspace(context, ref);

    return Scaffold(body: body);
  }

  Widget buildWorkspace(BuildContext context, WidgetRef ref) {
    return shadcn.ShadcnLayer(
      theme: shadcn.ThemeData(
        colorScheme: Theme.of(context).brightness == Brightness.light
            ? shadcn.ColorSchemes.lightNeutral
            : shadcn.ColorSchemes.darkNeutral,
      ),
      child: shadcn.ResizablePanel.vertical(
        draggerBuilder: (context) {
          return shadcn.HorizontalResizableDragger();
        },
        children: [
          shadcn.ResizablePane.flex(
            initialFlex: 1,
            minSize: 180,
            child: buildLocalFiles(context, ref),
          ),
          shadcn.ResizablePane.flex(
            initialFlex: 1,
            minSize: 180,
            child: buildBoardFiles(context, ref),
          ),
        ],
      ),
    );
  }

  Widget buildLocalFiles(BuildContext context, WidgetRef ref) {
    if (ref.watch(localWorkspaceProvider) != null) {
      final localWorkspace = ref.watch(localWorkspaceProvider)!;
      return Column(
        children: [
          PaneHeader(
            title: "本地项目",
            subtitle: localWorkspace.path,
            leadingIcon: Icons.folder_outlined,
            compact: true,
            actions: [
              IconButton(
                tooltip: "新建文件",
                onPressed: () async {
                  await ref
                      .read(localWorkspaceProvider.notifier)
                      .createFile("new_file", null);
                },
                icon: const Icon(Icons.note_add_outlined),
              ),
              IconButton(
                tooltip: "新建文件夹",
                onPressed: () async {
                  await ref
                      .read(localWorkspaceProvider.notifier)
                      .createFolder("new_folder", null);
                },
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              IconButton(
                tooltip: "刷新本地文件",
                onPressed: () => ref
                    .read(localFileItemsProvider.notifier)
                    .buildRootFileListItems(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          // buildLocalActionStrip(context, ref),
          Expanded(
            child: SuperTreeView<FileSystemItem>(
              logic: TreeViewConfig(
                enableDragAndDrop: ref.watch(localEnableDragAndDrop),
                onNodeTap: (id) {
                  ref
                      .read(localFileTreeViewControllerProvider)
                      .setSelectedNodeId(id);
                  File file = File(id);
                  if (context.mounted) {
                    ref
                        .read(tabbedViewControllerProvider.notifier)
                        .openFile(context, file: file);
                  }
                },
                namingStrategy: TreeNamingStrategy.always,
              ),
              style: SuperTreeThemes.material().treeStyle,
              controller: ref.watch(localFileTreeViewControllerProvider),
              prefixBuilder:
                  (BuildContext context, TreeNode<FileSystemItem> node) {
                    return SuperTreeThemes.material().fileSystemIconProvider!
                        .getIcon(node);
                  },
              contentBuilder:
                  (
                    BuildContext context,
                    TreeNode<FileSystemItem> node,
                    Widget? renameField,
                  ) {
                    if (renameField != null) {
                      return renameField;
                    }
                    return ContextMenuWidget(
                      child: Text(node.data.name),
                      menuProvider: (request) {
                        ref
                            .read(localFileTreeViewControllerProvider)
                            .setSelectedNodeId(node.id);

                        final TreeNode<FileSystemItem>? boardFileTarget = ref
                            .read(boardWorkspaceProvider.notifier)
                            .getFocusFileNode();

                        final TreeNode<FileSystemItem>? boardFolderTarget = ref
                            .read(boardWorkspaceProvider.notifier)
                            .getFocusFolderNode();
                        final TreeNode<FileSystemItem>? localFolderTarget = ref
                            .read(localWorkspaceProvider.notifier)
                            .getFocusFolderNode();

                        return Menu(
                          children: [
                            MenuAction(
                              title: "重命名",
                              callback: () => ref
                                  .read(localFileTreeViewControllerProvider)
                                  .setRenamingNodeId(node.id),
                            ),
                            MenuAction(
                              title: "删除",
                              callback: () async {
                                if (await confirmDelete(
                                  context,
                                  node.data.name,
                                )) {
                                  if (!context.mounted) return;
                                  ref
                                      .read(localFileTreeViewControllerProvider)
                                      .removeNode(node);
                                  showActionSnackBar(
                                    context,
                                    "已删除 ${node.data.name}",
                                  );
                                }
                              },
                            ),
                            MenuSeparator(),
                            MenuAction(
                              title: "上传到设备文件夹 ${boardFolderTarget?.id ?? "/"}",
                              callback: () async {
                                if (node.data is FileItem) {
                                  final String content = await local
                                      .getFileContent(node.id);
                                  final targetPath =
                                      (boardFolderTarget?.id != null)
                                      ? "${boardFolderTarget!.id}/${path.basename(node.id)}"
                                      : "/${path.basename(node.id)}";
                                  await ref
                                      .read(boardWorkspaceProvider.notifier)
                                      .writeFile(targetPath, content);
                                  ref
                                      .read(boardFileItemsProvider.notifier)
                                      .buildRootFileListItems();
                                  if (!context.mounted) return;
                                  showActionSnackBar(
                                    context,
                                    "已上传到设备：$targetPath",
                                  );
                                } else if (node.data is FolderItem) {
                                  final targetPath =
                                      (boardFolderTarget?.id != null)
                                      ? "${boardFolderTarget!.id}/${path.basename(node.id)}"
                                      : "/${path.basename(node.id)}";
                                  await ref
                                      .read(boardWorkspaceProvider.notifier)
                                      .uploadFolder(node.id, targetPath);
                                  ref
                                      .read(boardFileItemsProvider.notifier)
                                      .buildRootFileListItems();
                                  if (!context.mounted) return;
                                  showActionSnackBar(
                                    context,
                                    "已上传文件夹到设备：$targetPath",
                                  );
                                }
                              },
                              attributes: MenuActionAttributes(
                                disabled: !(ref
                                    .watch(getUsbSerialProvider())
                                    .isConnected),
                              ),
                            ),
                            MenuAction(
                              title:
                                  "覆盖设备文件 ${boardFileTarget?.id ?? "（未选择设备文件）"}",
                              callback: () async {
                                final String content = await local
                                    .getFileContent(node.id);
                                await ref
                                    .read(boardWorkspaceProvider.notifier)
                                    .writeFile(boardFileTarget!.id, content);
                                ref
                                    .read(boardFileItemsProvider.notifier)
                                    .buildRootFileListItems();
                                if (!context.mounted) return;
                                showActionSnackBar(
                                  context,
                                  "已覆盖设备文件：${boardFileTarget.id}",
                                );
                              },
                              attributes: MenuActionAttributes(
                                disabled:
                                    !(ref
                                        .watch(getUsbSerialProvider())
                                        .isConnected) ||
                                    (boardFileTarget == null ||
                                        (node.data is FolderItem)),
                              ),
                            ),
                            MenuSeparator(),
                            MenuAction(
                              title:
                                  "在 ${localFolderTarget?.id ?? localWorkspace.path} 新建文件",
                              callback: () async {
                                await ref
                                    .read(localWorkspaceProvider.notifier)
                                    .createFile("new_file", localFolderTarget);
                              },
                            ),
                            MenuAction(
                              title:
                                  "在 ${localFolderTarget?.id ?? localWorkspace.path} 新建文件夹",
                              callback: () async {
                                await ref
                                    .read(localWorkspaceProvider.notifier)
                                    .createFolder(
                                      "new_folder",
                                      localFolderTarget,
                                    );
                              },
                            ),
                          ],
                        );
                      },
                    );
                  },
            ),
          ),
        ],
      );
    } else {
      return WorkspaceEmptyState(
        icon: Icons.folder_outlined,
        title: "打开一个本地项目",
        message: "选择保存 MicroPython 脚本的文件夹，然后就可以在本地和设备之间同步文件。",
        actionLabel: "打开文件夹",
        onAction: () => ref.read(localFileItemsProvider.notifier).openFolder(),
      );
    }
  }

  Widget buildLocalActionStrip(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isConnected = ref.watch(getUsbSerialProvider()).isConnected;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: isConnected
                  ? () => uploadSelectedLocalItem(context, ref)
                  : null,
              icon: const Icon(Icons.upload_outlined, size: 18),
              label: Text("上传选中项"),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: () => ref
                  .read(localFileItemsProvider.notifier)
                  .buildRootFileListItems(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text("刷新"),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildBoardFiles(BuildContext context, WidgetRef ref) {
    if (ref.watch(getUsbSerialProvider()).isConnected) {
      final usb = ref.watch(getUsbSerialProvider());
      return Column(
        children: [
          PaneHeader(
            title: "设备文件",
            subtitle: "已连接：${usb.selectedPortName}",
            leadingIcon: Icons.developer_board_outlined,
            compact: true,
            actions: [
              IconButton(
                tooltip: "刷新设备文件",
                onPressed: () {
                  ref.read(boardWorkspaceProvider.notifier).clear();
                  ref
                      .watch(boardFileItemsProvider.notifier)
                      .buildRootFileListItems();
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          // buildBoardActionStrip(context, ref),
          Expanded(
            child: SuperTreeView<FileSystemItem>(
              logic: TreeViewConfig(
                enableDragAndDrop: ref.watch(boardEnableDragAndDrop),
                onNodeTap: (id) async {
                  ref
                      .read(boardFileTreeViewControllerProvider)
                      .setSelectedNodeId(id);
                  final node = ref
                      .read(boardFileTreeViewControllerProvider)
                      .findNodeById(id);
                  if (node == null || node.data is! FileItem) return;
                  final file = await board.getLocalFilePath(node);
                  final content = await ref
                      .read(boardWorkspaceProvider.notifier)
                      .getFileContent(id);
                  await file.writeAsString(content);
                  if (context.mounted) {
                    ref
                        .read(tabbedViewControllerProvider.notifier)
                        .openFile(
                          context,
                          file: file,
                          isBoardFile: true,
                          boardFilePath: id,
                        );
                  }
                },
                namingStrategy: TreeNamingStrategy.always,
              ),
              style: SuperTreeThemes.material().treeStyle,
              controller: ref.watch(boardFileTreeViewControllerProvider),
              prefixBuilder:
                  (BuildContext context, TreeNode<FileSystemItem> node) {
                    return SuperTreeThemes.material().fileSystemIconProvider!
                        .getIcon(node);
                  },
              contentBuilder:
                  (
                    BuildContext context,
                    TreeNode<FileSystemItem> node,
                    Widget? renameField,
                  ) {
                    if (renameField != null) {
                      return renameField;
                    }
                    return ContextMenuWidget(
                      child: Text(node.data.name),
                      menuProvider: (request) {
                        ref
                            .read(boardFileTreeViewControllerProvider)
                            .setSelectedNodeId(node.id);

                        final TreeNode<FileSystemItem>? localFileTarget = ref
                            .read(localWorkspaceProvider.notifier)
                            .getFocusFileNode();

                        final TreeNode<FileSystemItem>? localFolderTarget = ref
                            .read(localWorkspaceProvider.notifier)
                            .getFocusFolderNode();

                        return Menu(
                          children: [
                            MenuAction(
                              title: "重命名",
                              callback: () => ref
                                  .read(boardFileTreeViewControllerProvider)
                                  .setRenamingNodeId(node.id),
                            ),
                            MenuAction(
                              title: "删除",
                              callback: () async {
                                if (await confirmDelete(
                                  context,
                                  node.data.name,
                                )) {
                                  if (!context.mounted) return;
                                  ref
                                      .read(boardFileTreeViewControllerProvider)
                                      .removeNode(node);
                                  showActionSnackBar(
                                    context,
                                    "已从设备删除 ${node.data.name}",
                                  );
                                }
                              },
                            ),
                            MenuSeparator(),
                            MenuAction(
                              title:
                                  "下载到本地文件夹 ${localFolderTarget?.id ?? ref.watch(localWorkspaceProvider)?.path ?? "（未打开本地项目）"}",
                              callback: () async {
                                final localWorkspace = ref.read(
                                  localWorkspaceProvider,
                                );
                                if (localWorkspace == null) return;
                                final targetPath =
                                    (localFolderTarget?.id != null)
                                    ? path.join(
                                        localFolderTarget!.id,
                                        path.basename(node.id),
                                      )
                                    : path.join(
                                        localWorkspace.path,
                                        path.basename(node.id),
                                      );
                                if (node.data is FileItem) {
                                  final String content = await ref
                                      .read(boardWorkspaceProvider.notifier)
                                      .getFileContent(node.id);
                                  local.writeFile(targetPath, content);
                                  if (!context.mounted) return;
                                  showActionSnackBar(
                                    context,
                                    "已下载到本地：$targetPath",
                                  );
                                } else if (node.data is FolderItem) {
                                  await ref
                                      .read(boardWorkspaceProvider.notifier)
                                      .downloadFolder(node.id, targetPath);
                                  if (!context.mounted) return;
                                  showActionSnackBar(
                                    context,
                                    "已下载文件夹到本地：$targetPath",
                                  );
                                }

                                ref
                                    .read(localFileItemsProvider.notifier)
                                    .buildRootFileListItems();
                              },
                              attributes: MenuActionAttributes(
                                disabled:
                                    !(ref
                                        .watch(getUsbSerialProvider())
                                        .isConnected) ||
                                    (ref.watch(localWorkspaceProvider)?.path ==
                                        null),
                              ),
                            ),
                            MenuAction(
                              title:
                                  "覆盖本地文件 ${localFileTarget?.id ?? "（未选择本地文件）"}",
                              callback: () async {
                                final String content = await ref
                                    .read(boardWorkspaceProvider.notifier)
                                    .getFileContent(node.id);
                                local.writeFile(localFileTarget!.id, content);
                                ref
                                    .read(localFileItemsProvider.notifier)
                                    .buildRootFileListItems();
                                if (!context.mounted) return;
                                showActionSnackBar(
                                  context,
                                  "已覆盖本地文件：${localFileTarget.id}",
                                );
                              },
                              attributes: MenuActionAttributes(
                                disabled:
                                    (localFileTarget == null) ||
                                    ((ref.watch(localWorkspaceProvider)?.path ==
                                            null) ||
                                        (node.data is FolderItem)),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
            ),
          ),
        ],
      );
    } else {
      return WorkspaceEmptyState(
        icon: Icons.developer_board_outlined,
        title: "连接 MicroPython 设备",
        message: "连接后这里会显示板端文件，可以和本地项目互相同步。",
        actionLabel: "打开设备管理",
        onAction: () => context.go("/tools"),
      );
    }
  }

  Widget buildBoardActionStrip(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hasLocalWorkspace = ref.watch(localWorkspaceProvider) != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: hasLocalWorkspace
                  ? () => downloadSelectedBoardItem(context, ref)
                  : null,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text("下载选中项"),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: () {
                ref.read(boardWorkspaceProvider.notifier).clear();
                ref
                    .read(boardFileItemsProvider.notifier)
                    .buildRootFileListItems();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text("刷新"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> uploadSelectedLocalItem(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final selectedFile = ref
        .read(localWorkspaceProvider.notifier)
        .getFocusFileNode();
    final selectedFolder = ref
        .read(localWorkspaceProvider.notifier)
        .getFocusFolderNode();
    final selected = selectedFile ?? selectedFolder;
    if (selected == null) {
      showActionSnackBar(context, "先选择一个本地文件或文件夹");
      return;
    }

    final boardFolderTarget = ref
        .read(boardWorkspaceProvider.notifier)
        .getFocusFolderNode();
    final targetPath = boardFolderTarget?.id != null
        ? "${boardFolderTarget!.id}/${path.basename(selected.id)}"
        : "/${path.basename(selected.id)}";

    if (selected.data is FileItem) {
      final content = await local.getFileContent(selected.id);
      await ref
          .read(boardWorkspaceProvider.notifier)
          .writeFile(targetPath, content);
      if (!context.mounted) return;
      showActionSnackBar(context, "已上传到设备：$targetPath");
    } else {
      await ref
          .read(boardWorkspaceProvider.notifier)
          .uploadFolder(selected.id, targetPath);
      if (!context.mounted) return;
      showActionSnackBar(context, "已上传文件夹到设备：$targetPath");
    }
    ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
  }

  Future<void> downloadSelectedBoardItem(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final selectedFile = ref
        .read(boardWorkspaceProvider.notifier)
        .getFocusFileNode();
    final selectedFolder = ref
        .read(boardWorkspaceProvider.notifier)
        .getFocusFolderNode();
    final selected = selectedFile ?? selectedFolder;
    final localWorkspace = ref.read(localWorkspaceProvider);
    if (selected == null) {
      showActionSnackBar(context, "先选择一个设备文件或文件夹");
      return;
    }
    if (localWorkspace == null) {
      showActionSnackBar(context, "先打开一个本地项目");
      return;
    }

    final localFolderTarget = ref
        .read(localWorkspaceProvider.notifier)
        .getFocusFolderNode();
    final targetPath = localFolderTarget?.id != null
        ? path.join(localFolderTarget!.id, path.basename(selected.id))
        : path.join(localWorkspace.path, path.basename(selected.id));

    if (selected.data is FileItem) {
      final content = await ref
          .read(boardWorkspaceProvider.notifier)
          .getFileContent(selected.id);
      local.writeFile(targetPath, content);
      if (!context.mounted) return;
      showActionSnackBar(context, "已下载到本地：$targetPath");
    } else {
      await ref
          .read(boardWorkspaceProvider.notifier)
          .downloadFolder(selected.id, targetPath);
      if (!context.mounted) return;
      showActionSnackBar(context, "已下载文件夹到本地：$targetPath");
    }

    ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
  }

  Future<bool> confirmDelete(BuildContext context, String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text("删除项目"),
        content: Text("确定要删除“$name”吗？此操作无法直接撤销。"),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text("取消"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => context.pop(true),
            child: const Text("删除"),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void showActionSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
