import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/settings.dart';

class LspSettings extends ConsumerWidget {
  const LspSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text("语言服务器设置"),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: Padding(
        padding: EdgeInsetsGeometry.only(left: 5, right: 5),
        child: ListView(
          children: [
            ListTile(
              title: Text("启用语言服务器"),
              subtitle: Text("更改将会在新标签页中生效"),
              trailing: Switch(
                value: ref.watch(useLsp),
                onChanged: (value) {
                  ref.read(useLsp.notifier).state = value;
                },
              ),
            ),
            ListTile(
              title: Text("WebSocket 地址"),
              subtitle: Text(ref.watch(lspWebScoketPath)),
              onTap: () => showPathDialog(context, ref),
            ),
            ListTile(
              title: Text("抑制警告"),
              subtitle: Text("更改将会在新标签页中生效，关闭后将不会有下划线标识警告"),
              trailing: Switch(
                value: ref.watch(disableWarning),
                onChanged: (value) {
                  ref.read(disableWarning.notifier).state = value;
                },
              ),
            ),
            ListTile(
              title: Text("抑制错误"),
              subtitle: Text("更改将会在新标签页中生效，关闭后将不会有下划线标识错误"),
              trailing: Switch(
                value: ref.watch(disableError),
                onChanged: (value) {
                  ref.read(disableError.notifier).state = value;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void showPathDialog(BuildContext context, WidgetRef ref) async {
    final TextEditingController controller = TextEditingController();
    controller.text = ref.read(lspWebScoketPath);
    await showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text("输入地址"),
        children: [
          SimpleDialogOption(child: TextField(controller: controller)),
          SimpleDialogOption(child: Text("请注意，若该地址不正确，服务器启动将会静默失败")),
          SimpleDialogOption(
            child: FilledButton(
              onPressed: () {
                ref.read(lspWebScoketPath.notifier).state = controller.text;
              },
              child: Text("确定"),
            ),
          ),
        ],
      ),
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
