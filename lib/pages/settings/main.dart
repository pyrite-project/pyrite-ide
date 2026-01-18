import 'package:flutter/material.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Settings extends StatelessWidget {
  const Settings({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          const SliverAppBar.large(title: UseText("设置")),
          SliverList.list(
            children: const [
              ListTile(
                leading: Icon(Icons.edit),
                title: UseText("编辑器"),
                subtitle: UseText("字体及大小、缩进、自动换行等编辑器行为"),
              ),
              ListTile(
                leading: Icon(Icons.computer),
                title: UseText("调试与终端"),
                subtitle: UseText("终端字体及大小、交互式解释器模式"),
              ),
              ListTile(
                leading: Icon(Icons.color_lens),
                title: UseText("外观与风格"),
                subtitle: UseText("颜色风格、显示模式"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
