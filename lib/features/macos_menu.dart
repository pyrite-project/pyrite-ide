import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/services/editor/ui.dart';
import 'package:pyrite_ide/core/services/file/ui.dart';
import 'package:pyrite_ide/core/services/function_page.dart';

class MacOSMenu extends ConsumerWidget {
  const MacOSMenu({super.key, required this.app});

  final MaterialApp app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformMenuBar(menus: _build(ref), child: app);
  }

  List<PlatformMenuItem> _build(WidgetRef ref) {
    return [
      PlatformMenu(
        label: appName,
        menus: const [
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.servicesSubmenu,
          ),
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.hideOtherApplications,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.showAllApplications,
          ),
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
        ],
      ),
      PlatformMenu(
        label: '文件',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: '新建文件',
                onSelected: () => createFileAction(ref),
              ),
              PlatformMenuItem(
                label: '打开文件',
                onSelected: () => openFileAction(ref),
              ),
              PlatformMenuItem(
                label: '打开文件夹',
                onSelected: () => openFolderAction(ref),
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: '编辑',
        menus: [
          PlatformMenuItem(
            label: "撤销",
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyZ,
              control: true,
            ),
            onSelected: () => undoAction(ref),
          ),
          PlatformMenuItem(
            label: "恢复",
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyZ,
              control: true,
              shift: true,
            ),
            onSelected: () => redoAction(ref),
          ),
          PlatformMenuItem(
            label: "剪切",
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyX,
              control: true,
            ),
            onSelected: () => cutAction(ref),
          ),
          PlatformMenuItem(
            label: "复制",
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyC,
              control: true,
            ),
            onSelected: () => copyAction(ref),
          ),
          PlatformMenuItem(
            label: "粘贴",
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyV,
              control: true,
            ),
            onSelected: () => pasteAction(ref),
          ),
          PlatformMenuItem(
            label: "光标移动至行首",
            onSelected: () => moveCursorToLineStartAction(ref),
          ),
          PlatformMenuItem(
            label: "光标移动至行尾",
            onSelected: () => moveCursorToLineEndAction(ref),
          ),
          PlatformMenuItem(
            label: "光标移动至开头",
            onSelected: () => moveCursorToPageStartAction(ref),
          ),
          PlatformMenuItem(
            label: "光标移动至结尾",
            onSelected: () => moveCursorToPageEndAction(ref),
          ),
        ],
      ),
      PlatformMenu(
        label: '视图',
        menus: [
          PlatformMenuItem(
            label: "切换“功能”开启状态",
            onSelected: () => ref.read(functionPageShow.notifier).state = !ref
                .read(functionPageShow),
          ),
          PlatformMenuItem(
            label: "切换“控制台”开启状态",
            onSelected: () => ref.read(consolePageShow.notifier).state = !ref
                .read(consolePageShow),
          ),
          PlatformMenuItem(
            label: "切换“拓展”开启状态",
            onSelected: () => ref.read(expansionPageShow.notifier).state = !ref
                .read(expansionPageShow),
          ),
        ],
      ),
      PlatformMenu(
        label: '窗口',
        menus: const [
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.minimizeWindow,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.zoomWindow,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
          ),
        ],
      ),
    ];
  }
}
