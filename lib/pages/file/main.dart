import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/file/ui_utils.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/board_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
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
        optionalDivider: true,
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
    if (ref.watch(fileProvider) != null) {
      final localWorkspace = ref.watch(fileProvider)!;
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
                  final parentPath = ref.read(fileProvider)?.path ?? '';
                  final uniquePath = await local.getUniqueFilePath(
                    path.join(parentPath, "new_file"),
                  );
                  await ref.read(fileProvider.notifier).createFile(uniquePath);
                },
                icon: const Icon(Icons.note_add_outlined),
              ),
              IconButton(
                tooltip: "新建文件夹",
                onPressed: () async {
                  final parentPath = ref.read(fileProvider)?.path ?? '';
                  final uniquePath = await local.getUniqueFolderPath(
                    path.join(parentPath, "new_folder"),
                  );
                  await ref
                      .read(fileProvider.notifier)
                      .createFolder(uniquePath);
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
                onNodeTap: (id) => ref
                    .read(localFileTreeViewControllerProvider)
                    .setSelectedNodeId(id),
                onNodeDoubleTap: (id) =>
                    ref.read(fileProvider.notifier).openFile(context, id),
                namingStrategy: TreeNamingStrategy.always,
              ),
              style: SuperTreeThemes.material().treeStyle.copyWith(
                selectedColor: Theme.of(context).colorScheme.secondaryContainer,
              ),
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
                    final isGitIgnored = local.isGitIgnoredItem(node.data);
                    return ContextMenuWidget(
                      child: Text(
                        node.data.name,
                        style: isGitIgnored
                            ? TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                              )
                            : null,
                      ),
                      menuProvider: (request) {
                        ref
                            .read(localFileTreeViewControllerProvider)
                            .setSelectedNodeId(node.id);

                        final TreeNode<FileSystemItem>? boardFileTarget = ref
                            .read(boardProvider.notifier)
                            .getFocusFileNode();

                        final TreeNode<FileSystemItem>? boardFolderTarget = ref
                            .read(boardProvider.notifier)
                            .getFocusFolderNode();
                        final TreeNode<FileSystemItem>? localFolderTarget = ref
                            .read(fileProvider.notifier)
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
                                  ref
                                      .read(localFileTreeViewControllerProvider)
                                      .removeNode(node);
                                  showEditorSnackBar(
                                    context,
                                    "已删除 ${node.data.name}",
                                  );
                                }
                              },
                            ),
                            MenuSeparator(),
                            MenuAction(
                              title: "上传到设备文件夹 ${boardFolderTarget?.id ?? "/"}",
                              callback: () => ref
                                  .read(fileProvider.notifier)
                                  .uploadSelectedLocalFileItem(context),
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
                                try {
                                  final bytes = await File(
                                    node.id,
                                  ).readAsBytes();
                                  await ref
                                      .read(boardProvider.notifier)
                                      .writeFileBytes(
                                        boardFileTarget!.id,
                                        bytes,
                                      );
                                  ref
                                      .read(boardFileItemsProvider.notifier)
                                      .buildRootFileListItems();

                                  if (!context.mounted) return;
                                  showEditorSnackBar(
                                    context,
                                    "已覆盖设备文件：${boardFileTarget.id}",
                                  );
                                } on DeviceNotReadyException catch (_) {
                                  if (!context.mounted) return;
                                  final sendCtrlC =
                                      await showDeviceNotReadyDialog(
                                        context,
                                        operation: "覆盖设备文件",
                                      );
                                  if (sendCtrlC) {
                                    ref
                                        .read(getUsbSerialProvider().notifier)
                                        .sendCommand("\x03");
                                  }
                                }
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
                                final parentDir =
                                    localFolderTarget?.id ??
                                    localWorkspace.path;
                                final uniquePath = await local
                                    .getUniqueFilePath(
                                      path.join(parentDir, "new_file"),
                                    );
                                await ref
                                    .read(fileProvider.notifier)
                                    .createFile(uniquePath);
                              },
                            ),
                            MenuAction(
                              title:
                                  "在 ${localFolderTarget?.id ?? localWorkspace.path} 新建文件夹",
                              callback: () async {
                                final parentDir =
                                    localFolderTarget?.id ??
                                    localWorkspace.path;
                                final uniquePath = await local
                                    .getUniqueFolderPath(
                                      path.join(parentDir, "new_folder"),
                                    );
                                await ref
                                    .read(fileProvider.notifier)
                                    .createFolder(uniquePath);
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
                  ? () async {
                      try {
                        await ref
                            .read(fileProvider.notifier)
                            .uploadSelectedLocalFileItem(context);
                      } on DeviceNotReadyException catch (_) {
                        if (!context.mounted) return;
                        final sendCtrlC = await showDeviceNotReadyDialog(
                          context,
                          operation: "上传文件到设备",
                        );
                        if (sendCtrlC) {
                          ref
                              .read(getUsbSerialProvider().notifier)
                              .sendCommand("\x03");
                        }
                      }
                    }
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
    if (ref.watch(getUsbSerialProvider()).isConnected &&
        ref.watch(boardFileItemsProvider).isNotEmpty) {
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
                onPressed: () async {
                  try {
                    await ref
                        .watch(boardFileItemsProvider.notifier)
                        .buildRootFileListItems();
                  } on DeviceNotReadyException catch (_) {
                    if (!context.mounted) return;
                    final sendCtrlC = await showDeviceNotReadyDialog(
                      context,
                      operation: "刷新设备文件",
                    );
                    if (sendCtrlC) {
                      ref
                          .read(getUsbSerialProvider().notifier)
                          .sendCommand("\x03");
                    }
                  }
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
                onNodeTap: (id) => ref
                    .read(boardFileTreeViewControllerProvider)
                    .setSelectedNodeId(id),
                onNodeDoubleTap: (id) =>
                    ref.read(boardProvider.notifier).openFile(context, id),
                namingStrategy: TreeNamingStrategy.always,
              ),
              style: SuperTreeThemes.material().treeStyle.copyWith(
                selectedColor: Theme.of(context).colorScheme.secondaryContainer,
              ),
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
                            .read(fileProvider.notifier)
                            .getFocusFileNode();

                        final TreeNode<FileSystemItem>? localFolderTarget = ref
                            .read(fileProvider.notifier)
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
                                  try {
                                    if (node.data is FolderItem) {
                                      await ref
                                          .read(boardProvider.notifier)
                                          .deleteFolder(node.id);
                                    } else {
                                      await ref
                                          .read(boardProvider.notifier)
                                          .deleteFile(node.id);
                                    }
                                    ref
                                        .read(
                                          boardFileTreeViewControllerProvider,
                                        )
                                        .removeNode(node);
                                    if (!context.mounted) return;
                                    showEditorSnackBar(
                                      context,
                                      "已从设备删除 ${node.data.name}",
                                    );
                                  } on DeviceNotReadyException catch (_) {
                                    if (!context.mounted) return;
                                    final sendCtrlC =
                                        await showDeviceNotReadyDialog(
                                          context,
                                          operation: "删除设备文件",
                                        );
                                    if (sendCtrlC) {
                                      ref
                                          .read(getUsbSerialProvider().notifier)
                                          .sendCommand("\x03");
                                    }
                                  }
                                }
                              },
                            ),
                            MenuSeparator(),
                            MenuAction(
                              title:
                                  "下载到本地文件夹 ${localFolderTarget?.id ?? ref.watch(fileProvider)?.path ?? "（未打开本地项目）"}",
                              callback: () async {
                                try {
                                  await ref
                                      .read(boardProvider.notifier)
                                      .downloadSelectedBoardItem(context);
                                } on DeviceNotReadyException catch (_) {
                                  if (!context.mounted) return;
                                  final sendCtrlC =
                                      await showDeviceNotReadyDialog(
                                        context,
                                        operation: "下载设备文件",
                                      );
                                  if (sendCtrlC) {
                                    ref
                                        .read(getUsbSerialProvider().notifier)
                                        .sendCommand("\x03");
                                  }
                                }
                              },
                              attributes: MenuActionAttributes(
                                disabled:
                                    !(ref
                                        .watch(getUsbSerialProvider())
                                        .isConnected) ||
                                    (ref.watch(fileProvider)?.path == null),
                              ),
                            ),
                            MenuAction(
                              title:
                                  "覆盖本地文件 ${localFileTarget?.id ?? "（未选择本地文件）"}",
                              callback: () async {
                                try {
                                  final bytes = await ref
                                      .read(boardProvider.notifier)
                                      .getFileBytes(node.id);
                                  await File(
                                    localFileTarget!.id,
                                  ).writeAsBytes(bytes);
                                  ref
                                      .read(localFileItemsProvider.notifier)
                                      .buildRootFileListItems();

                                  if (!context.mounted) return;
                                  showEditorSnackBar(
                                    context,
                                    "已覆盖本地文件：${localFileTarget.id}",
                                  );
                                } on DeviceNotReadyException catch (_) {
                                  if (!context.mounted) return;
                                  final sendCtrlC =
                                      await showDeviceNotReadyDialog(
                                        context,
                                        operation: "读取设备文件",
                                      );
                                  if (sendCtrlC) {
                                    ref
                                        .read(getUsbSerialProvider().notifier)
                                        .sendCommand("\x03");
                                  }
                                }
                              },
                              attributes: MenuActionAttributes(
                                disabled:
                                    (localFileTarget == null) ||
                                    ((ref.watch(fileProvider)?.path == null) ||
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
    } else if (ref.watch(getUsbSerialProvider()).isConnected) {
      return WorkspaceEmptyState(
        icon: Icons.developer_board_outlined,
        title: "点击刷新按钮以获取设备文件列表",
        message: "这里会显示板端文件，可以和本地项目互相同步。",
        actionLabel: "刷新",
        onAction: () =>
            ref.watch(boardFileItemsProvider.notifier).buildRootFileListItems(),
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
}
