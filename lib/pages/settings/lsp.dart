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
        SettingsSection(
          title: "MicroPython Stubs",
          description: "配置 pylsp 等语言服务使用的 MicroPython 类型存根。",
          children: [
            SwitchListTile(
              title: const Text("启用 Stubs"),
              subtitle: const Text("启用后语言服务可读取配置的 stubs layer"),
              value: ref.watch(microPythonStubsEnabled),
              onChanged: (value) {
                ref.read(microPythonStubsEnabled.notifier).state = value;
              },
            ),
            const SectionDivider(),
            SwitchListTile(
              title: const Text("自动检测 Layer"),
              subtitle: const Text("后续可根据连接设备推荐 generic/port/board stubs"),
              value: ref.watch(microPythonStubsAutoDetectLayers),
              onChanged: (value) {
                ref.read(microPythonStubsAutoDetectLayers.notifier).state = value;
              },
            ),
            const SectionDivider(),
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text("Stubs Layers"),
              subtitle: Text(_layersSummary(ref.watch(microPythonStubsLayers))),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showLayersDialog(context, ref),
            ),
            const SectionDivider(),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text("额外路径"),
              subtitle: Text(_pathsSummary(ref.watch(microPythonStubsExtraPaths))),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showExtraPathsDialog(context, ref),
            ),
          ],
        ),
        SettingsSection(
          title: "LSP 功能",
          description: "控制 CodeForge 向语言服务器声明和使用的能力。设置会在新打开的编辑器标签页中生效。",
          children: [
            _CapabilitySwitch(title: "语义高亮", provider: lspSemanticHighlighting),
            const SectionDivider(),
            _CapabilitySwitch(title: "代码补全", provider: lspCodeCompletion),
            const SectionDivider(),
            _CapabilitySwitch(title: "悬浮提示", provider: lspHoverInfo),
            const SectionDivider(),
            _CapabilitySwitch(title: "代码操作", provider: lspCodeAction),
            const SectionDivider(),
            _CapabilitySwitch(title: "签名帮助", provider: lspSignatureHelp),
            const SectionDivider(),
            _CapabilitySwitch(title: "文档颜色", provider: lspDocumentColor),
            const SectionDivider(),
            _CapabilitySwitch(title: "文档高亮", provider: lspDocumentHighlight),
            const SectionDivider(),
            _CapabilitySwitch(title: "代码折叠", provider: lspCodeFolding),
            const SectionDivider(),
            _CapabilitySwitch(title: "内联提示", provider: lspInlayHint),
            const SectionDivider(),
            _CapabilitySwitch(title: "跳转定义", provider: lspGoToDefinition),
            const SectionDivider(),
            _CapabilitySwitch(title: "重命名符号", provider: lspRename),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text("语言服务器设置")),
      body: body,
    );
  }

  String _layersSummary(List<MicroPythonStubsLayer> layers) {
    if (layers.isEmpty) return "未配置";
    return layers.map((layer) => '${layer.provider}/${layer.profile}').join(', ');
  }

  String _pathsSummary(List<String> paths) {
    if (paths.isEmpty) return "未配置";
    return paths.length == 1 ? paths.first : "${paths.length} 个路径";
  }

  void _showLayersDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: ref
          .read(microPythonStubsLayers)
          .map((layer) => '${layer.provider}/${layer.profile}')
          .join('\n'),
    );
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Stubs Layers"),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: controller,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              helperText: "每行一个 layer，格式：provider/profile。上方优先级更高。",
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text("取消")),
          FilledButton(
            onPressed: () {
              final layers = controller.text
                  .split('\n')
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty)
                  .map((line) {
                    final parts = line.split('/');
                    if (parts.length < 2) return null;
                    return MicroPythonStubsLayer(
                      provider: parts.first.trim(),
                      profile: parts.sublist(1).join('/').trim(),
                    );
                  })
                  .whereType<MicroPythonStubsLayer>()
                  .where((layer) => layer.provider.isNotEmpty && layer.profile.isNotEmpty)
                  .toList();
              ref.read(microPythonStubsLayers.notifier).state = layers;
              context.pop();
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  void _showExtraPathsDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: ref.read(microPythonStubsExtraPaths).join('\n'),
    );
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("额外 Stubs 路径"),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: controller,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              helperText: "每行一个本地路径，会追加给语言服务使用。",
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text("取消")),
          FilledButton(
            onPressed: () {
              ref.read(microPythonStubsExtraPaths.notifier).state = controller.text
                  .split('\n')
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty)
                  .toList();
              context.pop();
            },
            child: const Text("保存"),
          ),
        ],
      ),
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

class _CapabilitySwitch extends ConsumerWidget {
  const _CapabilitySwitch({required this.title, required this.provider});

  final String title;
  final StateProvider<bool> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      title: Text(title),
      value: ref.watch(provider),
      onChanged: (value) => ref.read(provider.notifier).state = value,
    );
  }
}
