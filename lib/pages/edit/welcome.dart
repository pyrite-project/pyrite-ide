import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Welcome extends ConsumerWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset("assets/icons/app_icon.png", width: 80, height: 80),
          SizedBox(height: 30),
          TextLogo(),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(label: Text("Debug")),
              SizedBox(width: 2),
              Badge(label: Text("MicroPython")),
              SizedBox(width: 2),
              Badge(label: Text("Cross-platform")),
              SizedBox(width: 2),
              Badge(label: Text("Modern")),
              SizedBox(width: 2),
              Badge(label: Text("Powerful")),
            ],
          ),
          SizedBox(height: 20),
          TextBodyMedium(
            "欢迎来到 PyriteIDE",
            color: Theme.of(context).colorScheme.secondary,
          ),
          TextBodyMedium(
            "若已打开项目，请前往“文件”打开一个项目中的文件",
            color: Theme.of(context).colorScheme.secondary,
          ),
          SizedBox(height: 20),
          SizedBox(
            width: 500,
            child: GridView(
              shrinkWrap: true,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                mainAxisSpacing: 5,
                crossAxisSpacing: 5,
                maxCrossAxisExtent: 200,
                childAspectRatio: 3.5,
              ),
              children: [
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: Icon(Icons.add),
                  label: Text("新建项目"),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await getDirectory(ref);
                    ref.watch(treeItems.notifier).state =
                        await buildFileListItems(ref, await getFilesList(ref));
                  },
                  icon: Icon(Icons.folder_outlined),
                  label: Text("打开项目"),
                ),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: Icon(Icons.add),
                  label: Text("打开终端"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
