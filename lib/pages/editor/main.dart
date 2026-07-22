import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/expansion_page.dart';
import 'package:pyrite_ide/core/services/file/board_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/features/edit_core/main.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;
import 'package:pyrite_ide/shared/tabbed_view/tabbed_view.dart';

class Editor extends ConsumerWidget {
  const Editor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedValue = ref
        .watch(tabbedViewControllerProvider)
        .selectedTab
        ?.value;
    final fileValue =
        selectedValue is TabDataValue && selectedValue.type == "file"
        ? selectedValue
        : null;
    final canSave = fileValue != null;
    final isConnected = ref.watch(getUsbSerialProvider()).isConnected;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: canSave ? () => saveFile(context, ref) : null,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const UseText(I18nKey.commonSave),
              ),
              const SizedBox(width: 4),
              (ref
                          .read(tabbedViewControllerProvider)
                          .selectedTab
                          ?.value
                          .isBoardFile ==
                      true)
                  ? OutlinedButton.icon(
                      onPressed: canSave && isConnected
                          ? () => ref
                                .read(boardProvider.notifier)
                                .downloadSelectedBoardItem(context)
                          : null,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const UseText(I18nKey.editorToolbarDownload),
                    )
                  : OutlinedButton.icon(
                      onPressed: canSave && isConnected
                          ? () => ref
                                .read(fileProvider.notifier)
                                .uploadSelectedLocalFileItem(
                                  context,
                                  selectedTab: ref
                                      .read(tabbedViewControllerProvider)
                                      .selectedTab,
                                )
                          : null,
                      icon: const Icon(Icons.upload_outlined, size: 18),
                      label: const UseText(I18nKey.editorToolbarUpload),
                    ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: canSave && isConnected
                    ? () => runCurrentFile(context, ref)
                    : null,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const UseText(I18nKey.editorToolbarRun),
              ),
              const SizedBox(height: 24, child: VerticalDivider(thickness: 1)),
              IconButton(
                tooltip: translateForWidget(
                  ref,
                  isConnected
                      ? I18nKey.editorToolbarInterruptDevice
                      : I18nKey.editorToolbarInterruptNeedsDevice,
                ),
                icon: const Icon(Icons.stop_circle_outlined, size: 20),
                onPressed: isConnected
                    ? () {
                        ref
                            .read(getUsbSerialProvider().notifier)
                            .sendCommand("\x03");
                      }
                    : null,
              ),
              IconButton(
                tooltip: translateForWidget(
                  ref,
                  isConnected
                      ? I18nKey.editorToolbarSoftReboot
                      : I18nKey.editorToolbarSoftRebootNeedsDevice,
                ),
                icon: const Icon(Icons.restart_alt, size: 20),
                onPressed: isConnected
                    ? () {
                        ref
                            .read(getUsbSerialProvider().notifier)
                            .sendCommand("\x04");
                      }
                    : null,
              ),
              PopupMenuButton<String>(
                tooltip: translateForWidget(
                  ref,
                  I18nKey.editorToolbarMoreActions,
                ),
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case "saveAs":
                      ref.read(fileProvider.notifier).saveCurrentFileAs();
                      break;
                    case "cut":
                      ref.read(editorControllerMapProvider.notifier).cut();
                      break;
                    case "copy":
                      ref.read(editorControllerMapProvider.notifier).copy();
                      break;
                    case "paste":
                      ref.read(editorControllerMapProvider.notifier).paste();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: "saveAs",
                    enabled: canSave,
                    child: const UseText(I18nKey.menuSaveAs),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: "cut",
                    enabled: canSave,
                    child: const UseText(I18nKey.menuCut),
                  ),
                  PopupMenuItem(
                    value: "copy",
                    enabled: canSave,
                    child: const UseText(I18nKey.menuCopy),
                  ),
                  PopupMenuItem(
                    value: "paste",
                    enabled: canSave,
                    child: const UseText(I18nKey.menuPaste),
                  ),
                ],
              ),
            ],
          ),
        ),
        toolbarHeight: 50,
      ),
      body: body(context, ref),
    );
  }

  Widget body(BuildContext context, WidgetRef ref) {
    return TabbedViewTheme(
      data: TabbedViewThemeData.underline(
        colorSet: MaterialColor(
          Theme.of(context).colorScheme.primary.toARGB32(),
          <int, Color>{
            50: Theme.of(context).colorScheme.surface,
            400: Theme.of(context).colorScheme.secondaryContainer,
            500: Theme.of(context).colorScheme.surface,
            700: Theme.of(context).colorScheme.secondary,
            900: Theme.of(context).colorScheme.onSecondaryContainer,
          },
        ),
        underlineColorSet: MaterialColor(
          Theme.of(context).colorScheme.primary.toARGB32(),
          <int, Color>{},
        ),
      ),
      child: TabbedView(controller: ref.watch(tabbedViewControllerProvider)),
    );
  }
}

class ExpansionPage extends ConsumerWidget {
  const ExpansionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedValue = ref.watch(expansionViewController).selectedTab?.value;
    final fileValue =
        selectedValue is TabDataValue && selectedValue.type == "file"
        ? selectedValue
        : null;
    final canSave = fileValue != null;
    return Scaffold(
      body: Column(
        children: [
          PaneHeader(
            title: I18nKey.settingsExpansionPanelTitle,
            leadingIcon: Icons.expand_outlined,
            actions: [
              PopupMenuButton<String>(
                tooltip: translateForWidget(
                  ref,
                  I18nKey.editorToolbarMoreActions,
                ),
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case "saveAs":
                      ref.read(fileProvider.notifier).saveCurrentFileAs();
                      break;
                    case "cut":
                      ref.read(editorControllerMapProvider.notifier).cut();
                      break;
                    case "copy":
                      ref.read(editorControllerMapProvider.notifier).copy();
                      break;
                    case "paste":
                      ref.read(editorControllerMapProvider.notifier).paste();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: "saveAs",
                    enabled: canSave,
                    child: const UseText(I18nKey.menuSaveAs),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: "cut",
                    enabled: canSave,
                    child: const UseText(I18nKey.menuCut),
                  ),
                  PopupMenuItem(
                    value: "copy",
                    enabled: canSave,
                    child: const UseText(I18nKey.menuCopy),
                  ),
                  PopupMenuItem(
                    value: "paste",
                    enabled: canSave,
                    child: const UseText(I18nKey.menuPaste),
                  ),
                ],
              ),
            ],
          ),
          Expanded(child: body(context, ref)),
        ],
      ),
    );
  }

  Widget body(BuildContext context, WidgetRef ref) {
    return TabbedViewTheme(
      data: TabbedViewThemeData.underline(
        colorSet: MaterialColor(
          Theme.of(context).colorScheme.primary.toARGB32(),
          <int, Color>{
            50: Theme.of(context).colorScheme.surface,
            400: Theme.of(context).colorScheme.secondaryContainer,
            500: Theme.of(context).colorScheme.surface,
            700: Theme.of(context).colorScheme.secondary,
            900: Theme.of(context).colorScheme.onSecondaryContainer,
          },
        ),
        underlineColorSet: MaterialColor(
          Theme.of(context).colorScheme.primary.toARGB32(),
          <int, Color>{},
        ),
      ),
      child: TabbedView(controller: ref.watch(expansionViewController)),
    );
  }
}
