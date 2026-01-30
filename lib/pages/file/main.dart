import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file.dart';
import 'package:pyrite_ide/core/services/edit.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:tolyui/tolyui.dart';

class ProjectFiles extends ConsumerWidget {
  const ProjectFiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text("项目文件"),
        actions: [
          IconButton(onPressed: () {}, icon: Icon(Icons.add)),
          IconButton(onPressed: () {}, icon: Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: TolyTree<FileTreeItem>(
                showConnectingLines: true,
                onTap: (node) async {
                  File file = await getOpenFile(node.id, ref);
                  TabData newTab = createNewTab(
                    file,
                    ref,
                    await createNewEditorController(file, ref),
                  );
                  tabbedViewController.addTab(newTab);
                  tabbedViewController.selectTab(newTab);
                },
                nodes: ref.watch(treeItems),
                loadData: (node) => _loadChildren(node, ref),
                nodeBuilder: (node) => Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        node.data.icon,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(node.data.name),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<TreeNode<FileTreeItem>>> _loadChildren(
    TreeNode<FileTreeItem> node,
    WidgetRef ref,
  ) async {
    if (node.isLeaf == null) {
      return await buildFileListItems(
        ref,
        await getFilesList(ref, path: node.id),
        update: false,
      );
    } else {
      return [];
    }
  }
}
