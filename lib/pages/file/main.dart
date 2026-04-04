import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/models/file.dart';
import 'package:pyrite_ide/core/services/board_manager/utils.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart' as board;
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:pyrite_ide/shared/toly_tree.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

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
              ref.watch(boardFileItemsProvider.notifier).clear();
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
              child: buildProjectFiles(context, ref),
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

  Widget buildProjectFiles(BuildContext context, WidgetRef ref) {
    if (ref.watch(workspaceProvider) != null) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: TolyTree<LocalFileTreeItem>(
              showConnectingLines: true,
              onTap: (node) async {
                if (!node.data.isDicrectory) {
                  File file = File(node.id);
                  if (context.mounted) {
                    ref
                        .read(tabbedViewControllerProvider.notifier)
                        .openFile(context, file: file);
                  }
                }
              },
              nodes: ref.watch(localFileItemsProvider),
              loadData: (node) => _loadProjectChildren(node, ref),
              nodeBuilder: (node) => Tooltip(
                message: node.data.name,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        node.data.icon,
                        color: Theme.of(context).colorScheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(node.data.name),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
      if (ref.watch(boardFileItemsProvider).isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: .center,
            children: [
              Icon(
                Icons.power_outlined,
                size: 50,
                color: Theme.of(context).colorScheme.secondary,
              ),
              SizedBox(height: 10),
              TextBodyMedium(
                "MicroPython 设备文件为空",
                color: Theme.of(context).colorScheme.secondary,
              ),
              TextBodyMedium(
                "请尝试点击上方刷新按钮刷新",
                color: Theme.of(context).colorScheme.secondary,
              ),
            ],
          ),
        );
      }
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: TolyTree<BoardFileTreeItem>(
              showConnectingLines: true,
              onTap: (node) async {
                if (!node.data.isDicrectory) {
                  final File file = await board.getLocalFilePath(node);
                  final String content = await ref
                      .read(boardFileItemsProvider.notifier)
                      .getFileContent(node.id);
                  await file.writeAsString(content);
                  if (context.mounted) {
                    ref
                        .read(tabbedViewControllerProvider.notifier)
                        .openFile(
                          context,
                          file: file,
                          isBoardFile: true,
                          boardFilePath: node.id,
                        );
                  }
                }
              },
              nodes: ref.watch(boardFileItemsProvider),
              loadData: (node) => _loadBoardChildren(node, ref),
              nodeBuilder: (node) => Tooltip(
                message: node.data.name,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        node.data.icon,
                        color: Theme.of(context).colorScheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(node.data.name),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: .center,
          children: [
            Icon(
              Icons.power_outlined,
              size: 50,
              color: Theme.of(context).colorScheme.secondary,
            ),
            SizedBox(height: 10),
            TextBodyMedium(
              "这里将展示 MicroPython 设备的文件",
              color: Theme.of(context).colorScheme.secondary,
            ),
            TextBodyMedium(
              "请先连接一个 MicroPython 设备",
              color: Theme.of(context).colorScheme.secondary,
            ),
            SizedBox(height: 10),
            FilledButton(
              onPressed: () => context.push("/tools"),
              child: Text("管理 MicroPython 设备"),
            ),
          ],
        ),
      );
    }
  }

  Future<List<TreeNode<LocalFileTreeItem>>> _loadProjectChildren(
    TreeNode<LocalFileTreeItem> node,
    WidgetRef ref,
  ) async {
    // print(node.isExpanded);
    if (node.isLeaf == null) {
      return await local.buildFileListItems(await local.getFilesList(node.id));
    } else {
      return [];
    }
  }

  Future<List<TreeNode<BoardFileTreeItem>>> _loadBoardChildren(
    TreeNode<BoardFileTreeItem> node,
    WidgetRef ref,
  ) async {
    // print(node.isExpanded);
    if (node.isLeaf == null) {
      // print(node.id);
      return await board.buildFileListItems(
        await ref
            .read(boardFileItemsProvider.notifier)
            .getFilesList(path: node.id),
      );
    } else {
      return [];
    }
  }
}
