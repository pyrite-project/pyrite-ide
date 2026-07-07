import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';

class StyleSettings extends ConsumerWidget {
  const StyleSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeColorValue = ref.watch(themeColor);
    final activePluginThemeIdValue = ref.watch(activePluginThemeId);
    final dataRegistry = ref.watch(dataRegistryProvider);

    final hasPluginTheme = activePluginThemeIdValue != null;
    final pluginTheme = hasPluginTheme
        ? dataRegistry.getThemeById(activePluginThemeIdValue)
        : null;
    // If plugin theme forces a mode, ThemeMode setting is disabled
    final themeModeDisabled = pluginTheme?.mode != null;

    final body = ListView(
      padding: EdgeInsets.all(12),
      children: [
        SettingsSection(
          title: "主题模式",
          description: themeModeDisabled
              ? "当前插件主题已锁定为${pluginTheme?.mode == 'dark' ? '暗色' : '亮色'}模式。"
              : "决定界面跟随系统、常亮或常暗。",
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.auto_mode),
                    label: Text("自动"),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode),
                    label: Text("日光"),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode),
                    label: Text("黑夜"),
                  ),
                ],
                selected: {ref.watch(themeMode)},
                onSelectionChanged: themeModeDisabled
                    ? null
                    : (value) {
                        ref.read(themeMode.notifier).state = value.first;
                      },
              ),
            ),
          ],
        ),
        SettingsSection(
          title: "主题风格",
          description: hasPluginTheme ? "插件主题启用时此项不可用。" : "切换不同风格的组件样式与布局密度。",
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<ThemeStyle>(
                segments: const [
                  ButtonSegment(
                    value: ThemeStyle.standard,
                    icon: Icon(Icons.lan),
                    label: Text("标准"),
                  ),
                  ButtonSegment(
                    value: ThemeStyle.compact,
                    icon: Icon(Icons.window),
                    label: Text("紧凑"),
                  ),
                  ButtonSegment(
                    value: ThemeStyle.comfortable,
                    icon: Icon(Icons.space_dashboard),
                    label: Text("舒适"),
                  ),
                ],
                selected: {ref.watch(themeStyle)},
                onSelectionChanged: hasPluginTheme
                    ? null
                    : (value) {
                        ref.read(themeStyle.notifier).state = value.first;
                      },
              ),
            ),
          ],
        ),
        if (!hasPluginTheme)
          SettingsSection(
            title: "主题颜色",
            description: "保留 MD3 动态颜色，也可以选择固定种子色。",
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChoiceChip(
                      avatar: const Icon(Icons.auto_awesome),
                      label: const Text("跟随系统"),
                      selected: themeColorValue == null,
                      onSelected: (v) {
                        if (v) {
                          ref.read(themeColor.notifier).state = null;
                        } else {
                          ref.read(themeColor.notifier).state = Colors.teal;
                        }
                      },
                    ),
                    SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: context.effectiveRadius,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      margin: EdgeInsets.all(0),
                      child: ColorPicker(
                        color:
                            themeColorValue ??
                            Theme.of(context).colorScheme.primary,
                        onColorChanged: (color) =>
                            ref.read(themeColor.notifier).state = color,
                        pickersEnabled: const {
                          ColorPickerType.primary: true,
                          ColorPickerType.accent: true,
                          ColorPickerType.wheel: true,
                        },
                        enableShadesSelection: false,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        SettingsSection(
          title: "插件主题",
          description: "使用插件提供的主题配色方案。选中后将覆盖上方的主题风格和主题颜色设置。",
          children: [
            RadioGroup<String?>(
              groupValue: activePluginThemeIdValue,
              onChanged: (value) {
                ref.read(activePluginThemeId.notifier).state = value;
              },
              child: Column(
                children: [
                  RadioListTile<String?>(
                    title: Text("内置"),
                    subtitle: Text("使用系统动态色或自定义种子色"),
                    value: null,
                  ),
                  for (final theme in dataRegistry.allThemes)
                    RadioListTile<String?>(
                      title: Text(theme.name),
                      subtitle: Text(
                        [
                          'by ${theme.pluginId}',
                          if (theme.mode != null)
                            '· ${theme.mode == 'dark' ? '仅暗色' : '仅亮色'}',
                        ].join(' '),
                      ),
                      value: theme.id,
                    ),
                ],
              ),
            ),
          ],
        ),
        SettingsSection(
          title: "菜单样式",
          description: "控制桌面右键菜单的视觉样式。",
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.menu_open_outlined),
              title: const Text("Material Design 3 右键菜单"),
              subtitle: const Text("使用自绘菜单样式替代默认桌面菜单 fallback"),
              value: ref.watch(useMaterialContextMenu),
              onChanged: (value) {
                ref.read(useMaterialContextMenu.notifier).state = value;
              },
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text("外观与风格")),
      body: body,
    );
  }
}
