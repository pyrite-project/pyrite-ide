import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/services/board_manager/main.dart';
import 'package:pyrite_ide/core/services/file/board.dart';
import 'package:pyrite_ide/core/services/file/local.dart' as local;
import 'package:pyrite_ide/core/services/file/board.dart' as board;
import 'package:pyrite_ide/core/services/file/ui.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:pyrite_ide/shared/toly_tree.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:path/path.dart' as path;

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
              ref.watch(local.treeItems.notifier).state = await local
                  .buildFileListItems(ref, await local.getFilesList(ref));
              ref.watch(board.treeItems.notifier).state = [];
              ref.watch(board.treeItems.notifier).state = await board
                  .buildFileListItems(ref, await getFilesList(ref));
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
    if (ref.watch(local.rootDirectory) != null) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: TolyTree<local.FileTreeItem>(
              showConnectingLines: true,
              onTap: (node) async {
                if (!node.data.isDicrectory) {
                  File file = await local.getOpenFile(node.id, ref);
                  if (context.mounted) {
                    openFileAction(context, ref, file: file);
                  }
                }
              },
              nodes: ref.watch(local.treeItems),
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
              onPressed: () => openFolderAction(ref),
              child: Text("打开文件夹"),
            ),
          ],
        ),
      );
    }
  }

  Widget buildBoardFiles(BuildContext context, WidgetRef ref) {
    if (ref.watch(connectState)) {
      if (ref.watch(board.treeItems).isEmpty) {
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
            child: TolyTree<board.FileTreeItem>(
              showConnectingLines: true,
              onTap: (node) async {
                if (!node.data.isDicrectory) {
                    final supportDir = await getApplicationSupportDirectory();
                    print("debug: appSupportDir ${supportDir.path}");
                    List<String> fileName = node.id.split("/");
                    String fileNameResult = "";
                    for (int i = 1; i < fileName.length; i++) {
                      fileNameResult = path.join(fileNameResult, fileName[i]);
                    }
                    File file = File(path.join(supportDir.path, fileNameResult));
                    file.create(recursive: true, exclusive: false);
                    print("debug: open board file ${file.path}");
                    String content = await getFileContent(ref, path: node.id);
                    await file.writeAsString(content);
                  if (context.mounted) {
                    openFileAction(context, ref, file: file);
                  }
                }
              },
              nodes: ref.watch(board.treeItems),
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

  Future<List<TreeNode<local.FileTreeItem>>> _loadProjectChildren(
    TreeNode<local.FileTreeItem> node,
    WidgetRef ref,
  ) async {
    // print(node.isExpanded);
    if (node.isLeaf == null) {
      return await local.buildFileListItems(
        ref,
        await local.getFilesList(ref, path: node.id),
        update: false,
      );
    } else {
      return [];
    }
  }

  Future<List<TreeNode<board.FileTreeItem>>> _loadBoardChildren(
    TreeNode<board.FileTreeItem> node,
    WidgetRef ref,
  ) async {
    // print(node.isExpanded);
    if (node.isLeaf == null) {
      // print(node.id);
      return await board.buildFileListItems(
        ref,
        await board.getFilesList(ref, path: node.id),
        update: false,
      );
    } else {
      return [];
    }
  }
}
