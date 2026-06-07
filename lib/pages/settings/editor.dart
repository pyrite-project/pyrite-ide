import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';

class EditorSettings extends ConsumerWidget {
  const EditorSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text("编辑器设置")),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
              SwitchListTile(
                title: const Text("显示行号"),
                subtitle: const Text("在编辑器左侧显示行号"),
                value: ref.watch(editorLineNumber),
                onChanged: (value) {
                  ref.read(editorLineNumber.notifier).state = value;
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void showTextFontDialog(BuildContext context, WidgetRef ref) async {
    final List<SimpleDialogOption> children = [];
    editorTextFonts.forEach((name, value) {
      children.add(
        SimpleDialogOption(
          child: Column(
            children: [
              ListTile(
                title: Text(name),
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
              Divider(),
            ],
          ),
        ),
      );
    });
    await showDialog(
      context: context,
      builder: (context) =>
          SimpleDialog(title: Text("选择编辑器字体"), children: children),
    );
  }

  void showFontSizeDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final size = ref.watch(editorFontSize);
          return SimpleDialog(
            title: Text("字体大小"),
            children: [
              Slider(
                min: 10,
                max: 28,
                divisions: 18,
                value: size,
                label: size.toStringAsFixed(0),
                onChanged: (value) =>
                    ref.read(editorFontSize.notifier).state = value,
              ),
            ],
          );
        },
      ),
    );
  }
}
