import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/local.dart' as local;
import 'package:pyrite_ide/core/services/editor/main.dart';
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
              ref.watch(local.treeItems.notifier).state = await local
                  .buildFileListItems(ref, await local.getFilesList(ref));
            },
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: MaterialButton(
        hoverColor: Theme.of(context).colorScheme.surface,
        splashColor: Theme.of(context).colorScheme.surface,
        onPressed: () => ref.read(local.selectedPath.notifier).state = null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: TolyTree<local.FileTreeItem>(
                  showConnectingLines: true,
                  onTap: (node) async {
                    ref.read(local.selectedPath.notifier).state = node.id;
                    print(ref.read(local.selectedPath));
                    if (!node.data.isDicrectory) {
                      File file = await local.getOpenFile(node.id, ref);
                      TabData newTab = await createNewFileTab(
                        file,
                        ref,
                        await createNewEditorController(file, ref),
                      );
                      ref.read(tabbedViewController).addTab(newTab);
                      ref.read(tabbedViewController).selectTab(newTab);
                    }
                  },
                  nodes: ref.watch(local.treeItems),
                  loadData: (node) => _loadChildren(node, ref),
                  nodeBuilder: (node) => Tooltip(
                    message:
                        "${node.data.name}${(ref.watch(local.selectedPath) == node.id) ? "（已选择）" : ""}",
                    child: Container(
                      color: (ref.watch(local.selectedPath) == node.id)
                          ? Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest
                          : null,
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 4,
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
      ),
    );
  }

  Future<List<TreeNode<local.FileTreeItem>>> _loadChildren(
    TreeNode<local.FileTreeItem> node,
    WidgetRef ref,
  ) async {
    print(node.isExpanded);
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
