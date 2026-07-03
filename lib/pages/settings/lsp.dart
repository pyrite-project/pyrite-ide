import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_refresh.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';

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

            ListTile(
              title: const Text("连接方式"),
              subtitle: Text(
                ref.watch(lspType) == LspType.webSocket
                    ? "WebSocket"
                    : "stdio (本地进程)",
              ),
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
              ListTile(
                title: const Text("WebSocket 地址"),
                subtitle: Text("ws://${ref.watch(lspWebSocketPath)}"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showPathDialog(context, ref),
              ),
            ] else ...[
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
                      onChanged: (value) {
                        ref.read(lspStdioExecutable.notifier).state = value;
                      },
                      onFieldSubmitted: (value) {
                        ref.read(lspStdioExecutable.notifier).state = value
                            .trim();
                        showIdeSuccess(context, "可执行文件路径已更新");
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
                      onChanged: (value) {
                        ref.read(lspStdioArgs.notifier).state = value;
                      },
                      onFieldSubmitted: (value) {
                        ref.read(lspStdioArgs.notifier).state = value.trim();
                        showIdeSuccess(context, "启动参数已更新");
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

            SwitchListTile(
              title: const Text("自动检测 Layer"),
              subtitle: const Text("后续可根据连接设备推荐 generic/port/board stubs"),
              value: ref.watch(microPythonStubsAutoDetectLayers),
              onChanged: (value) {
                ref.read(microPythonStubsAutoDetectLayers.notifier).state =
                    value;
              },
            ),

            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text("Stubs Layers"),
              subtitle: Text(_layersSummary(ref.watch(microPythonStubsLayers))),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showLayersDialog(context, ref),
            ),

            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text("额外路径"),
              subtitle: Text(
                _pathsSummary(ref.watch(microPythonStubsExtraPaths)),
              ),
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

            _CapabilitySwitch(title: "代码补全", provider: lspCodeCompletion),

            _CapabilitySwitch(title: "悬浮提示", provider: lspHoverInfo),

            _CapabilitySwitch(title: "代码操作", provider: lspCodeAction),

            _CapabilitySwitch(title: "签名帮助", provider: lspSignatureHelp),

            _CapabilitySwitch(title: "文档颜色", provider: lspDocumentColor),

            _CapabilitySwitch(title: "文档高亮", provider: lspDocumentHighlight),

            _CapabilitySwitch(title: "代码折叠", provider: lspCodeFolding),

            _CapabilitySwitch(title: "内联提示", provider: lspInlayHint),

            _CapabilitySwitch(title: "跳转定义", provider: lspGoToDefinition),

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
    return layers
        .map((layer) => '${layer.provider}/${layer.profile}')
        .join(', ');
  }

  String _pathsSummary(List<String> paths) {
    if (paths.isEmpty) return "未配置";
    return paths.length == 1 ? paths.first : "${paths.length} 个路径";
  }

  void _showLayersDialog(BuildContext context, WidgetRef ref) async {
    final layers = List<MicroPythonStubsLayer>.from(
      ref.read(microPythonStubsLayers),
    );
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final providers = ref.read(dataRegistryProvider).allStubsProviders;
          return AlertDialog(
            title: const Text("Stubs Layers"),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (layers.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.layers_clear_outlined),
                      title: Text("未配置 Layer"),
                      subtitle: Text("添加 generic、port 或 board stubs layer"),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: layers.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) => _StubsLayerTile(
                          layer: layers[index],
                          profile: _findProfile(ref, layers[index]),
                          canMoveUp: index > 0,
                          canMoveDown: index < layers.length - 1,
                          onMoveUp: () => setDialogState(() {
                            final item = layers.removeAt(index);
                            layers.insert(index - 1, item);
                          }),
                          onMoveDown: () => setDialogState(() {
                            final item = layers.removeAt(index);
                            layers.insert(index + 1, item);
                          }),
                          onDelete: () => setDialogState(() {
                            layers.removeAt(index);
                          }),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: providers.isEmpty
                          ? null
                          : () async {
                              final layer = await _showAddLayerDialog(
                                context,
                                ref,
                                layers,
                              );
                              if (layer == null) return;
                              setDialogState(() => layers.add(layer));
                            },
                      icon: const Icon(Icons.add),
                      label: const Text("添加 Layer"),
                    ),
                  ),
                  if (providers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text("未找到 stubs provider，请先安装并启用 stubs 插件。"),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(),
                child: const Text("取消"),
              ),
              FilledButton(
                onPressed: () {
                  ref.read(microPythonStubsLayers.notifier).state =
                      List.unmodifiable(layers);
                  refreshOpenLspStubsConfiguration(ref);
                  context.pop();
                  showIdeSuccess(context, "Stubs Layers 已更新");
                },
                child: const Text("保存"),
              ),
            ],
          );
        },
      ),
    );
  }

  StubsProfileEntry? _findProfile(WidgetRef ref, MicroPythonStubsLayer layer) {
    return ref
        .read(dataRegistryProvider)
        .getStubsProfile(layer.provider, layer.profile);
  }

  Future<MicroPythonStubsLayer?> _showAddLayerDialog(
    BuildContext context,
    WidgetRef ref,
    List<MicroPythonStubsLayer> selected,
  ) async {
    final providers = ref.read(dataRegistryProvider).allStubsProviders;
    return showDialog<MicroPythonStubsLayer>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("添加 Stubs Layer"),
        content: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: providers.length,
              itemBuilder: (context, providerIndex) {
                final provider = providers[providerIndex];
                return ExpansionTile(
                  initiallyExpanded: providerIndex == 0,
                  title: Text(provider.providerId),
                  subtitle: Text(
                    [
                      if (provider.version.isNotEmpty) provider.version,
                      '${provider.profiles.length} profiles',
                    ].join(' · '),
                  ),
                  children: [
                    for (final profile in provider.profiles)
                      Builder(
                        builder: (context) {
                          final alreadySelected = selected.any(
                            (layer) =>
                                layer.provider == provider.providerId &&
                                layer.profile == profile.id,
                          );
                          return ListTile(
                            enabled: !alreadySelected,
                            title: Text(profile.label ?? profile.id),
                            subtitle: Text(
                              '${provider.providerId}/${profile.id}\n${profile.path}',
                            ),
                            isThreeLine: true,
                            trailing: alreadySelected
                                ? const Text("已添加")
                                : const Icon(Icons.add),
                            onTap: alreadySelected
                                ? null
                                : () => context.pop(
                                    MicroPythonStubsLayer(
                                      provider: provider.providerId,
                                      profile: profile.id,
                                    ),
                                  ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text("取消")),
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
              ref.read(microPythonStubsExtraPaths.notifier).state = controller
                  .text
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
                showIdeError(context, "请输入有效的 WebSocket 地址");
                return;
              }
              ref.read(lspWebSocketPath.notifier).state = value;
              context.pop();
              showIdeSuccess(context, "语言服务器地址已更新");
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

class _StubsLayerTile extends StatelessWidget {
  const _StubsLayerTile({
    required this.layer,
    required this.profile,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final MicroPythonStubsLayer layer;
  final StubsProfileEntry? profile;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = profile?.label ?? '${layer.provider}/${layer.profile}';
    final subtitle = profile == null
        ? '未找到 profile: ${layer.provider}/${layer.profile}'
        : '${layer.provider}/${layer.profile}\n${profile!.path}';
    return ListTile(
      leading: Icon(
        profile == null ? Icons.warning_amber_outlined : Icons.layers_outlined,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      isThreeLine: profile != null,
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: '上移',
            onPressed: canMoveUp ? onMoveUp : null,
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            tooltip: '下移',
            onPressed: canMoveDown ? onMoveDown : null,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
