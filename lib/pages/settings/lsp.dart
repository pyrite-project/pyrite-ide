import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:tolyui_message/tolyui_message.dart';

class LspSettings extends ConsumerWidget {
  const LspSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = ListView(
      padding: EdgeInsets.all(12),
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
              title: const Text("连接方式"),
              subtitle: Text(ref.watch(lspType) == LspType.webSocket ? "WebSocket" : "stdio (本地进程)"),
            ),
            RadioGroup<LspType>(
              groupValue: ref.watch(lspType),
              onChanged: (value) {
                if (value != null) ref.read(lspType.notifier).state = value;
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    RadioListTile<LspType>(
                      title: const Text("WebSocket"),
                      subtitle: const Text("连接到远程 WebSocket 服务器"),
                      value: LspType.webSocket,
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<LspType>(
                      title: const Text("stdio"),
                      subtitle: const Text("启动本地语言服务器进程"),
                      value: LspType.stdio,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            if (ref.watch(lspType) == LspType.webSocket) ...[
              const SectionDivider(),
              ListTile(
                title: const Text("WebSocket 地址"),
                subtitle: Text("ws://${ref.watch(lspWebSocketPath)}"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showPathDialog(context, ref),
              ),
            ] else ...[
              const SectionDivider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    TextFormField(
                      initialValue: ref.read(lspStdioExecutable),
                      decoration: const InputDecoration(
                        labelText: "可执行文件路径",
                        helperText: "例如 python、node 或完整路径",
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (value) {
                        ref.read(lspStdioExecutable.notifier).state = value.trim();
                        $message.attach(context);
                        $message.success(message: "可执行文件路径已更新");
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: ref.read(lspStdioArgs),
                      decoration: const InputDecoration(
                        labelText: "启动参数",
                        helperText: "空格分隔，例如 --stdio",
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (value) {
                        ref.read(lspStdioArgs.notifier).state = value.trim();
                        $message.attach(context);
                        $message.success(message: "启动参数已更新");
                      },
                    ),
                  ],
                ),
              ),
            ],
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
    );

    return Scaffold(
      appBar: AppBar(title: const Text("语言服务器设置")),
      body: body,
    );
  }

  void showPathDialog(BuildContext context, WidgetRef ref) async {
    final TextEditingController controller = TextEditingController();
    controller.text = ref.read(lspWebSocketPath);
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
              final value = controller.text.trim().replaceFirst(
                RegExp(r'^ws://'),
                '',
              );
              if (value.isEmpty) return;
              final Uri? uri;
              try {
                uri = Uri.tryParse("ws://$value");
                if (uri == null ||
                    uri.host.isEmpty ||
                    !uri.hasPort ||
                    uri.port <= 0 ||
                    uri.port > 65535) {
                  throw const FormatException("Invalid WebSocket address");
                }
              } on FormatException {
                $message.attach(context);
                $message.error(message: "请输入有效的 WebSocket 地址");
                return;
              }
              ref.read(lspWebSocketPath.notifier).state = value;
              context.pop();
              $message.attach(context);
              $message.success(message: "语言服务器地址已更新");
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }
}
