import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/services/editor.dart';
import 'package:pyrite_ide/core/services/file.dart';

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
                label: '新建文件…',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyN,
                  meta: true,
                ),
                onSelected: () {
                  unawaited(_newFile(ref));
                },
              ),
              PlatformMenuItem(
                label: '打开文件…',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyO,
                  meta: true,
                ),
                onSelected: () {
                  unawaited(_openFile(ref));
                },
              ),
              PlatformMenuItem(
                label: '打开文件夹…',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyO,
                  meta: true,
                  shift: true,
                ),
                onSelected: () {
                  unawaited(_openFolder(ref));
                },
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: '视图',
        menus: const [
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.toggleFullScreen,
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

  Future<void> _newFile(WidgetRef ref) async {
    final file = await createFile();
    if (file == null) return;

    final controller = await createNewEditorController(file, ref);
    final tab = await createNewFileTab(file, ref, controller);
    ref.read(tabbedViewController).addTab(tab);
    ref.read(tabbedViewController).selectTab(tab);
  }

  Future<void> _openFile(WidgetRef ref) async {
    final file = await getFile();
    if (file == null) return;

    final controller = await createNewEditorController(file, ref);
    final tab = await createNewFileTab(file, ref, controller);
    ref.read(tabbedViewController).addTab(tab);
    ref.read(tabbedViewController).selectTab(tab);
  }

  Future<void> _openFolder(WidgetRef ref) async {
    await getDirectory(ref);
    ref.read(treeItems.notifier).state = await buildFileListItems(
      ref,
      await getFilesList(ref),
    );
  }
}
