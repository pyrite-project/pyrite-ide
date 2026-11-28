import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_layout_commands.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_tree.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/features/command_palette/command_palette.dart';
import 'package:pyrite_ide/features/command_palette/editor_palette_hooks.dart';
import 'package:pyrite_ide/features/command_palette/palette_entry.dart';
import 'package:pyrite_ide/features/function_page/console_tabs.dart';

class MacOSMenu extends ConsumerWidget {
  const MacOSMenu({super.key, required this.app});

  final MaterialApp app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformMenuBar(menus: _build(context, ref), child: app);
  }

  List<PlatformMenuItem> _build(BuildContext context, WidgetRef ref) {
    String t(I18nKey key) => translateForWidget(ref, key);

    // The menu bar sits above the MaterialApp, so its own context cannot push
    // a route; dialogs go through the root navigator instead.
    void openPalette(PaletteLaunchMode mode) {
      final paletteContext = appContext;
      if (paletteContext == null) return;
      unawaited(
        showCommandPalette(
          paletteContext,
          mode: mode,
          hooks: editorPaletteHooks(),
        ),
      );
    }

    void runEditor(Future<void> Function(BuildContext context) action) {
      final editorContext = appContext;
      if (editorContext == null) return;
      unawaited(action(editorContext));
    }

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
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: t(I18nKey.menuReopenClosedTab),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyT,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => runEditor(
                  (editor) async => await reopenClosedEditorTab(editor, ref),
                ),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: t(I18nKey.menuCommandPalette),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyP,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => openPalette(PaletteLaunchMode.commands),
              ),
              PlatformMenuItem(
                label: t(I18nKey.menuQuickOpen),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyP,
                  meta: true,
                ),
                onSelected: () => openPalette(PaletteLaunchMode.files),
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
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: t(I18nKey.menuToggleFunctionPanel),
                onSelected: () => ref.read(functionPageShow.notifier).state =
                    !ref.read(functionPageShow),
              ),
              PlatformMenuItem(
                label: t(I18nKey.menuToggleConsolePanel),
                onSelected: () => ref.read(consolePageShow.notifier).state =
                    !ref.read(consolePageShow),
              ),
              PlatformMenuItem(
                label: t(I18nKey.consoleResetLayout),
                onSelected: () =>
                    resetTerminalLayout(ProviderScope.containerOf(context)),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: t(I18nKey.menuSplitRight),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.backslash,
                  meta: true,
                ),
                onSelected: () => splitActiveEditor(ref, PaneEdge.right),
              ),
              PlatformMenuItem(
                label: t(I18nKey.menuSplitDown),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.backslash,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => splitActiveEditor(ref, PaneEdge.bottom),
              ),
              PlatformMenuItem(
                label: t(I18nKey.menuCloseGroup),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyW,
                  meta: true,
                  alt: true,
                ),
                onSelected: () => runEditor(
                  (editor) async => await closeActiveEditorGroup(editor, ref),
                ),
              ),
              PlatformMenuItem(
                label: t(I18nKey.menuResetEditorLayout),
                onSelected: () => resetEditorLayout(ref),
              ),
            ],
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
