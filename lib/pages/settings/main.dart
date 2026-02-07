import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Settings extends StatelessWidget {
  const Settings({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("设置"),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: Padding(
        padding: EdgeInsetsGeometry.only(left: 5, right: 5),
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const UseText("编辑器"),
              subtitle: const UseText("字体及大小、缩进、自动换行等编辑器行为"),
              onTap: () => context.go("/settings/editor"),
            ),
            const ListTile(
              leading: Icon(Icons.computer),
              title: UseText("调试与终端"),
              subtitle: UseText("终端字体及大小、交互式解释器模式"),
            ),
            ListTile(
              leading: Icon(Icons.color_lens),
              title: UseText("外观与风格"),
              subtitle: UseText("颜色风格、显示模式"),
              onTap: () => context.go("/settings/style"),
            ),
          ],
        ),
      ),
    );
  }
}
