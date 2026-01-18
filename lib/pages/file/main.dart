import 'package:flutter/material.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class ProjectFiles extends StatelessWidget {
  const ProjectFiles({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          const SliverAppBar.large(title: UseText("文件")),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Icon(
                  Icons.border_clear,
                  size: 60,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                UseText(
                  "请先打开一个项目",
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: null,
        icon: Icon(Icons.add),
        label: UseText("新建 Python 文件"),
      ),
    );
  }
}
