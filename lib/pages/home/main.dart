import 'package:flutter/material.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          const SliverAppBar.large(title: UseText("首页")),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Icon(
                  Icons.border_clear,
                  size: 60,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                UseText("暂无项目", color: Theme.of(context).colorScheme.secondary),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: null,
        icon: Icon(Icons.add),
        label: UseText("新建项目"),
      ),
    );
  }
}
