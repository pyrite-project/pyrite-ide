import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/window.dart';
import 'package:pyrite_ide/core/services/edit.dart';
import 'package:pyrite_ide/core/services/file.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:window_manager/window_manager.dart';

class UseWindow {
  void init() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      WidgetsFlutterBinding.ensureInitialized();
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }
  }
}

class UseTitleBar extends StatelessWidget {
  const UseTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final double titleBarHeight = Platform.isMacOS ? 36 : 45;
    final double leftPadding = Platform.isMacOS ? 80 : 18;
    final double appIconSize = Platform.isMacOS ? 14 : 25;
    return GestureDetector(
      onPanStart: (details) => windowManager.startDragging(),
      child: Container(
        padding: EdgeInsets.only(left: leftPadding, right: 8),
        color: Theme.of(context).colorScheme.surface,
        height: titleBarHeight,
        child: Row(
          children: [
            Image.asset(
              "assets/icons/app_icon.png",
              width: appIconSize,
              height: appIconSize,
            ),
            SizedBox(width: 20),
            if (!Platform.isMacOS) AppActionBar(),
            Expanded(child: Platform.isMacOS ? SizedBox() : WindowActionBar()),
          ],
        ),
      ),
    );
  }
}

class AppActionBar extends ConsumerWidget {
  const AppActionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MenuBar(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(
          Theme.of(context).colorScheme.surface,
        ),
        elevation: WidgetStateProperty.all(0),
      ),
      children: [
        SubmenuButton(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surface,
            ),
            overlayColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surface,
            ),
          ),
          alignmentOffset: Offset(0, 5),
          menuStyle: MenuStyle(
            minimumSize: WidgetStatePropertyAll(Size(180, 0)),
          ),
          menuChildren: [
            buildMenuItemButton(context, "新建文件", () async {
              final file = await createFile();
              if (file != null) {
                final TabData newTab = await createNewFileTab(
                  file,
                  ref,
                  await createNewEditorController(file, ref),
                );
                ref.read(tabbedViewController).addTab(newTab);
                ref.read(tabbedViewController).selectTab(newTab);
              }
            }, leadingIconData: Icons.add),
            buildMenuItemButton(
              context,
              "新建窗口（暂不支持）",
              null,
              leadingIconData: Icons.window_sharp,
            ),
            PopupMenuDivider(),
            buildMenuItemButton(context, "打开文件", () async {
              File? file = await getFile();
              if (file != null) {
                final TabData newTab = await createNewFileTab(
                  file,
                  ref,
                  await createNewEditorController(file, ref),
                );
                ref.read(tabbedViewController).addTab(newTab);
                ref.read(tabbedViewController).selectTab(newTab);
              }
            }, leadingIconData: Icons.open_in_browser),
            buildMenuItemButton(context, "打开文件夹", () async {
              await getDirectory(ref);
              ref.watch(treeItems.notifier).state = await buildFileListItems(
                ref,
                await getFilesList(ref),
              );
            }, leadingIconData: Icons.folder_open),
            buildMenuItemButton(
              context,
              "打开最近的文件或文件夹",
              () {},
              trailingIconData: Icons.chevron_right,
            ),
            PopupMenuDivider(),
            buildMenuItemButton(
              context,
              "保存当前文件",
              () {},
              leadingIconData: Icons.save,
            ),
            buildMenuItemButton(context, "保存所有", () {}),
            buildMenuItemButton(
              context,
              "将当前文件另存为",
              () {},
              leadingIconData: Icons.save_as,
            ),
            PopupMenuDivider(),
            buildMenuItemButton(
              context,
              "关闭当前文件",
              () {},
              leadingIconData: Icons.close,
            ),
            buildMenuItemButton(context, "关闭所有文件", () {}),
          ],
          child: Text("文件"),
        ),
        SubmenuButton(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surface,
            ),
            overlayColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surface,
            ),
          ),
          alignmentOffset: Offset(0, 5),
          menuChildren: [buildMenuItemButton(context, "data", () {})],
          child: Text("编辑"),
        ),
        SubmenuButton(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surface,
            ),
            overlayColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surface,
            ),
          ),
          alignmentOffset: Offset(0, 5),
          menuChildren: [],
          child: Text("视图"),
        ),
      ],
    );
  }

  Widget buildMenuItemButton(
    BuildContext context,
    String text,
    Function()? onPressed, {
    IconData? leadingIconData,
    IconData? trailingIconData,
  }) {
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: (leadingIconData != null)
          ? Icon(leadingIconData, size: 18)
          : SizedBox(width: 18),
      trailingIcon: (trailingIconData != null)
          ? Icon(trailingIconData, size: 18)
          : SizedBox(width: 18),
      style: ButtonStyle(),
      child: Text(text),
    );
  }
}

class WindowActionBar extends StatelessWidget {
  const WindowActionBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          icon: Icon(Icons.minimize, size: 18),
          onPressed: () => windowManager.minimize(),
        ),
        FutureBuilder<bool>(
          future: windowManager.isMaximized(),
          builder: (context, snapshot) {
            return IconButton(
              icon: Icon(
                snapshot.data == true ? Icons.filter_none : Icons.crop_square,
                size: 20,
              ),
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            );
          },
        ),
        IconButton(
          hoverColor: Theme.of(context).colorScheme.error.withOpacity(0.3),
          icon: Icon(Icons.close, size: 20),
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }
}
