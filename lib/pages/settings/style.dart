import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';

class StyleSettings extends ConsumerWidget {
  const StyleSettings({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = ListView(
      padding: EdgeInsets.all(compact ? 12 : 16),
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
          title: "主题颜色",
          description: "保留 MD3 动态颜色，也可以选择固定种子色。",
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.auto_awesome),
                    label: const Text("跟随系统"),
                    selected: ref.watch(themeColor) == null,
                    onSelected: (value) =>
                        ref.read(themeColor.notifier).state = null,
                  ),
                  buildColorChoice(ref, label: "火焰橙", color: Colors.deepOrange),
                  buildColorChoice(ref, label: "掌控蓝", color: Colors.blue),
                  buildColorChoice(ref, label: "松石绿", color: Colors.teal),
                ],
              ),
            ),
          ],
        ),
      ],
    );

    if (compact) {
      return Column(
        children: [
          const PaneHeader(
            title: "外观与风格",
            subtitle: "主题模式和 MD3 种子色",
            leadingIcon: Icons.color_lens_outlined,
            compact: true,
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("外观与风格")),
      body: body,
    );
  }

  Widget buildColorChoice(
    WidgetRef ref, {
    required String label,
    required Color color,
  }) {
    return ChoiceChip(
      avatar: CircleAvatar(backgroundColor: color, radius: 8),
      label: Text(label),
      selected: ref.watch(themeColor)?.toARGB32() == color.toARGB32(),
      onSelected: (value) => ref.read(themeColor.notifier).state = color,
    );
  }
}
