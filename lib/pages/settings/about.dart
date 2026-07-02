import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:vertical_card_pager/vertical_card_pager.dart';

class About extends StatelessWidget {
  const About({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> titles = ["", "现代化", "强大", "跨平台", "生态布局"];

    final List<Widget> images = [
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 15.0),
            child: Center(
              child: Hero(
                tag: 'app_icon',
                child: Image.asset(
                  width: 200,
                  height: 200,
                  "assets/icons/app_icon.png",
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const Hero(tag: "app_name", child: TextDisplayMedium("PyriteIDE")),
        ],
      ),
      Hero(
        tag: "feature_modern_image",
        child: ClipRRect(
          borderRadius: BorderRadiusGeometry.circular(10),
          child: Image.asset("assets/about/1.webp", fit: BoxFit.cover),
        ),
      ),
      Hero(
        tag: "feature_powerful_image",
        child: ClipRRect(
          borderRadius: BorderRadiusGeometry.circular(10),
          child: Image.asset("assets/about/2.webp", fit: BoxFit.cover),
        ),
      ),
      Hero(
        tag: "feature_cross_platform_image",
        child: ClipRRect(
          borderRadius: BorderRadiusGeometry.circular(10),
          child: Image.asset("assets/about/3.webp", fit: BoxFit.cover),
        ),
      ),
      Hero(
        tag: "about_project_image",
        child: ClipRRect(
          borderRadius: BorderRadiusGeometry.circular(10),
          child: Image.asset("assets/about/4.webp", fit: BoxFit.cover),
        ),
      ),
    ];

    final details = [
      "app_details",
      "feature/modern",
      "feature/powerful",
      "feature/cross_platform",
      "project",
    ];

    return Scaffold(
      appBar: AppBar(title: const UseText("关于")),
      body: Column(
        children: <Widget>[
          Expanded(
            child: VerticalCardPager(
              titles: titles,
              images: images,
              textStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              onSelectedItem: (index) {
                context.go("/settings/about/${details[index]}");
              },
              initialPage: 0,
              align: ALIGN.CENTER,
              physics: const ClampingScrollPhysics(),
            ),
          ),
        ],
      ),
    );
  }
}

class AppDetails extends ConsumerStatefulWidget {
  const AppDetails({super.key});

  @override
  ConsumerState<AppDetails> createState() => _AppDetailsState();
}

class _AppDetailsState extends ConsumerState<AppDetails> {
  late final Future<_DiagnosticInfo> _diagnosticInfo = _loadDiagnosticInfo();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("应用与设备信息")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Hero(
                tag: 'app_icon',
                child: Image.asset(
                  width: 80,
                  height: 80,
                  "assets/icons/app_icon.png",
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 20),
              const Hero(
                tag: "app_name",
                child: TextDisplayMedium("PyriteIDE"),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FutureBuilder<_DiagnosticInfo>(
            future: _diagnosticInfo,
            builder: (context, snapshot) {
              final info = snapshot.data;
              if (info == null) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final diagnostics = _buildDiagnosticsText(info);
              return Column(
                children: [
                  SettingsSection(
                    title: "运行路径",
                    description: "这些路径直接对应应用数据、插件和缓存位置。",
                    children: [
                      _CopyableInfoTile(
                        icon: Icons.folder_outlined,
                        title: "应用支持目录",
                        value: info.supportPath,
                      ),
                      const SectionDivider(),
                      _CopyableInfoTile(
                        icon: Icons.extension_outlined,
                        title: "插件目录",
                        value: info.pluginPath,
                      ),
                      const SectionDivider(),
                      _CopyableInfoTile(
                        icon: Icons.cached_outlined,
                        title: "缓存目录",
                        value: info.cachePath,
                      ),
                      const SectionDivider(),
                      _CopyableInfoTile(
                        icon: Icons.folder_special_outlined,
                        title: "临时目录",
                        value: info.tempPath,
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: "运行状态",
                    description: "从当前 Provider 状态读取，便于判断配置是否已生效。",
                    children: [
                      _InfoTile(
                        icon: Icons.computer,
                        title: "当前平台",
                        subtitle: info.platform,
                      ),
                      const SectionDivider(),
                      _InfoTile(
                        icon: Icons.extension_outlined,
                        title: "插件统计",
                        subtitle:
                            "已安装 ${info.pluginCount} 个，启用 ${info.enabledPluginCount} 个，Data 插件 ${info.dataPluginCount} 个。",
                      ),
                      const SectionDivider(),
                      _InfoTile(
                        icon: Icons.layers_outlined,
                        title: "Contribution",
                        subtitle:
                            "记录 ${info.contributionCount} 项，Stubs provider ${info.stubsProviderCount} 个。",
                      ),
                      const SectionDivider(),
                      _InfoTile(
                        icon: Icons.memory_outlined,
                        title: "Python Runtime",
                        subtitle:
                            "Runtime asset: ${info.pythonAsset}\nBoot asset: assets/python_runtime_boot.zip",
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: "关键设置",
                    description: "展示会影响调试、串口和语言服务行为的实际配置。",
                    children: [
                      _InfoTile(
                        icon: Icons.speed,
                        title: "默认波特率",
                        subtitle: "${info.baudRate} baud",
                      ),
                      const SectionDivider(),
                      _InfoTile(
                        icon: Icons.replay_outlined,
                        title: "串口自动重连",
                        subtitle: info.autoReconnect ? "已启用" : "未启用",
                      ),
                      const SectionDivider(),
                      _InfoTile(
                        icon: Icons.code_outlined,
                        title: "MicroPython Stubs",
                        subtitle:
                            "${info.stubsEnabled ? '已启用' : '未启用'}，Layers: ${info.stubsLayersSummary}",
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: "诊断摘要",
                    description: "复制这段内容可以直接用于反馈环境问题。",
                    children: [
                      ExpansionTile(
                        leading: const Icon(Icons.fact_check_outlined),
                        title: const Text("查看完整摘要"),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: SelectableText(diagnostics),
                          ),
                        ],
                      ),
                      const SectionDivider(),
                      ListTile(
                        leading: const Icon(Icons.copy_outlined),
                        title: const Text("复制诊断信息"),
                        subtitle: const Text(
                          "包含目录、插件、Contribution、串口和 stubs 设置",
                        ),
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: diagnostics),
                          );
                          if (context.mounted) {
                            showIdeSuccess(context, "诊断信息已复制");
                          }
                        },
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<_DiagnosticInfo> _loadDiagnosticInfo() async {
    final support = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    final temp = await getTemporaryDirectory();
    final plugins = ref.read(pluginManagerProvider).values.toList();
    final contributions = ref.read(dataContributionsProvider);
    final registry = ref.read(dataRegistryProvider);
    final layers = ref.read(microPythonStubsLayers);
    return _DiagnosticInfo(
      platform: Platform.operatingSystem,
      supportPath: support.path,
      pluginPath: path.join(support.path, 'plugin'),
      cachePath: cache.path,
      tempPath: temp.path,
      pythonAsset: _pythonAssetPath(),
      pluginCount: plugins
          .where((plugin) => plugin.status != PluginStatus.uninstalled)
          .length,
      enabledPluginCount: plugins
          .where((plugin) => plugin.status == PluginStatus.usable)
          .length,
      dataPluginCount: plugins
          .where((plugin) => plugin.type == PluginType.data)
          .length,
      contributionCount: contributions.length,
      stubsProviderCount: registry.allStubsProviders.length,
      baudRate: ref.read(serialDefaultBaudRate),
      autoReconnect: ref.read(serialAutoReconnect),
      stubsEnabled: ref.read(microPythonStubsEnabled),
      stubsLayersSummary: layers.isEmpty
          ? '未配置'
          : layers
                .map((layer) => '${layer.provider}/${layer.profile}')
                .join(', '),
    );
  }

  String _buildDiagnosticsText(_DiagnosticInfo info) {
    return [
      'PyriteIDE diagnostics',
      'Platform: ${info.platform}',
      'Support directory: ${info.supportPath}',
      'Plugin directory: ${info.pluginPath}',
      'Cache directory: ${info.cachePath}',
      'Temp directory: ${info.tempPath}',
      'Python runtime asset: ${info.pythonAsset}',
      'Python runtime boot: assets/python_runtime_boot.zip',
      'Plugins: installed=${info.pluginCount}, enabled=${info.enabledPluginCount}, data=${info.dataPluginCount}',
      'Contributions: records=${info.contributionCount}, stubsProviders=${info.stubsProviderCount}',
      'Serial: baudRate=${info.baudRate}, autoReconnect=${info.autoReconnect}',
      'MicroPython stubs: enabled=${info.stubsEnabled}, layers=${info.stubsLayersSummary}',
    ].join('\n');
  }

  String _pythonAssetPath() {
    if (Platform.isAndroid) return 'assets/android/python.zip';
    if (Platform.isWindows) return 'assets/windows/python.zip';
    if (Platform.isLinux) return 'assets/linux/python.zip';
    if (Platform.isMacOS) return 'assets/macos/python.zip';
    return 'unknown';
  }
}

class _DiagnosticInfo {
  const _DiagnosticInfo({
    required this.platform,
    required this.supportPath,
    required this.pluginPath,
    required this.cachePath,
    required this.tempPath,
    required this.pythonAsset,
    required this.pluginCount,
    required this.enabledPluginCount,
    required this.dataPluginCount,
    required this.contributionCount,
    required this.stubsProviderCount,
    required this.baudRate,
    required this.autoReconnect,
    required this.stubsEnabled,
    required this.stubsLayersSummary,
  });

  final String platform;
  final String supportPath;
  final String pluginPath;
  final String cachePath;
  final String tempPath;
  final String pythonAsset;
  final int pluginCount;
  final int enabledPluginCount;
  final int dataPluginCount;
  final int contributionCount;
  final int stubsProviderCount;
  final int baudRate;
  final bool autoReconnect;
  final bool stubsEnabled;
  final String stubsLayersSummary;
}

class FeatureModern extends StatelessWidget {
  const FeatureModern({super.key});

  @override
  Widget build(BuildContext context) {
    return _AboutDetailPage(
      title: "现代化的 PyriteIDE",
      heroTag: "feature_modern_image",
      image: "assets/about/1.webp",
      children: [
        SettingsSection(
          title: "界面体验",
          description: "围绕开发工作流设计，减少干扰并保持信息密度。",
          children: const [
            _InfoTile(
              icon: Icons.dashboard_customize_outlined,
              title: "Material Design 3",
              subtitle: "简洁，一致",
            ),

            _InfoTile(
              icon: Icons.view_column_outlined,
              title: "响应式布局",
              subtitle: "桌面、平板和移动布局分别优化导航和编辑区空间。",
            ),

            _InfoTile(
              icon: Icons.tab_outlined,
              title: "多标签编辑",
              subtitle: "标签页、未保存状态和编辑器状态会在会话间恢复。",
            ),
          ],
        ),
        SettingsSection(
          title: "交互预览",
          description: "直接展示 PyriteIDE 常用的 Material Design 3 控件。",
          children: const [
            _MaterialComponentShowcase(),
            _ThemeModePreview(),
            _DensityPreview(),
          ],
        ),
      ],
    );
  }
}

class FeaturePowerful extends StatelessWidget {
  const FeaturePowerful({super.key});

  @override
  Widget build(BuildContext context) {
    return _AboutDetailPage(
      title: "强大的 PyriteIDE",
      heroTag: "feature_powerful_image",
      image: "assets/about/2.webp",
      children: [
        SettingsSection(
          title: "开发能力",
          description: "编辑、设备、语言服务和插件能力组合成完整工作流。",
          children: const [
            _CapabilityExpansion(
              icon: Icons.code,
              title: "编辑器与 LSP",
              items: ["多标签编辑", "语言服务器配置", "MicroPython Stubs Layers"],
            ),

            _CapabilityExpansion(
              icon: Icons.developer_board_outlined,
              title: "设备与串口",
              items: ["串口 REPL", "文件上传/下载差异确认", "WebREPL 配置"],
            ),

            _CapabilityExpansion(
              icon: Icons.extension_outlined,
              title: "插件 SDK",
              items: ["UI 插件", "后台 Service 插件", "Data Contribution 插件"],
            ),
          ],
        ),
        const SettingsSection(
          title: "当前配置快照",
          description: "从真实设置 provider 读取，不展示静态宣传语。",
          children: [_RuntimeSettingsSnapshot()],
        ),
        SettingsSection(
          title: "快捷入口",
          children: [
            ListTile(
              leading: const Icon(Icons.terminal_outlined),
              title: const Text("调试与终端设置"),
              subtitle: const Text("配置串口、WebREPL 和终端显示"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/terminal'),
            ),

            ListTile(
              leading: const Icon(Icons.language_outlined),
              title: const Text("语言服务器设置"),
              subtitle: const Text("配置 LSP 与 MicroPython stubs"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/lsp'),
            ),
          ],
        ),
      ],
    );
  }
}

class FeatureCrossPlatform extends StatelessWidget {
  const FeatureCrossPlatform({super.key});

  @override
  Widget build(BuildContext context) {
    return _AboutDetailPage(
      title: "跨平台的 PyriteIDE",
      heroTag: "feature_cross_platform_image",
      image: "assets/about/3.webp",
      children: [
        const SettingsSection(
          title: "平台能力",
          description: "选择平台查看主要支持能力。",
          children: [_PlatformMatrix()],
        ),
        SettingsSection(
          title: "当前平台",
          description: "从 Dart 运行时读取的系统信息。",
          children: [
            _InfoTile(
              icon: Icons.computer,
              title: "操作系统",
              subtitle: Platform.operatingSystem,
            ),
            _InfoTile(
              icon: Icons.info_outline,
              title: "系统版本",
              subtitle: Platform.operatingSystemVersion,
            ),
          ],
        ),
        const SettingsSection(
          title: "设计原则",
          children: [
            _InfoTile(
              icon: Icons.devices_outlined,
              title: "同一工作流，多端呈现",
              subtitle: "核心编辑、设置和插件模型保持一致，平台差异集中在设备和终端能力。",
            ),

            _InfoTile(
              icon: Icons.desktop_windows_outlined,
              title: "桌面优先的终端能力",
              subtitle: "桌面终端依赖本地 pty，Android 中会禁用相关入口。",
            ),

            _InfoTile(
              icon: Icons.usb_outlined,
              title: "移动端设备连接",
              subtitle: "Android 侧重点是 USB 串口和设备文件操作。",
            ),
          ],
        ),
      ],
    );
  }
}

class AboutProject extends StatelessWidget {
  const AboutProject({super.key});

  @override
  Widget build(BuildContext context) {
    return _AboutDetailPage(
      title: "生态布局",
      heroTag: "about_project_image",
      image: "assets/about/4.webp",
      children: [
        SettingsSection(
          title: "生态层次",
          description: "PyriteIDE 的能力被拆成核心、运行时、插件和数据贡献几个层次。",
          children: const [
            _EcosystemTile(
              icon: Icons.hub_outlined,
              title: "IDE Core",
              subtitle: "编辑器、设置、标签页、输出面板和设备工作流。",
            ),

            _EcosystemTile(
              icon: Icons.integration_instructions_outlined,
              title: "PyriteSDK",
              subtitle: "UI、Service、Data 三类插件，按权限访问 IDE 能力。",
            ),

            _EcosystemTile(
              icon: Icons.layers_outlined,
              title: "Data Contribution",
              subtitle: "主题、语言包、stubs 等数据由 IDE 持久管理。",
            ),

            _EcosystemTile(
              icon: Icons.memory_outlined,
              title: "Python Runtime",
              subtitle: "插件进程通过 bridge 与 IDE 通信，Data 插件贡献完成即可退出。",
            ),
          ],
        ),
        const SettingsSection(
          title: "当前生态状态",
          description: "从插件管理器和数据 registry 读取当前状态。",
          children: [_EcosystemSnapshot()],
        ),
        SettingsSection(
          title: "模块展开",
          description: "查看每个生态模块负责的边界。",
          children: const [
            _CapabilityExpansion(
              icon: Icons.edit_note_outlined,
              title: "Editor / LSP",
              items: ["CodeForge 编辑器", "pylsp 集成", "Stubs Layers 配置刷新"],
            ),
            _CapabilityExpansion(
              icon: Icons.cable_outlined,
              title: "Serial / Board",
              items: ["串口连接", "REPL 输入输出", "开发板文件读写"],
            ),
            _CapabilityExpansion(
              icon: Icons.palette_outlined,
              title: "Theme / I18n / Stubs",
              items: ["主题贡献", "语言包贡献", "MicroPython 类型存根贡献"],
            ),
          ],
        ),
        SettingsSection(
          title: "开发者入口",
          children: [
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text("插件与 SDK 文档"),
              subtitle: const Text("https://pyrite.flowecho.org"),
              trailing: const Icon(Icons.copy_outlined),
              onTap: () => _copyPath(context, 'https://pyrite.flowecho.org'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AboutDetailPage extends StatelessWidget {
  const _AboutDetailPage({
    required this.title,
    required this.heroTag,
    required this.image,
    required this.children,
  });

  final String title;
  final String heroTag;
  final String image;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Hero(
              tag: heroTag,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    image: AssetImage(image),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(title),
          ],
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: children),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class _CopyableInfoTile extends StatelessWidget {
  const _CopyableInfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: SelectableText(value),
      trailing: const Icon(Icons.copy_outlined),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) {
          showIdeSuccess(context, "已复制：$title");
        }
      },
    );
  }
}

class _MaterialComponentShowcase extends StatefulWidget {
  const _MaterialComponentShowcase();

  @override
  State<_MaterialComponentShowcase> createState() =>
      _MaterialComponentShowcaseState();
}

class _MaterialComponentShowcaseState
    extends State<_MaterialComponentShowcase> {
  bool _switchOn = true;
  bool _checked = true;
  double _slider = 0.65;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => showIdeSuccess(context, "FilledButton 可用"),
                icon: const Icon(Icons.check),
                label: const Text("Filled"),
              ),
              OutlinedButton.icon(
                onPressed: () => showIdeMessage(context, "OutlinedButton 可用"),
                icon: const Icon(Icons.touch_app_outlined),
                label: const Text("Outlined"),
              ),
              FilterChip(
                selected: _checked,
                avatar: const Icon(Icons.filter_alt_outlined),
                label: const Text("FilterChip"),
                onSelected: (value) => setState(() => _checked = value),
              ),
              ActionChip(
                avatar: const Icon(Icons.copy_outlined),
                label: const Text("ActionChip"),
                onPressed: () => showIdeSuccess(context, "ActionChip 已触发"),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("SwitchListTile"),
                subtitle: const Text("展示设置项开关样式"),
                value: _switchOn,
                onChanged: (value) => setState(() => _switchOn = value),
              ),
              Slider(
                value: _slider,
                onChanged: (value) => setState(() => _slider = value),
              ),
              // LinearProgressIndicator(value: _slider),
            ],
          ),
        ],
      ),
    );
  }
}

class _RuntimeSettingsSnapshot extends ConsumerWidget {
  const _RuntimeSettingsSnapshot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layers = ref.watch(microPythonStubsLayers);
    return Column(
      children: [
        _InfoTile(
          icon: Icons.speed,
          title: "串口默认波特率",
          subtitle: "${ref.watch(serialDefaultBaudRate)} baud",
        ),
        const SectionDivider(),
        _InfoTile(
          icon: Icons.replay_outlined,
          title: "串口自动重连",
          subtitle: ref.watch(serialAutoReconnect) ? "已启用" : "未启用",
        ),
        const SectionDivider(),
        _InfoTile(
          icon: Icons.layers_outlined,
          title: "MicroPython Stubs Layers",
          subtitle: layers.isEmpty
              ? "未配置"
              : layers
                    .map((layer) => '${layer.provider}/${layer.profile}')
                    .join(', '),
        ),
        const SectionDivider(),
        _InfoTile(
          icon: Icons.terminal_outlined,
          title: "终端显示",
          subtitle:
              "${ref.watch(terminalFontFamily)} · ${ref.watch(terminalFontSize).toStringAsFixed(0)}px · 行高 ${ref.watch(terminalLineHeight).toStringAsFixed(1)}",
        ),
      ],
    );
  }
}

class _EcosystemSnapshot extends ConsumerWidget {
  const _EcosystemSnapshot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref
        .watch(pluginManagerProvider)
        .values
        .where((plugin) => plugin.status != PluginStatus.uninstalled)
        .toList();
    final dataPlugins = plugins
        .where((plugin) => plugin.type == PluginType.data)
        .length;
    final enabled = plugins
        .where((plugin) => plugin.status == PluginStatus.usable)
        .length;
    final contributions = ref.watch(dataContributionsProvider);
    final registry = ref.watch(dataRegistryProvider);
    return Column(
      children: [
        _InfoTile(
          icon: Icons.extension_outlined,
          title: "插件数量",
          subtitle:
              "已安装 ${plugins.length} 个，启用 $enabled 个，Data 插件 $dataPlugins 个。",
        ),
        const SectionDivider(),
        _InfoTile(
          icon: Icons.layers_outlined,
          title: "Contribution 记录",
          subtitle: "${contributions.length} 项持久记录",
        ),
        const SectionDivider(),
        _InfoTile(
          icon: Icons.code_outlined,
          title: "Stubs Provider",
          subtitle: "当前注册 ${registry.allStubsProviders.length} 个 provider",
        ),
      ],
    );
  }
}

class _ThemeModePreview extends StatefulWidget {
  const _ThemeModePreview();

  @override
  State<_ThemeModePreview> createState() => _ThemeModePreviewState();
}

class _ThemeModePreviewState extends State<_ThemeModePreview> {
  String _value = 'system';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'system',
            icon: Icon(Icons.auto_mode),
            label: Text("自动"),
          ),
          ButtonSegment(
            value: 'light',
            icon: Icon(Icons.light_mode),
            label: Text("日光"),
          ),
          ButtonSegment(
            value: 'dark',
            icon: Icon(Icons.dark_mode),
            label: Text("黑夜"),
          ),
        ],
        selected: {_value},
        onSelectionChanged: (value) => setState(() => _value = value.first),
      ),
    );
  }
}

class _DensityPreview extends StatelessWidget {
  const _DensityPreview();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: const [
          Chip(avatar: Icon(Icons.lan), label: Text("标准")),
          Chip(avatar: Icon(Icons.window), label: Text("紧凑")),
          Chip(avatar: Icon(Icons.space_dashboard), label: Text("舒适")),
        ],
      ),
    );
  }
}

class _CapabilityExpansion extends StatelessWidget {
  const _CapabilityExpansion({
    required this.icon,
    required this.title,
    required this.items,
  });

  final IconData icon;
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(icon),
      title: Text(title),
      children: [
        for (final item in items)
          ListTile(
            dense: true,
            leading: const Icon(Icons.check_circle_outline),
            title: Text(item),
          ),
      ],
    );
  }
}

class _PlatformMatrix extends StatefulWidget {
  const _PlatformMatrix();

  @override
  State<_PlatformMatrix> createState() => _PlatformMatrixState();
}

class _PlatformMatrixState extends State<_PlatformMatrix> {
  String _platform = Platform.isAndroid ? 'android' : 'desktop';

  @override
  Widget build(BuildContext context) {
    final capabilities = _platform == 'desktop'
        ? ["本地文件", "桌面终端", "USB 串口", "Python 插件", "LSP"]
        : ["移动布局", "USB 串口", "开发板文件", "Python 插件", "LSP"];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'desktop',
                icon: Icon(Icons.desktop_windows),
                label: Text("桌面"),
              ),
              ButtonSegment(
                value: 'android',
                icon: Icon(Icons.phone_android),
                label: Text("Android"),
              ),
            ],
            selected: {_platform},
            onSelectionChanged: (value) =>
                setState(() => _platform = value.first),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final capability in capabilities)
                Chip(avatar: const Icon(Icons.check), label: Text(capability)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EcosystemTile extends StatelessWidget {
  const _EcosystemTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.account_tree_outlined),
    );
  }
}

Future<void> _copyPath(BuildContext context, String path) async {
  await Clipboard.setData(ClipboardData(text: path));
  if (context.mounted) {
    showIdeSuccess(context, "文档路径已复制");
  }
}
