import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/board_manager/utils.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/board_workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:pyrite_ide/core/services/file/local_workspace_provider.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:super_context_menu/super_context_menu.dart';
import 'package:super_tree/super_tree.dart';

class ProjectFiles extends ConsumerWidget {
  const ProjectFiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text("文件"),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton(
            onPressed: () async {
              ref
                  .read(localFileItemsProvider.notifier)
                  .buildRootFileListItems();
              ref.watch(boardWorkspaceProvider.notifier).clear();
              ref
                  .watch(boardFileItemsProvider.notifier)
                  .buildRootFileListItems();
            },
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: shadcn.ShadcnLayer(
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
              child: buildLocalFiles(context, ref),
            ),
            shadcn.ResizablePane.flex(
              initialFlex: 1,
              child: buildBoardFiles(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildLocalFiles(BuildContext context, WidgetRef ref) {
    if (ref.watch(localWorkspaceProvider) != null) {
      return SuperTreeView<FileSystemItem>(
        logic: TreeViewConfig(
          enableDragAndDrop: ref.watch(localEnableDragAndDrop),
          onNodeTap: (id) {
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
        prefixBuilder: (BuildContext context, TreeNode<FileSystemItem> node) {
          return SuperTreeThemes.material().fileSystemIconProvider!.getIcon(
            node,
          );
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
                  final TreeNode<FileSystemItem>? localFileTarget = ref
                      .read(localWorkspaceProvider.notifier)
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
                        callback: () => ref
                            .read(localFileTreeViewControllerProvider)
                            .removeNode(node),
                      ),
                      MenuSeparator(),
                      MenuAction(
                        title: "下载至 ${boardFolderTarget?.id ?? "/"}",
                        callback: () async {
                          if (node.data is FileItem) {
                            final String content = await local.getFileContent(
                              node.id,
                            );
                            await ref
                                .read(boardWorkspaceProvider.notifier)
                                .writeFile(
                                  (boardFolderTarget?.id != null)
                                      ? "${boardFolderTarget!.id}/${path.basename(node.id)}"
                                      : "/${path.basename(node.id)}",
                                  content,
                                );
                            ref
                                .read(boardFileItemsProvider.notifier)
                                .buildRootFileListItems();
                          } else if (node.data is FolderItem) {
                            await ref
                                .read(boardWorkspaceProvider.notifier)
                                .uploadFolder(
                                  node.id,
                                  (boardFolderTarget?.id != null)
                                      ? "${boardFolderTarget!.id}/${path.basename(node.id)}"
                                      : "/${path.basename(node.id)}",
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
                        title: "下载至 ${boardFileTarget?.id ?? "（焦点非文件或未选择）"}",
                        callback: () async {
                          final String content = await local.getFileContent(
                            node.id,
                          );
                          await ref
                              .read(boardWorkspaceProvider.notifier)
                              .writeFile(boardFileTarget!.id, content);
                          ref
                              .read(boardFileItemsProvider.notifier)
                              .buildRootFileListItems();
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
                            "在 ${localFolderTarget?.id ?? ref.read(localWorkspaceProvider)!.path} 新建文件",
                        callback: () async {
                          await ref
                              .read(localWorkspaceProvider.notifier)
                              .createFile("new_file", localFolderTarget);
                        },
                      ),
                      MenuAction(
                        title:
                            "在 ${localFolderTarget?.id ?? ref.read(localWorkspaceProvider)!.path} 新建文件夹",
                        callback: () async {
                          await ref
                              .read(localWorkspaceProvider.notifier)
                              .createFolder("new_folder", localFolderTarget);
                        },
                      ),
                    ],
                  );
                },
              );
            },
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: .center,
          children: [
            Icon(
              Icons.folder_outlined,
              size: 50,
              color: Theme.of(context).colorScheme.secondary,
            ),
            SizedBox(height: 10),
            TextBodyMedium(
              "欢迎来到 PyriteIDE",
              color: Theme.of(context).colorScheme.secondary,
            ),
            TextBodyMedium(
              "请先打开一个项目文件夹",
              color: Theme.of(context).colorScheme.secondary,
            ),
            SizedBox(height: 10),
            FilledButton(
              onPressed: () =>
                  ref.read(localFileItemsProvider.notifier).openFolder(),
              child: Text("打开文件夹"),
            ),
          ],
        ),
      );
    }
  }

  Widget buildBoardFiles(BuildContext context, WidgetRef ref) {
    if (ref.watch(getUsbSerialProvider()).isConnected) {
      return SuperTreeView<FileSystemItem>(
        logic: TreeViewConfig(
          enableDragAndDrop: ref.watch(boardEnableDragAndDrop),
          onNodeTap: (id) {
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
        controller: ref.watch(boardFileTreeViewControllerProvider),
        prefixBuilder: (BuildContext context, TreeNode<FileSystemItem> node) {
          return SuperTreeThemes.material().fileSystemIconProvider!.getIcon(
            node,
          );
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

                  final TreeNode<FileSystemItem>? boardFileTarget = ref
                      .read(boardWorkspaceProvider.notifier)
                      .getFocusFileNode();
                  final TreeNode<FileSystemItem>? localFileTarget = ref
                      .read(localWorkspaceProvider.notifier)
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
                            .read(boardFileTreeViewControllerProvider)
                            .setRenamingNodeId(node.id),
                      ),
                      MenuAction(
                        title: "删除",
                        callback: () => ref
                            .read(boardFileTreeViewControllerProvider)
                            .removeNode(node),
                      ),
                      MenuSeparator(),
                      MenuAction(
                        title:
                            "上传至 ${localFolderTarget?.id ?? ref.watch(localWorkspaceProvider)?.path}",
                        callback: () async {
                          if (node.data is FileItem) {
                            final String content = await ref
                                .read(boardWorkspaceProvider.notifier)
                                .getFileContent(node.id);
                            local.writeFile(
                              (localFolderTarget?.id != null)
                                  ? path.join(
                                      localFolderTarget!.id,
                                      path.basename(node.id),
                                    )
                                  : path.join(
                                      ref.watch(localWorkspaceProvider)!.path,
                                      path.basename(node.id),
                                    ),
                              content,
                            );
                          } else if (node.data is FolderItem) {
                            await ref
                                .read(boardWorkspaceProvider.notifier)
                                .downloadFolder(
                                  node.id,
                                  (localFolderTarget?.id != null)
                                      ? path.join(
                                          localFolderTarget!.id,
                                          path.basename(node.id),
                                        )
                                      : path.join(
                                          ref
                                              .watch(localWorkspaceProvider)!
                                              .path,
                                          path.basename(node.id),
                                        ),
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
                              (ref.watch(localWorkspaceProvider)?.path == null),
                        ),
                      ),
                      MenuAction(
                        title: "上传至 ${localFileTarget?.id ?? "（焦点非文件或未选择）"}",
                        callback: () async {
                          final String content = await ref
                              .read(boardWorkspaceProvider.notifier)
                              .getFileContent(node.id);
                          local.writeFile(
                            path.join(localFileTarget!.id),
                            content,
                          );
                          ref
                              .read(localFileItemsProvider.notifier)
                              .buildRootFileListItems();
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
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: .center,
          children: [
            Icon(
              Icons.devices,
              size: 50,
              color: Theme.of(context).colorScheme.secondary,
            ),
            SizedBox(height: 10),
            TextBodyMedium(
              "尚未连接到 MicroPython 设备",
              color: Theme.of(context).colorScheme.secondary,
            ),
            TextBodyMedium(
              "请前往设备管理连接一个设备",
              color: Theme.of(context).colorScheme.secondary,
            ),
            SizedBox(height: 10),
            FilledButton(
              onPressed: () => context.push("/tools"),
              child: Text("设备管理"),
            ),
          ],
        ),
      );
    }
  }
}
