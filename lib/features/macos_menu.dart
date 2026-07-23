import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';

class MacOSMenu extends ConsumerWidget {
  const MacOSMenu({super.key, required this.app});

  final MaterialApp app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformMenuBar(menus: _build(context, ref), child: app);
  }

  List<PlatformMenuItem> _build(BuildContext context, WidgetRef ref) {
    String t(I18nKey key) => translateForWidget(ref, key);
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
        label: t(I18nKey.menuFile),
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: t(I18nKey.menuNewFile),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyN,
                  meta: true,
                ),
                onSelected: () => ref
                    .read(tabbedViewControllerProvider.notifier)
                    .createFile(),
              ),
              PlatformMenuItem(
                label: t(I18nKey.menuOpenFile),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyO,
                  meta: true,
                ),
                onSelected: () => ref
                    .read(tabbedViewControllerProvider.notifier)
                    .openFile(context),
              ),
              PlatformMenuItem(
                label: t(I18nKey.menuOpenFolder),
                onSelected: () =>
                    ref.read(localFileItemsProvider.notifier).openFolder(),
              ),
              PlatformMenuItem(
                label: t(I18nKey.menuSaveCurrentFile),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyS,
                  meta: true,
                ),
                onSelected: () =>
                    ref.read(fileProvider.notifier).saveCurrentFile(),
              ),
              PlatformMenuItem(
                label: t(I18nKey.menuSaveAs),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyS,
                  meta: true,
                  shift: true,
                ),
                onSelected: () =>
                    ref.read(fileProvider.notifier).saveCurrentFileAs(),
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: t(I18nKey.menuEdit),
        menus: [
          PlatformMenuItem(
            label: t(I18nKey.menuCut),
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyX,
              meta: true,
            ),
            onSelected: ref.read(editorControllerMapProvider.notifier).cut,
          ),
          PlatformMenuItem(
            label: t(I18nKey.menuCopy),
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyC,
              meta: true,
            ),
            onSelected: ref.read(editorControllerMapProvider.notifier).copy,
          ),
          PlatformMenuItem(
            label: t(I18nKey.menuPaste),
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyV,
              meta: true,
            ),
            onSelected: ref.read(editorControllerMapProvider.notifier).paste,
          ),
        ],
      ),
      PlatformMenu(
        label: t(I18nKey.menuView),
        menus: [
          PlatformMenuItem(
            label: t(I18nKey.menuToggleFunctionPanel),
            onSelected: () => ref.read(functionPageShow.notifier).state = !ref
                .read(functionPageShow),
          ),
          PlatformMenuItem(
            label: t(I18nKey.menuToggleConsolePanel),
            onSelected: () => ref.read(consolePageShow.notifier).state = !ref
                .read(consolePageShow),
          ),
          PlatformMenuItem(
            label: t(I18nKey.menuToggleExpansionPanel),
            onSelected: () => ref.read(expansionPageShow.notifier).state = !ref
                .read(expansionPageShow),
          ),
        ],
      ),
      PlatformMenu(
        label: t(I18nKey.menuWindow),
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
