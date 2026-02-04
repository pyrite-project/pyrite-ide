import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/list_divider.dart';

class EditorSettings extends ConsumerWidget {
  const EditorSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text("编辑器设置"),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: Padding(
        padding: EdgeInsetsGeometry.only(left: 5, right: 5),
        child: ListView(
          children: [
            ListTile(
              title: Text("字体"),
              subtitle: Text(ref.watch(editorTextFontProvider)),
              onTap: () => showTextFontDialog(context, ref),
            ),
            ListTile(
              title: Text("字体大小"),
              subtitle: Text(ref.watch(editorFontSize).toString()),
              onTap: () => showFontSizeDialog(context, ref),
            ),
          ],
        ),
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
    final result = await showDialog(
      context: context,
      builder: (context) =>
          SimpleDialog(title: Text("选择编辑器字体"), children: children),
    );
  }

  void showFontSizeDialog(BuildContext context, WidgetRef ref) async {
    final List<SimpleDialogOption> children = [];
    double size = ref.watch(editorFontSize);
    final result = await showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text("选择编辑器字体"),
        children: [
          Slider(
            min: 5,
            max: 30,
            value: ref.watch(editorFontSize),
            onChanged: (value) {
              ref.read(editorFontSize.notifier).state = value;
              print(ref.watch(editorFontSize));
            },
          ),
        ],
      ),
    );
  }
}
