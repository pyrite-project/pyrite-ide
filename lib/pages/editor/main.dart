import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/serial/active_device_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/file_tab_title.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
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
class Editor extends ConsumerStatefulWidget {
  const Editor({super.key});

  @override
  ConsumerState<Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<Editor> {
  final Set<TabbedViewController> _followed = {};

  @override
  void dispose() {
    for (final controller in _followed) {
      controller.removeListener(_onGroupChanged);
    }
    _followed.clear();
    super.dispose();
  }

  void _onGroupChanged() {
    if (mounted) setState(() {});
  }

  /// A group empties through its own controller -- the close button, the
  /// context menu, the SDK -- and that notify never reaches the layout
  /// provider. Following the controllers is what lets the editor notice an
  /// emptied group and prune it in the same frame.
  void _follow(EditorLayout layout, TabbedViewController primary) {
    for (final controller in layout.controllers(primary)) {
      if (_followed.add(controller)) {
        controller.addListener(_onGroupChanged);
      }
    }
    // Groups that left the tree must stop notifying a subtree that is gone.
    _followed.removeWhere((controller) {
      final stale = !layout.controllers(primary).contains(controller);
      if (stale) controller.removeListener(_onGroupChanged);
      return stale;
    });
  }

  @override
  Widget build(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    // Watched as well as the layout: the primary controller is swapped for a
    // fresh instance by nearly every tab operation, and the strip has to
    // follow it or the new tab would open into a stale tree.
    final primary = ref.watch(tabbedViewControllerProvider);
    final layout = ref.watch(editorLayoutProvider);
    _follow(layout, primary);
    if (needsEditorLayoutRefresh(container)) {
      // Out of the build phase: the layout changed, so it has to be rewritten.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        container.read(editorLayoutProvider.notifier).state =
            refreshEditorLayout(container);
        // Which names collide changed with the pruning, so the titles have to
        // be recomputed here as well: `_refreshLayout` does it for the drag
        // paths, and a pruned group otherwise leaves a long title behind.
        refreshFileTabTitles(allEditorTabs(container));
      });
    }
    // A root-level split promises to take the whole area, and the root has no
    // pane of its own to draw that in, so the area draws it.
    final areaPreview = ref.watch(editorAreaSplitPreviewProvider);
    return Scaffold(
      appBar: _buildToolbar(context),
      body: Stack(
        children: [
          _buildLayout(context, layout),
          if (areaPreview != null)
            Positioned.fill(child: EditorSplitHint(split: areaPreview)),
        ],
      ),
    );
  }

  /// The editor area's action bar.
  ///
  /// One bar for the whole area rather than one per group: it acts on the
  /// group the user last clicked, which is what
  /// [activeEditorControllerProvider] resolves to. [Editor] rebuilds whenever
  /// any group controller notifies, so the bar tracks the focused group's tab
  /// without extra listeners of its own.
  PreferredSizeWidget _buildToolbar(BuildContext context) {
    final active = ref.watch(activeEditorControllerProvider);
    final fileValue = editorTabValueOf(active.selectedTab);
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
                                selectedTab: active.selectedTab,
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

  Widget _buildLayout(BuildContext context, EditorLayout node) {
    if (node is! SplitLayout) {
      // One drop region per group: its edges split this group, its middle
      // accepts a tab from another one.
      final controller = groupController(
        ProviderScope.containerOf(context),
        node,
      );
      return EditorSplitDropRegion(
        controller: controller,
        child: EditorGroup(controller: controller),
      );
    }
    final split = node;
    return shadcn.ResizablePanel(
      direction: split.axis,
      optionalDivider: false,
      draggerBuilder: (context) => switch (split.axis) {
        Axis.horizontal => const shadcn.VerticalResizableDragger(),
        Axis.vertical => const shadcn.HorizontalResizableDragger(),
      },
      children: [
        for (final child in split.children)
          shadcn.ResizablePane.flex(
            initialFlex: 1,
            minSize: 200,
            child: _buildLayout(context, child),
          ),
      ],
    );
  }
}

/// One editor group: its tab strip, and nothing else.
///
/// The action bar is the editor area's, not the group's -- it sits once above
/// the whole layout and acts on whichever group the user last clicked.
class EditorGroup extends ConsumerWidget {
  const EditorGroup({super.key, required this.controller});

  final TabbedViewController controller;

  /// Marks this group as the one the shared editing commands act on.
  void _focus(WidgetRef ref) {
    if (ref.read(focusedEditorGroupProvider) != controller) {
      ref.read(focusedEditorGroupProvider.notifier).state = controller;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _focus(ref),
      child: TabbedViewTheme(
        data: buildTabStripTheme(context),
        child: TabbedView(controller: controller),
      ),
    );
  }
}
