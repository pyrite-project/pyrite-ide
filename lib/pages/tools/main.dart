import 'package:flutter/material.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Tools extends StatelessWidget {
  const Tools({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          const SliverAppBar.large(title: UseText("工具")),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Icon(
                  Icons.border_clear,
                  size: 60,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                UseText("暂无工具", color: Theme.of(context).colorScheme.secondary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
