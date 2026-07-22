import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Settings extends ConsumerWidget {
  const Settings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = ListView(
      padding: const EdgeInsets.all(12),
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

            ListTile(
              leading: const Icon(Icons.terminal),
              title: const UseText("调试与终端"),
              subtitle: const UseText("波特率、自动重连、REPL"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go("/settings/terminal"),
            ),

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

            SwitchListTile(
              secondary: const Icon(Icons.dashboard),
              title: const Text("功能面板"),
              subtitle: const Text("显示/隐藏功能导航面板"),
              value: ref.watch(functionPageShow),
              onChanged: (value) {
                ref.read(functionPageShow.notifier).state = value;
              },
            ),

            SwitchListTile(
              secondary: const Icon(Icons.terminal),
              title: const Text("控制台面板"),
              subtitle: const Text("显示/隐藏控制台输出面板"),
              value: ref.watch(consolePageShow),
              onChanged: (value) {
                ref.read(consolePageShow.notifier).state = value;
              },
            ),

            SwitchListTile(
              secondary: const Icon(Icons.expand),
              title: const Text("扩展面板"),
              subtitle: const Text("显示/隐藏扩展信息面板"),
              value: ref.watch(expansionPageShow),
              onChanged: (value) {
                ref.read(expansionPageShow.notifier).state = value;
              },
            ),

            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const UseText("重新显示欢迎引导"),
              subtitle: const UseText("用于测试首次启动 OOBE 覆盖层"),
              trailing: const Icon(Icons.open_in_full),
              onTap: () {
                ref.read(welcomeCompletedProvider.notifier).state = false;
                context.go('/welcome');
              },
            ),

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

    return Scaffold(
      appBar: AppBar(title: const Text("设置")),
      body: body,
    );
  }
}
