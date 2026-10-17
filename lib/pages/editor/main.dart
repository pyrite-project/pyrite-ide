import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/serial/active_device_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/file/board_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/features/edit_core/main.dart';
import 'package:pyrite_ide/features/function_page/editor_split_drop.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;
import 'package:pyrite_ide/shared/tabbed_view/tabbed_view.dart';
import 'package:pyrite_ide/shared/tabbed_view/tab_strip_theme.dart';

/// The editor area: the layout tree recorded in [editorLayoutProvider], laid
/// out recursively so a group can be split again inside itself.
///
/// Only a change of the tree rebuilds the area. Each group's strip follows its
/// own controller, and the toolbar follows the active tab.
class Editor extends ConsumerStatefulWidget {
  const Editor({super.key});

  @override
  ConsumerState<Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<Editor> {
  /// One key per group, so reshaping the tree moves a group's subtree instead
  /// of rebuilding it: its open editors keep their scroll position, focus and
  /// search state.
  ///
  /// Held by this editor area rather than derived from the controller alone,
  /// so two areas briefly on screen together -- the frame a window crosses a
  /// layout breakpoint -- never claim the same key.
  final Map<TabbedViewController, GlobalKey> _groupKeys = {};

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(editorLayoutProvider);
    _groupKeys.removeWhere((group, _) => !layout.contains(group));
    // A root-level split promises to take the whole area, and the root has no
    // pane of its own to draw that in, so the area draws it.
    final areaPreview = ref.watch(editorAreaSplitPreviewProvider);
    return Scaffold(
      appBar: const EditorToolbar(),
      body: Stack(
        children: [
          _buildLayout(layout),
          if (areaPreview != null)
            Positioned.fill(child: EditorSplitHint(split: areaPreview)),
        ],
      ),
    );
  }

  Widget _buildLayout(EditorLayout node) {
    return switch (node) {
      GroupLayout(:final controller) => KeyedSubtree(
        key: _groupKeys.putIfAbsent(controller, GlobalKey.new),
        // One drop region per group: its edges split this group, its middle
        // accepts a tab from another one.
        child: EditorSplitDropRegion(
          controller: controller,
          child: EditorGroup(controller: controller),
        ),
      ),
      SplitLayout(:final axis, :final children) => shadcn.ResizablePanel(
        direction: axis,
        optionalDivider: false,
        draggerBuilder: (context) => switch (axis) {
          Axis.horizontal => const shadcn.VerticalResizableDragger(),
          Axis.vertical => const shadcn.HorizontalResizableDragger(),
        },
        children: [
          for (final child in children)
            shadcn.ResizablePane.flex(
              initialFlex: 1,
              minSize: 200,
              child: _buildLayout(child),
            ),
        ],
      ),
    };
  }
}

/// The editor area's action bar.
///
/// One bar for the whole area rather than one per group: it acts on the tab
/// [activeEditorTabProvider] resolves to -- the selected tab of the group the
/// user last worked in -- and rebuilds as that tab changes.
class EditorToolbar extends ConsumerWidget implements PreferredSizeWidget {
  const EditorToolbar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeEditorTabProvider);
    final fileValue = active.value;
    final canSave = fileValue?.type == "file";
    final isConnected = ref.watch(deviceConnectedProvider);
    final serialConnected = ref.watch(serialProvider).isConnected;
    final hardwareResetStrategy = ref.watch(hardwareResetStrategyProvider);
    return AppBar(
      titleSpacing: 8,
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            IconButton(
              tooltip: translateForWidget(ref, I18nKey.commonSave),
              icon: const Icon(Icons.save_outlined),
              onPressed: canSave ? () => saveFile(context, ref) : null,
            ),
            const SizedBox(width: 4),
            (fileValue?.isBoardFile == true)
                ? IconButton(
                    tooltip: translateForWidget(
                      ref,
                      I18nKey.editorToolbarDownload,
                    ),
                    icon: const Icon(Icons.download_outlined),
                    onPressed: canSave && isConnected
                        ? () => ref
                              .read(boardProvider)
                              .downloadSelectedBoardItem(context)
                        : null,
                  )
                : IconButton(
                    tooltip: translateForWidget(
                      ref,
                      I18nKey.editorToolbarUpload,
                    ),
                    icon: const Icon(Icons.upload_outlined),
                    onPressed: canSave && isConnected
                        ? () => ref
                              .read(fileProvider.notifier)
                              .uploadSelectedLocalFileItem(
                                context,
                                selectedTab: active.tab,
                              )
                        : null,
                  ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: translateForWidget(ref, I18nKey.editorToolbarRun),
              icon: const Icon(Icons.play_arrow),
              onPressed: canSave && isConnected
                  ? () => runCurrentFile(context, ref)
                  : null,
            ),
            const SizedBox(height: 24, child: VerticalDivider(thickness: 1)),
            IconButton(
              tooltip: translateForWidget(
                ref,
                isConnected
                    ? I18nKey.editorToolbarInterruptDevice
                    : I18nKey.editorToolbarInterruptNeedsDevice,
              ),
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: isConnected
                  ? () {
                      sendCommandToActiveDevice(ref.read, "\x03");
                    }
                  : null,
            ),
            IconButton(
              tooltip: translateForWidget(
                ref,
                serialConnected &&
                        hardwareResetStrategy != HardwareResetStrategy.disabled
                    ? I18nKey.editorToolbarHardwareReset
                    : I18nKey.editorToolbarHardwareResetUnavailable,
              ),
              icon: const Icon(Icons.power_settings_new),
              onPressed:
                  serialConnected &&
                      hardwareResetStrategy != HardwareResetStrategy.disabled
                  ? () async {
                      final accepted = await hardwareResetDevice(ref.read);
                      if (!context.mounted) return;
                      showIdeMessage(
                        context,
                        translateForWidget(
                          ref,
                          accepted
                              ? I18nKey.editorToolbarHardwareResetStarted
                              : I18nKey.editorToolbarHardwareResetFailed,
                        ),
                        type: accepted
                            ? IdeMessageType.success
                            : IdeMessageType.error,
                      );
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
              icon: const Icon(Icons.restart_alt),
              onPressed: isConnected
                  ? () {
                      sendCommandToActiveDevice(ref.read, "\x04");
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
    );
  }
}

/// One editor group: its tab strip, and nothing else.
///
/// The action bar is the editor area's, not the group's -- it sits once above
/// the whole layout and acts on whichever group the user last worked in.
class EditorGroup extends ConsumerWidget {
  const EditorGroup({super.key, required this.controller});

  final TabbedViewController controller;

  /// Marks this group as the one the shared editing commands act on.
  void _focus(WidgetRef ref) {
    ref.read(editorLayoutProvider.notifier).focus(controller);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A click focuses the group, and so does keyboard focus arriving inside
    // it -- Tab traversal, a shortcut, an editor requesting focus -- so the
    // toolbar never acts on a group other than the one being typed in.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) _focus(ref);
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _focus(ref),
        child: TabbedViewTheme(
          data: buildTabStripTheme(context),
          child: TabbedView(controller: controller),
        ),
      ),
    );
  }
}
