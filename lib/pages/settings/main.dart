import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Settings extends StatelessWidget {
  const Settings({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: EdgeInsets.all(compact ? 12 : 16),
      children: [
        SettingsSection(
          title: "工作区",
          description: "编辑器、终端和语言服务行为。",
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const UseText("编辑器"),
              subtitle: const UseText("字体、字号、折行、行号"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go("/settings/editor"),
            ),
            const SectionDivider(),
            ListTile(
              leading: const Icon(Icons.terminal),
              title: const UseText("调试与终端"),
              subtitle: const UseText("终端字体、REPL 行为"),
              trailing: const PillBadge(label: "即将支持"),
              enabled: false,
            ),
            const SectionDivider(),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const UseText("语言服务器"),
              subtitle: const UseText("诊断、补全和 LSP WebSocket 地址"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go("/settings/lsp"),
            ),
          ],
        ),
        SettingsSection(
          title: "界面",
          description: "主题、颜色和显示偏好。",
          children: [
            ListTile(
              leading: const Icon(Icons.color_lens_outlined),
              title: const UseText("外观与风格"),
              subtitle: const UseText("主题模式、动态颜色和种子色"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go("/settings/style"),
            ),
            const SectionDivider(),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const UseText("关于"),
              subtitle: const UseText("产品信息和当前阶段"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go("/settings/about"),
            ),
          ],
        ),
      ],
    );

    if (compact) {
      return Column(
        children: [
          const PaneHeader(
            title: "设置",
            subtitle: "调整工作区和界面偏好",
            leadingIcon: Icons.settings_outlined,
            compact: true,
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("设置")),
      body: body,
    );
  }
}
