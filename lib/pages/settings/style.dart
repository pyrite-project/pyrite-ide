import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class StyleSettings extends ConsumerWidget {
  const StyleSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text("外观与风格"),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: Padding(
        padding: EdgeInsetsGeometry.only(left: 15, right: 15),
        child: ListView(
          children: [
            UseText("主题模式"),
            SizedBox(height: 10),
            Row(
              spacing: 5,
              children: [
                ChoiceChip(
                  avatar: Icon(Icons.auto_mode),
                  label: Text("自动"),
                  selected: ref.watch(themeMode) == ThemeMode.system,
                  onSelected: (value) {
                    ref.read(themeMode.notifier).state = ThemeMode.system;
                  },
                ),
                ChoiceChip(
                  avatar: Icon(Icons.light_mode),
                  label: Text("日光"),
                  selected: ref.watch(themeMode) == ThemeMode.light,
                  onSelected: (value) {
                    ref.read(themeMode.notifier).state = ThemeMode.light;
                  },
                ),
                ChoiceChip(
                  avatar: Icon(Icons.dark_mode),
                  label: Text("黑夜"),
                  selected: ref.watch(themeMode) == ThemeMode.dark,
                  onSelected: (value) {
                    ref.read(themeMode.notifier).state = ThemeMode.dark;
                  },
                ),
              ],
            ),
            SizedBox(height: 20),
            UseText("主题颜色"),
            SizedBox(height: 10),
            GridView(
              shrinkWrap: true,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                mainAxisSpacing: 5,
                crossAxisSpacing: 5,
                maxCrossAxisExtent: 100,
                childAspectRatio: 2,
              ),
              children: [
                ChoiceChip(
                  label: Text("跟随系统"),
                  selected: ref.watch(themeColor) == null,
                  onSelected: (value) =>
                      ref.read(themeColor.notifier).state = null,
                ),
                ChoiceChip(
                  label: Text("火焰橙"),
                  selected: ref.watch(themeColor)?.toARGB32() == Colors.deepOrange.toARGB32(),
                  onSelected: (value) =>
                      ref.read(themeColor.notifier).state = Colors.deepOrange,
                ),
                ChoiceChip(
                  label: Text("掌控蓝"),
                  selected: ref.watch(themeColor)?.toARGB32() == Colors.blue.toARGB32(),
                  onSelected: (value) =>
                      ref.read(themeColor.notifier).state = Colors.blue,
                ),
              ],
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
                min: 5,
                max: 50,
                divisions: 45,
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
