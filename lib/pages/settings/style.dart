import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';

class StyleSettings extends ConsumerWidget {
  const StyleSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeColorValue = ref.watch(themeColor);
    final body = ListView(
      padding: EdgeInsets.all(12),
      children: [
        SettingsSection(
          title: "主题模式",
          description: "决定界面跟随系统、常亮或常暗。",
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
                onSelectionChanged: (value) {
                  ref.read(themeMode.notifier).state = value.first;
                },
              ),
            ),
          ],
        ),
        SettingsSection(
          title: "主题风格",
          description: "切换不同风格的组件样式与布局密度。",
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
                onSelectionChanged: (value) {
                  ref.read(themeStyle.notifier).state = value.first;
                },
              ),
            ),
          ],
        ),
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
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text("外观与风格")),
      body: body,
    );
  }
}
