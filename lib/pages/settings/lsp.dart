import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';

class LspSettings extends ConsumerWidget {
  const LspSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text("语言服务器设置")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsSection(
            title: "语言服务",
            description: "设置会在新打开的编辑器标签页中生效。",
            children: [
              SwitchListTile(
                title: const Text("启用语言服务器"),
                subtitle: const Text("提供补全、诊断和跳转等编辑能力"),
                value: ref.watch(useLsp),
                onChanged: (value) {
                  ref.read(useLsp.notifier).state = value;
                },
              ),
              const SectionDivider(),
              ListTile(
                title: const Text("WebSocket 地址"),
                subtitle: Text(ref.watch(lspWebScoketPath)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showPathDialog(context, ref),
              ),
            ],
          ),
          SettingsSection(
            title: "诊断显示",
            description: "控制编辑器是否显示语言服务器返回的问题标记。",
            children: [
              SwitchListTile(
                title: const Text("显示警告诊断"),
                subtitle: const Text("开启后，警告会以下划线标识"),
                value: !ref.watch(disableWarning),
                onChanged: (value) {
                  ref.read(disableWarning.notifier).state = !value;
                },
              ),
              const SectionDivider(),
              SwitchListTile(
                title: const Text("显示错误诊断"),
                subtitle: const Text("开启后，错误会以下划线标识"),
                value: !ref.watch(disableError),
                onChanged: (value) {
                  ref.read(disableError.notifier).state = !value;
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void showPathDialog(BuildContext context, WidgetRef ref) async {
    final TextEditingController controller = TextEditingController();
    controller.text = ref.read(lspWebScoketPath);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("WebSocket 地址"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: "地址",
            helperText: "例如 127.0.0.1:8765",
            prefixText: "ws://",
          ),
        ),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text("取消")),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              final messenger = ScaffoldMessenger.of(context);
              ref.read(lspWebScoketPath.notifier).state = value;
              context.pop();
              messenger.showSnackBar(
                const SnackBar(content: Text("语言服务器地址已更新")),
              );
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }
}
