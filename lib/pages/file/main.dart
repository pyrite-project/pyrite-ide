import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/local.dart' as local;
import 'package:pyrite_ide/core/services/file/ui.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:pyrite_ide/shared/toly_tree.dart';

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
            },
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: (ref.watch(local.rootDirectory) != null)
          ? CustomScrollView(
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
                    loadData: (node) => _loadChildren(node, ref),
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
            )
          : Center(
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
            ),
    );
  }

  Future<List<TreeNode<local.FileTreeItem>>> _loadChildren(
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
}
