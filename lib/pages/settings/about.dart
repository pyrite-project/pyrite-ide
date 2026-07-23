import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:vertical_card_pager/vertical_card_pager.dart';

class About extends ConsumerWidget {
  const About({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<String> titles = [
      "",
      translateForWidget(ref, I18nKey.aboutCardModern),
      translateForWidget(ref, I18nKey.aboutCardPowerful),
      translateForWidget(ref, I18nKey.aboutCardCrossPlatform),
      translateForWidget(ref, I18nKey.aboutCardEcosystem),
    ];

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
                  "assets/icons/app_icon.webp",
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
      appBar: AppBar(title: const UseText(I18nKey.aboutTitle)),
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
      appBar: AppBar(title: const UseText(I18nKey.aboutAppDetailsTitle)),
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
                  "assets/icons/app_icon.webp",
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
                    title: I18nKey.aboutRuntimePaths,
                    description: I18nKey.aboutRuntimePathsDescription,
                    children: [
                      _CopyableInfoTile(
                        icon: Icons.folder_outlined,
                        title: I18nKey.aboutSupportDirectory,
                        value: info.supportPath,
                      ),
                      const SectionDivider(),
                      _CopyableInfoTile(
                        icon: Icons.extension_outlined,
                        title: I18nKey.aboutPluginDirectory,
                        value: info.pluginPath,
                      ),
                      const SectionDivider(),
                      _CopyableInfoTile(
                        icon: Icons.cached_outlined,
                        title: I18nKey.aboutCacheDirectory,
                        value: info.cachePath,
                      ),
                      const SectionDivider(),
                      _CopyableInfoTile(
                        icon: Icons.folder_special_outlined,
                        title: I18nKey.aboutTempDirectory,
                        value: info.tempPath,
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: I18nKey.aboutRuntimeStatus,
                    description: I18nKey.aboutRuntimeStatusDescription,
                    children: [
                      _InfoTile(
                        icon: Icons.computer,
                        title: I18nKey.aboutCurrentPlatform,
                        subtitle: info.platform,
                      ),
                      const SectionDivider(),
                      _InfoTile(
                        icon: Icons.extension_outlined,
                        title: I18nKey.aboutPluginStats,
                        subtitle:
                            translateForWidget(
                                  ref,
                                  I18nKey.aboutPluginStatsValue,
                                )
                                .replaceAll(
                                  '{installed}',
                                  info.pluginCount.toString(),
                                )
                                .replaceAll(
                                  '{enabled}',
                                  info.enabledPluginCount.toString(),
                                )
                                .replaceAll(
                                  '{data}',
                                  info.dataPluginCount.toString(),
                                ),
                      ),
                      const SectionDivider(),
                      _InfoTile(
                        icon: Icons.layers_outlined,
                        title: "Contribution",
                        subtitle:
                            translateForWidget(
                                  ref,
                                  I18nKey.aboutContributionStatsValue,
                                )
                                .replaceAll(
                                  '{records}',
                                  info.contributionCount.toString(),
                                )
                                .replaceAll(
                                  '{providers}',
                                  info.stubsProviderCount.toString(),
                                ),
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
                    title: I18nKey.aboutKeySettings,
                    description: I18nKey.aboutKeySettingsDescription,
                    children: [
                      _InfoTile(
                        icon: Icons.speed,
                        title: I18nKey.aboutDefaultBaudRate,
                        subtitle: "${info.baudRate} baud",
                      ),
                      const SectionDivider(),
                      _InfoTile(
                        icon: Icons.replay_outlined,
                        title: I18nKey.aboutSerialAutoReconnect,
                        subtitle: info.autoReconnect
                            ? translateForWidget(ref, I18nKey.commonEnabled)
                            : translateForWidget(ref, I18nKey.commonDisabled),
                      ),
                      const SectionDivider(),
                      _InfoTile(
                        icon: Icons.code_outlined,
                        title: "MicroPython Stubs",
                        subtitle:
                            translateForWidget(
                                  ref,
                                  I18nKey.aboutStubsStatusValue,
                                )
                                .replaceAll(
                                  '{status}',
                                  info.stubsEnabled
                                      ? translateForWidget(
                                          ref,
                                          I18nKey.commonEnabled,
                                        )
                                      : translateForWidget(
                                          ref,
                                          I18nKey.commonDisabled,
                                        ),
                                )
                                .replaceAll(
                                  '{layers}',
                                  info.stubsLayersSummary,
                                ),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: I18nKey.aboutDiagnosticsSummary,
                    description: I18nKey.aboutDiagnosticsDescription,
                    children: [
                      ExpansionTile(
                        leading: const Icon(Icons.fact_check_outlined),
                        title: const UseText(I18nKey.aboutViewFullSummary),
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
                        title: const UseText(I18nKey.aboutCopyDiagnostics),
                        subtitle: const UseText(
                          I18nKey.aboutCopyDiagnosticsSubtitle,
                        ),
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: diagnostics),
                          );
                          if (context.mounted) {
                            showIdeSuccess(
                              context,
                              translateForWidget(
                                ref,
                                I18nKey.aboutDiagnosticsCopied,
                              ),
                            );
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
          ? I18nKey.settingsLspNotConfigured.fallback
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
      title: I18nKey.aboutModernTitle,
      heroTag: "feature_modern_image",
      image: "assets/about/1.webp",
      children: [
        SettingsSection(
          title: I18nKey.aboutModernExperience,
          description: I18nKey.aboutModernExperienceDescription,
          children: const [
            _InfoTile(
              icon: Icons.dashboard_customize_outlined,
              title: "Material Design 3",
              subtitle: I18nKey.aboutModernSimple,
            ),

            _InfoTile(
              icon: Icons.view_column_outlined,
              title: I18nKey.aboutModernResponsive,
              subtitle: I18nKey.aboutModernResponsiveSubtitle,
            ),

            _InfoTile(
              icon: Icons.tab_outlined,
              title: I18nKey.aboutModernTabs,
              subtitle: I18nKey.aboutModernTabsSubtitle,
            ),
          ],
        ),
        SettingsSection(
          title: I18nKey.aboutModernPreview,
          description: I18nKey.aboutModernPreviewDescription,
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
      title: I18nKey.aboutPowerfulTitle,
      heroTag: "feature_powerful_image",
      image: "assets/about/2.webp",
      children: [
        SettingsSection(
          title: I18nKey.aboutPowerfulCapability,
          description: I18nKey.aboutPowerfulCapabilityDescription,
          children: const [
            _CapabilityExpansion(
              icon: Icons.code,
              title: I18nKey.aboutEditorLsp,
              items: [
                I18nKey.aboutModernTabs,
                I18nKey.settingsLspPageTitle,
                "MicroPython Stubs Layers",
              ],
            ),

            _CapabilityExpansion(
              icon: Icons.developer_board_outlined,
              title: I18nKey.aboutDeviceSerial,
              items: [
                "Serial REPL",
                I18nKey.aboutFileSyncDiff,
                I18nKey.aboutWebReplConfig,
              ],
            ),

            _CapabilityExpansion(
              icon: Icons.extension_outlined,
              title: I18nKey.aboutPluginSdk,
              items: [
                I18nKey.aboutUiPlugins,
                I18nKey.aboutServicePlugins,
                I18nKey.aboutDataContributionPlugins,
              ],
            ),
          ],
        ),
        const SettingsSection(
          title: I18nKey.aboutCurrentConfigSnapshot,
          description: I18nKey.aboutCurrentConfigSnapshotDescription,
          children: [_RuntimeSettingsSnapshot()],
        ),
        SettingsSection(
          title: I18nKey.aboutQuickLinks,
          children: [
            ListTile(
              leading: const Icon(Icons.terminal_outlined),
              title: const UseText(I18nKey.aboutTerminalSettingsLink),
              subtitle: const UseText(
                I18nKey.aboutTerminalSettingsLinkSubtitle,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/terminal'),
            ),

            ListTile(
              leading: const Icon(Icons.language_outlined),
              title: const UseText(I18nKey.aboutLspSettingsLink),
              subtitle: const UseText(I18nKey.aboutLspSettingsLinkSubtitle),
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
      title: I18nKey.aboutCrossPlatformTitle,
      heroTag: "feature_cross_platform_image",
      image: "assets/about/3.webp",
      children: [
        const SettingsSection(
          title: I18nKey.aboutPlatformCapability,
          description: I18nKey.aboutPlatformCapabilityDescription,
          children: [_PlatformMatrix()],
        ),
        SettingsSection(
          title: I18nKey.aboutCurrentPlatform,
          description: I18nKey.aboutCurrentPlatformDescription,
          children: [
            _InfoTile(
              icon: Icons.computer,
              title: I18nKey.aboutOperatingSystem,
              subtitle: Platform.operatingSystem,
            ),
            _InfoTile(
              icon: Icons.info_outline,
              title: I18nKey.aboutSystemVersion,
              subtitle: Platform.operatingSystemVersion,
            ),
          ],
        ),
        const SettingsSection(
          title: I18nKey.aboutDesignPrinciples,
          children: [
            _InfoTile(
              icon: Icons.devices_outlined,
              title: I18nKey.aboutOneWorkflow,
              subtitle: I18nKey.aboutOneWorkflowSubtitle,
            ),

            _InfoTile(
              icon: Icons.desktop_windows_outlined,
              title: I18nKey.aboutDesktopTerminalFirst,
              subtitle: I18nKey.aboutDesktopTerminalFirstSubtitle,
            ),

            _InfoTile(
              icon: Icons.usb_outlined,
              title: I18nKey.aboutMobileDeviceConnection,
              subtitle: I18nKey.aboutMobileDeviceConnectionSubtitle,
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
      title: I18nKey.aboutEcosystemTitle,
      heroTag: "about_project_image",
      image: "assets/about/4.webp",
      children: [
        SettingsSection(
          title: I18nKey.aboutEcosystemLayers,
          description: I18nKey.aboutEcosystemLayersDescription,
          children: const [
            _EcosystemTile(
              icon: Icons.hub_outlined,
              title: "IDE Core",
              subtitle: I18nKey.aboutCoreLayerSubtitle,
            ),

            _EcosystemTile(
              icon: Icons.integration_instructions_outlined,
              title: "PyriteSDK",
              subtitle: I18nKey.aboutPluginLayerSubtitle,
            ),

            _EcosystemTile(
              icon: Icons.layers_outlined,
              title: "Data Contribution",
              subtitle: I18nKey.aboutDataLayerSubtitle,
            ),

            _EcosystemTile(
              icon: Icons.memory_outlined,
              title: "Python Runtime",
              subtitle: I18nKey.aboutRuntimeLayerSubtitle,
            ),
          ],
        ),
        const SettingsSection(
          title: I18nKey.aboutEcosystemStatus,
          description: I18nKey.aboutEcosystemStatusDescription,
          children: [_EcosystemSnapshot()],
        ),
        SettingsSection(
          title: I18nKey.aboutModuleExpansion,
          description: I18nKey.aboutModuleExpansionDescription,
          children: const [
            _CapabilityExpansion(
              icon: Icons.edit_note_outlined,
              title: "Editor / LSP",
              items: [
                "CodeForge Editor",
                I18nKey.aboutPylspIntegration,
                I18nKey.aboutStubsRefresh,
              ],
            ),
            _CapabilityExpansion(
              icon: Icons.cable_outlined,
              title: "Serial / Board",
              items: [
                I18nKey.aboutUsbSerial,
                I18nKey.aboutReplIo,
                I18nKey.aboutBoardFiles,
              ],
            ),
            _CapabilityExpansion(
              icon: Icons.palette_outlined,
              title: "Theme / I18n / Stubs",
              items: [
                I18nKey.aboutThemeContribution,
                I18nKey.aboutLanguagePackContribution,
                I18nKey.aboutMicropythonStubsContribution,
              ],
            ),
          ],
        ),
        SettingsSection(
          title: I18nKey.aboutDeveloperEntry,
          children: [
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const UseText(I18nKey.aboutPluginSdkDocs),
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

  final Object title;
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
            UseText(title),
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
  final Object title;
  final Object subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: UseText(title),
      subtitle: UseText(subtitle),
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
  final Object title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: UseText(title),
      subtitle: SelectableText(value),
      trailing: const Icon(Icons.copy_outlined),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) {
          showIdeSuccess(
            context,
            I18nKey.aboutCopied.fallback.replaceAll(
              '{title}',
              title.toString(),
            ),
          );
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
                onPressed: () => showIdeSuccess(
                  context,
                  I18nKey.aboutFilledButtonAvailable.fallback,
                ),
                icon: const Icon(Icons.check),
                label: const Text("Filled"),
              ),
              OutlinedButton.icon(
                onPressed: () => showIdeMessage(
                  context,
                  I18nKey.aboutOutlinedButtonAvailable.fallback,
                ),
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
                onPressed: () => showIdeSuccess(
                  context,
                  I18nKey.aboutActionChipTriggered.fallback,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("SwitchListTile"),
                subtitle: const UseText(I18nKey.aboutSwitchSubtitle),
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
          title: I18nKey.aboutSerialDefaultBaudRate,
          subtitle: "${ref.watch(serialDefaultBaudRate)} baud",
        ),
        const SectionDivider(),
        _InfoTile(
          icon: Icons.replay_outlined,
          title: I18nKey.aboutSerialAutoReconnect,
          subtitle: ref.watch(serialAutoReconnect)
              ? I18nKey.commonEnabled
              : I18nKey.commonDisabled,
        ),
        const SectionDivider(),
        _InfoTile(
          icon: Icons.layers_outlined,
          title: "MicroPython Stubs Layers",
          subtitle: layers.isEmpty
              ? I18nKey.settingsLspNotConfigured.fallback
              : layers
                    .map((layer) => '${layer.provider}/${layer.profile}')
                    .join(', '),
        ),
        const SectionDivider(),
        _InfoTile(
          icon: Icons.terminal_outlined,
          title: I18nKey.aboutTerminalDisplay,
          subtitle: I18nKey.aboutTerminalDisplayValue.fallback
              .replaceAll('{font}', ref.watch(terminalFontFamily))
              .replaceAll(
                '{size}',
                ref.watch(terminalFontSize).toStringAsFixed(0),
              )
              .replaceAll(
                '{height}',
                ref.watch(terminalLineHeight).toStringAsFixed(1),
              ),
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
          title: I18nKey.aboutPluginCount,
          subtitle: I18nKey.aboutPluginStatsValue.fallback
              .replaceAll('{installed}', plugins.length.toString())
              .replaceAll('{enabled}', enabled.toString())
              .replaceAll('{data}', dataPlugins.toString()),
        ),
        const SectionDivider(),
        _InfoTile(
          icon: Icons.layers_outlined,
          title: I18nKey.aboutContributionRecords,
          subtitle: I18nKey.aboutContributionRecordsValue.fallback.replaceAll(
            '{count}',
            contributions.length.toString(),
          ),
        ),
        const SectionDivider(),
        _InfoTile(
          icon: Icons.code_outlined,
          title: "Stubs Provider",
          subtitle: I18nKey.aboutStubsProviderValue.fallback.replaceAll(
            '{count}',
            registry.allStubsProviders.length.toString(),
          ),
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
            label: UseText(I18nKey.settingsStyleModeAuto),
          ),
          ButtonSegment(
            value: 'light',
            icon: Icon(Icons.light_mode),
            label: UseText(I18nKey.settingsStyleModeLight),
          ),
          ButtonSegment(
            value: 'dark',
            icon: Icon(Icons.dark_mode),
            label: UseText(I18nKey.settingsStyleModeDark),
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
          Chip(
            avatar: Icon(Icons.lan),
            label: UseText(I18nKey.settingsStyleStandard),
          ),
          Chip(
            avatar: Icon(Icons.window),
            label: UseText(I18nKey.settingsStyleCompact),
          ),
          Chip(
            avatar: Icon(Icons.space_dashboard),
            label: UseText(I18nKey.settingsStyleComfortable),
          ),
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
  final Object title;
  final List<Object> items;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(icon),
      title: UseText(title),
      children: [
        for (final item in items)
          ListTile(
            dense: true,
            leading: const Icon(Icons.check_circle_outline),
            title: UseText(item),
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
        ? [
            I18nKey.aboutLocalFiles,
            I18nKey.aboutDesktopTerminal,
            I18nKey.aboutUsbSerial,
            I18nKey.aboutPythonPlugins,
            "LSP",
          ]
        : [
            I18nKey.aboutMobileLayout,
            I18nKey.aboutUsbSerial,
            I18nKey.aboutBoardFiles,
            I18nKey.aboutPythonPlugins,
            "LSP",
          ];
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
                label: UseText(I18nKey.aboutDesktop),
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
                Chip(
                  avatar: const Icon(Icons.check),
                  label: UseText(capability),
                ),
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
  final Object title;
  final Object subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: UseText(title),
      subtitle: UseText(subtitle),
      trailing: const Icon(Icons.account_tree_outlined),
    );
  }
}

Future<void> _copyPath(BuildContext context, String path) async {
  await Clipboard.setData(ClipboardData(text: path));
  if (context.mounted) {
    showIdeSuccess(context, I18nKey.aboutDocsPathCopied.fallback);
  }
}
