import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';

class EditorSettings extends ConsumerWidget {
  const EditorSettings({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = ListView(
      padding: EdgeInsets.all(compact ? 12 : 16),
      children: [
        SettingsSection(
          title: "字体",
          description: "影响代码编辑区域的阅读和输入体验。",
          children: [
            ListTile(
              title: const Text("字体"),
              subtitle: Text(ref.watch(editorTextFontProvider)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showTextFontDialog(context, ref),
            ),
            const SectionDivider(),
            ListTile(
              title: const Text("字体大小"),
              subtitle: Text(
                "${ref.watch(editorFontSize).toStringAsFixed(0)} px",
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showFontSizeDialog(context),
            ),
          ],
        ),
        SettingsSection(
          title: "编辑行为",
          children: [
            SwitchListTile(
              title: const Text("自动折行"),
              subtitle: const Text("长行在可视区域内换行显示"),
              value: ref.watch(editorWordWrap),
              onChanged: (value) {
                ref.read(editorWordWrap.notifier).state = value;
              },
            ),
            const SectionDivider(),
            const ListTile(
              leading: Icon(Icons.format_list_numbered),
              title: Text("显示行号"),
              subtitle: Text("当前编辑器内核默认显示，暂未开放独立开关"),
              trailing: PillBadge(label: "内核默认"),
            ),
          ],
        ),
      ],
    );

    if (compact) {
      return Column(
        children: [
          const PaneHeader(
            title: "编辑器设置",
            subtitle: "字体和编辑行为",
            leadingIcon: Icons.edit_outlined,
            compact: true,
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("编辑器设置")),
      body: body,
    );
  }

  void showTextFontDialog(BuildContext context, WidgetRef ref) async {
    final List<SimpleDialogOption> children = [];
    editorTextFonts.forEach((name, value) {
      final selected = ref.read(editorTextFontProvider) == name;
      children.add(
        SimpleDialogOption(
          child: ListTile(
            title: Text(name),
            subtitle: Text(
              "print('Pyrite IDE')",
              style: TextStyle(fontFamily: value.isEmpty ? null : value),
            ),
            trailing: selected ? const Icon(Icons.check) : null,
            minTileHeight: 0,
            onTap: (name == "自定义")
                ? () {
                    customizationEditorTextFont();
                    context.pop(name);
                  }
                : () {
                    ref.read(editorTextFontProvider.notifier).state = name;
                    context.pop(name);
                  },
          ),
        ),
      );
    });
    await showDialog(
      context: context,
      builder: (context) =>
          SimpleDialog(title: const Text("选择编辑器字体"), children: children),
    );
  }

  void showFontSizeDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final size = ref.watch(editorFontSize);
          return SimpleDialog(
            title: const Text("字体大小"),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 12),
                child: Text(
                  "print('Pyrite IDE')",
                  style: TextStyle(
                    fontFamily:
                        editorTextFonts[ref.watch(editorTextFontProvider)],
                    fontSize: size,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Slider(
                  min: 10,
                  max: 28,
                  divisions: 18,
                  value: size,
                  label: size.toStringAsFixed(0),
                  onChanged: (value) =>
                      ref.read(editorFontSize.notifier).state = value,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
