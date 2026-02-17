import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/main.dart';
import 'package:pyrite_ide/core/services/editor/main.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:pyrite_ide/shared/toly_tree.dart';

class ProjectFiles extends ConsumerWidget {
  const ProjectFiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text("项目文件"),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton(
            onPressed: () async {
              ref.watch(treeItems.notifier).state = await buildFileListItems(
                ref,
                await getFilesList(ref),
              );
            },
            icon: Icon(Icons.refresh),
          ),
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
                  if (!node.data.isDicrectory) {
                    File file = await getOpenFile(node.id, ref);
                    TabData newTab = await createNewFileTab(
                      file,
                      ref,
                      await createNewEditorController(file, ref),
                    );
                    ref.read(tabbedViewController).addTab(newTab);
                    ref.read(tabbedViewController).selectTab(newTab);
                    // ignore: use_build_context_synchronously
                    if (!ResponsiveBreakpoints.of(context).isDesktop) {
                      ref.watch(nowViewSelectedIndex.notifier).state =
                          nowNavigationBarItems.length;
                    }
                  }
                },
                nodes: ref.watch(treeItems),
                loadData: (node) => _loadChildren(node, ref),
                nodeBuilder: (node) => Tooltip(
                  message: node.data.name,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 8,
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
