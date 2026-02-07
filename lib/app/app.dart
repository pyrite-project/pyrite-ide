import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor.dart';
import 'package:pyrite_ide/core/services/file.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:pyrite_ide/tool_ds/tool_ds.dart';

class PyriteIDE extends ConsumerWidget {
  const PyriteIDE({super.key});

  List<PlatformMenuItem> _buildMacosMenus(WidgetRef ref) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(lspClientProvider);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final app = MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: appName,
          themeMode: ref.watch(themeMode),
          theme: ThemeData(
            fontFamily: "HarmonyOS Sans SC",
            brightness: Brightness.light,
            colorScheme: (ref.watch(themeColor) == null)
                ? lightDynamic
                : ColorScheme.fromSeed(seedColor: ref.read(themeColor)!),
            appBarTheme: AppBarTheme(surfaceTintColor: Colors.transparent),
          ),
          darkTheme: ThemeData(
            fontFamily: "HarmonyOS Sans SC",
            brightness: Brightness.dark,
            colorScheme: (ref.watch(themeColor) == null)
                ? darkDynamic
                : ColorScheme.fromSeed(
                    seedColor: ref.read(themeColor)!,
                    brightness: Brightness.dark,
                  ),
            appBarTheme: AppBarTheme(surfaceTintColor: Colors.transparent),
          ),
          routerConfig: routes,
          builder: (context, child) => ToolScope(
            uiFontFamily: "HarmonyOS Sans SC",
            monoFontFamily: "JetBrainsMono",
            child: MaterialScope(
              child: ResponsiveBreakpoints.builder(
                child: child!,
                breakpoints: [
                  const Breakpoint(start: 0, end: 600, name: MOBILE),
                  const Breakpoint(start: 601, end: 1000, name: TABLET),
                  const Breakpoint(
                    start: 801,
                    end: double.infinity,
                    name: DESKTOP,
                  ),
                ],
              ),
            ),
          ),
        );

        if (!Platform.isMacOS) return app;
        return PlatformMenuBar(menus: _buildMacosMenus(ref), child: app);
      },
    );
  }
}
