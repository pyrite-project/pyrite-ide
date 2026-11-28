import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_tree.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/search/project_file_index.dart';
import 'package:pyrite_ide/features/command_palette/palette_entry.dart';
import 'package:pyrite_ide/shared/tabbed_view/unsaved_tab_guard.dart';
import 'package:responsive_framework/responsive_framework.dart';

/// Editor actions the palette cannot implement by itself yet.
///
/// The editor commands (reopen the last closed tab, close an editor group,
/// reset the editor layout) live in the editor feature; the Lead wires them
/// into the palette by passing callbacks here. An entry whose hook is null is
/// left out (reopen) or shown disabled (close group, reset layout).
@immutable
class CommandPaletteHooks {
  const CommandPaletteHooks({
    this.reopenLastClosedTab,
    this.closeEditorGroup,
    this.resetEditorLayout,
  });

  final PaletteExecuteCallback? reopenLastClosedTab;
  final PaletteExecuteCallback? closeEditorGroup;
  final PaletteExecuteCallback? resetEditorLayout;
}

/// The palette's built-in file, view, navigation and settings entries.
///
/// Titles are translated with [translateForWidget] at build time; the actions
/// read the same providers the toolbar and menus use, so the palette cannot
/// drift from them.
List<PaletteEntry> buildBuiltinPaletteEntries(
  BuildContext context,
  WidgetRef ref, {
  CommandPaletteHooks hooks = const CommandPaletteHooks(),
}) {
  String tr(I18nKey key) => translateForWidget(ref, key);

  final group = ref.watch(activeEditorControllerProvider);
  final layout = ref.watch(editorLayoutProvider);
  final selectedTab = group.selectedTab;
  final canSplit =
      selectedTab != null &&
      canTabLeaveGroup(selectedTab) &&
      group.tabs.length >= 2;
  final canCloseTab = selectedTab != null && selectedTab.closable;

  Future<void> closeTab(BuildContext context, WidgetRef ref) async {
    final active = ref.read(activeEditorControllerProvider);
    final tab = active.selectedTab;
    if (tab == null || !tab.closable) return;
    if (!await confirmCloseUnsavedTab(context, tab)) return;
    if (!context.mounted) return;
    final index = active.tabs.indexOf(tab);
    if (index < 0) return;
    active.removeTab(index);
    await ref.read(tabbedViewControllerProvider.notifier).afterTabClose(tab);
  }

  PaletteExecuteCallback splitEditor(PaneEdge where) => (context, ref) async {
    final active = ref.read(activeEditorControllerProvider);
    final tab = active.selectedTab;
    if (tab == null) return;
    ref
        .read(editorLayoutProvider.notifier)
        .splitGroup(from: active, target: active, tab: tab, where: where);
  };

  final entries = <PaletteEntry>[
    // File commands.
    PaletteEntry(
      id: 'builtin.file.new',
      title: tr(I18nKey.menuNewFile),
      category: PaletteCategory.command,
      icon: Icons.note_add_outlined,
      onSelect: (context, ref) async {
        ref.read(tabbedViewControllerProvider.notifier).createFile();
      },
    ),
    PaletteEntry(
      id: 'builtin.file.open',
      title: tr(I18nKey.menuOpenFile),
      category: PaletteCategory.command,
      icon: Icons.file_open_outlined,
      onSelect: (context, ref) async {
        await ref.read(tabbedViewControllerProvider.notifier).openFile(context);
      },
    ),
    PaletteEntry(
      id: 'builtin.file.open_folder',
      title: tr(I18nKey.menuOpenFolder),
      category: PaletteCategory.command,
      icon: Icons.folder_open_outlined,
      onSelect: (context, ref) async {
        ref.read(localFileItemsProvider.notifier).openFolder();
      },
    ),
    PaletteEntry(
      id: 'builtin.file.save',
      title: tr(I18nKey.menuSaveCurrentFile),
      category: PaletteCategory.command,
      icon: Icons.save_outlined,
      onSelect: (context, ref) async {
        await ref.read(fileProvider.notifier).saveCurrentFile();
      },
    ),
    PaletteEntry(
      id: 'builtin.file.save_as',
      title: tr(I18nKey.menuSaveCurrentFileAs),
      category: PaletteCategory.command,
      icon: Icons.save_as_outlined,
      onSelect: (context, ref) async {
        ref.read(fileProvider.notifier).saveCurrentFileAs();
      },
    ),
    PaletteEntry(
      id: 'builtin.file.close_tab',
      title: tr(I18nKey.tabContextMenuClose),
      category: PaletteCategory.command,
      icon: Icons.close,
      enabled: canCloseTab,
      onSelect: closeTab,
    ),
    if (hooks.reopenLastClosedTab != null)
      PaletteEntry(
        id: 'builtin.file.reopen_tab',
        title: tr(I18nKey.menuReopenClosedTab),
        category: PaletteCategory.command,
        icon: Icons.restore_outlined,
        onSelect: hooks.reopenLastClosedTab,
      ),

    // View commands.
    PaletteEntry(
      id: 'builtin.view.function_panel',
      title: tr(I18nKey.menuToggleFunctionPanel),
      category: PaletteCategory.command,
      icon: Icons.view_sidebar_outlined,
      onSelect: (context, ref) async {
        ref.read(functionPageShow.notifier).state = !ref.read(functionPageShow);
      },
    ),
    PaletteEntry(
      id: 'builtin.view.console_panel',
      title: tr(I18nKey.menuToggleConsolePanel),
      category: PaletteCategory.command,
      icon: Icons.terminal_outlined,
      onSelect: (context, ref) async {
        ref.read(consolePageShow.notifier).state = !ref.read(consolePageShow);
      },
    ),
    PaletteEntry(
      id: 'builtin.view.split_right',
      title: tr(I18nKey.menuSplitRight),
      category: PaletteCategory.command,
      icon: Icons.vertical_split_outlined,
      enabled: canSplit,
      onSelect: splitEditor(PaneEdge.right),
    ),
    PaletteEntry(
      id: 'builtin.view.split_down',
      title: tr(I18nKey.menuSplitDown),
      category: PaletteCategory.command,
      icon: Icons.horizontal_split_outlined,
      enabled: canSplit,
      onSelect: splitEditor(PaneEdge.bottom),
    ),
    PaletteEntry(
      id: 'builtin.view.close_group',
      title: tr(I18nKey.menuCloseGroup),
      category: PaletteCategory.command,
      icon: Icons.close_fullscreen_outlined,
      enabled: hooks.closeEditorGroup != null && layout.controllers.length > 1,
      onSelect: hooks.closeEditorGroup,
      subtitle: hooks.closeEditorGroup == null
          ? tr(I18nKey.paletteDisabled)
          : null,
    ),
    PaletteEntry(
      id: 'builtin.view.reset_layout',
      title: tr(I18nKey.menuResetEditorLayout),
      category: PaletteCategory.command,
      icon: Icons.restart_alt_outlined,
      enabled: hooks.resetEditorLayout != null,
      onSelect: hooks.resetEditorLayout,
      subtitle: hooks.resetEditorLayout == null
          ? tr(I18nKey.paletteDisabled)
          : null,
    ),

    // Navigation.
    _navigationEntry(
      id: 'builtin.nav.files',
      title: tr(I18nKey.navFiles),
      route: file,
      icon: Icons.folder_outlined,
    ),
    _navigationEntry(
      id: 'builtin.nav.search',
      title: tr(I18nKey.navSearch),
      route: search,
      icon: Icons.search_outlined,
    ),
    _navigationEntry(
      id: 'builtin.nav.devices',
      title: tr(I18nKey.navDevices),
      route: tools,
      icon: Icons.usb_outlined,
    ),
    _navigationEntry(
      id: 'builtin.nav.git',
      title: tr(I18nKey.navGit),
      route: git,
      icon: Icons.account_tree_outlined,
    ),
    _navigationEntry(
      id: 'builtin.nav.plugins',
      title: tr(I18nKey.navPlugins),
      route: plugins,
      icon: Icons.extension_outlined,
    ),
    _navigationEntry(
      id: 'builtin.nav.settings',
      title: tr(I18nKey.navSettings),
      route: settings,
      icon: Icons.settings_outlined,
    ),
    if (!ResponsiveBreakpoints.of(context).isDesktop)
      _navigationEntry(
        id: 'builtin.nav.editor',
        title: tr(I18nKey.navEditor),
        route: edit,
        icon: Icons.edit_outlined,
      ),

    // Settings sections.
    _navigationEntry(
      id: 'builtin.settings.editor',
      title: tr(I18nKey.settingsEditorTitle),
      route: '/settings/editor',
      icon: Icons.tune_outlined,
      category: PaletteCategory.setting,
    ),
    _navigationEntry(
      id: 'builtin.settings.terminal',
      title: tr(I18nKey.settingsTerminalTitle),
      route: '/settings/terminal',
      icon: Icons.terminal_outlined,
      category: PaletteCategory.setting,
    ),
    _navigationEntry(
      id: 'builtin.settings.lsp',
      title: tr(I18nKey.settingsLspTitle),
      route: '/settings/lsp',
      icon: Icons.code_outlined,
      category: PaletteCategory.setting,
    ),
    _navigationEntry(
      id: 'builtin.settings.style',
      title: tr(I18nKey.settingsStyleTitle),
      route: '/settings/style',
      icon: Icons.palette_outlined,
      category: PaletteCategory.setting,
    ),
    _navigationEntry(
      id: 'builtin.settings.about',
      title: tr(I18nKey.settingsAboutTitle),
      route: '/settings/about',
      icon: Icons.info_outline,
      category: PaletteCategory.setting,
    ),
  ];

  return entries;
}

PaletteEntry _navigationEntry({
  required String id,
  required String title,
  required String route,
  required IconData icon,
  PaletteCategory category = PaletteCategory.navigation,
}) {
  return PaletteEntry(
    id: id,
    title: title,
    category: category,
    icon: icon,
    onSelect: (context, ref) async => context.go(route),
  );
}

/// Quick-open rows for the indexed project files.
List<PaletteEntry> buildFilePaletteEntries(Iterable<ProjectFileEntry> files) {
  return [
    for (final fileEntry in files)
      PaletteEntry(
        id: 'file:${fileEntry.path}',
        title: fileEntry.name,
        subtitle: fileEntry.relativePath,
        category: PaletteCategory.file,
        icon: Icons.insert_drive_file_outlined,
        keywords: [fileEntry.relativePath],
        searchText: fileEntry.relativePath.toLowerCase(),
        onSelect: (context, ref) => _openProjectFile(context, ref, fileEntry),
      ),
  ];
}

Future<void> _openProjectFile(
  BuildContext context,
  WidgetRef ref,
  ProjectFileEntry entry,
) async {
  final file = File(entry.path);
  if (!await file.exists()) {
    throw FileSystemException('File not found', entry.relativePath);
  }
  if (!context.mounted) return;
  if (!ResponsiveBreakpoints.of(context).isDesktop) {
    context.go(edit);
  }
  await ref
      .read(tabbedViewControllerProvider.notifier)
      .openFile(context, file: file);
}
