import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/window.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_workspace_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
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
    final double leftPadding = Platform.isMacOS ? 80 : 22;
    final double appIconSize = Platform.isMacOS ? 14 : 28;
    return GestureDetector(
      onPanStart: (details) => windowManager.startDragging(),
      child: Container(
        padding: EdgeInsets.only(left: leftPadding, right: 8),
        color: Theme.of(context).colorScheme.surface,
        height: titleBarHeight,
        child: Row(
          children: [
            Image.asset(
              "assets/icons/app_icon_appbar.png",
              color: Theme.of(context).colorScheme.onSurface,
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
            buildMenuItemButton(
              context,
              "新建文件",
              () =>
                  ref.read(tabbedViewControllerProvider.notifier).createFile(),
              leadingIconData: Icons.add,
            ),
            buildMenuItemButton(
              context,
              "打开文件",
              () => ref
                  .read(tabbedViewControllerProvider.notifier)
                  .openFile(context),
              leadingIconData: Icons.open_in_browser,
            ),
            buildMenuItemButton(
              context,
              "打开文件夹",
              () => ref.read(localFileItemsProvider.notifier).openFolder(),
              leadingIconData: Icons.folder_open,
            ),
            PopupMenuDivider(),
            buildMenuItemButton(
              context,
              "保存当前文件",
              () => ref.read(localWorkspaceProvider.notifier).saveFile(),
              leadingIconData: Icons.save,
            ),
            buildMenuItemButton(
              context,
              "将当前文件另存为",
              () => ref.read(localWorkspaceProvider.notifier).saveAs(),
              leadingIconData: Icons.save_as,
            ),
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
          menuChildren: [
            buildMenuItemButton(
              context,
              "撤销",
              null,
              leadingIconData: Icons.undo,
              shortcut: SingleActivator(LogicalKeyboardKey.keyZ, control: true),
            ),
            buildMenuItemButton(
              context,
              "恢复",
              null,
              leadingIconData: Icons.redo,
              shortcut: SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: true,
                shift: true,
              ),
            ),
            PopupMenuDivider(),
            buildMenuItemButton(
              context,
              "剪切",
              ref.read(editorControllerMapProvider.notifier).cut,
              leadingIconData: Icons.cut,
              shortcut: SingleActivator(LogicalKeyboardKey.keyX, control: true),
            ),
            buildMenuItemButton(
              context,
              "复制",
              ref.read(editorControllerMapProvider.notifier).copy,
              leadingIconData: Icons.copy,
              shortcut: SingleActivator(LogicalKeyboardKey.keyC, control: true),
            ),
            buildMenuItemButton(
              context,
              "粘贴",
              ref.read(editorControllerMapProvider.notifier).paste,
              leadingIconData: Icons.paste,
              shortcut: SingleActivator(LogicalKeyboardKey.keyV, control: true),
            ),
          ],
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
          menuChildren: [
            MenuItemButton(
              onPressed: () {},
              leadingIcon: Icon(Icons.functions),
              trailingIcon: Checkbox(
                value: ref.watch(functionPageShow),
                onChanged: (value) =>
                    ref.read(functionPageShow.notifier).state = !ref.read(
                      functionPageShow,
                    ),
              ),
              child: Text("功能"),
            ),
            MenuItemButton(
              onPressed: () {},
              leadingIcon: Icon(Icons.control_camera),
              trailingIcon: Checkbox(
                value: ref.watch(consolePageShow),
                onChanged: (value) => ref.read(consolePageShow.notifier).state =
                    !ref.read(consolePageShow),
              ),
              child: Text("控制台"),
            ),
            MenuItemButton(
              onPressed: () {},
              leadingIcon: Icon(Icons.expand),
              trailingIcon: Checkbox(
                value: ref.watch(expansionPageShow),
                onChanged: (value) =>
                    ref.read(expansionPageShow.notifier).state = !ref.read(
                      expansionPageShow,
                    ),
              ),
              child: Text("拓展"),
            ),
          ],
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
    SingleActivator? shortcut,
    Widget? trailing,
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
      shortcut: shortcut,
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
          hoverColor: Theme.of(
            context,
          ).colorScheme.error.withValues(alpha: 0.3),
          icon: Icon(Icons.close, size: 20),
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }
}
