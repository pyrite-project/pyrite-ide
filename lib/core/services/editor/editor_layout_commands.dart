import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/shared/tabbed_view/tab_close_actions.dart';
import 'package:tabbed_view/tabbed_view.dart'
    show TabData, TabbedViewController;

/// An editor-group action a menu, shortcut or palette entry can run.
///
/// The command doubles as its palette identity ([id]) and its localized label
/// ([labelKey]), so the palette can list the same set of actions the editor's
/// own menus offer without a parallel table drifting out of date.
enum EditorLayoutCommand {
  splitRight('editor.split.right', PaneEdge.right),
  splitDown('editor.split.down', PaneEdge.bottom),
  closeGroup('editor.close_group', null),
  resetLayout('editor.reset_layout', null),
  reopenClosedTab('editor.reopen_closed_tab', null);

  const EditorLayoutCommand(this.id, this.splitEdge);

  /// Stable identifier for palette recents and keybindings.
  final String id;

  /// Where this command splits the active group, or null when it is not a
  /// split command.
  final PaneEdge? splitEdge;

  I18nKey get labelKey => switch (this) {
    EditorLayoutCommand.splitRight => I18nKey.editorSplitRight,
    EditorLayoutCommand.splitDown => I18nKey.editorSplitDown,
    EditorLayoutCommand.closeGroup => I18nKey.editorCloseGroup,
    EditorLayoutCommand.resetLayout => I18nKey.editorResetLayout,
    EditorLayoutCommand.reopenClosedTab => I18nKey.editorReopenClosedTab,
  };
}

/// Splits [group] towards [where], moving [tab] into the new group.
///
/// Returns false when the split would be undone immediately -- a pinned tab,
/// or a group whose last tab is the one moving.
bool splitEditorGroup(
  WidgetRef ref,
  TabbedViewController group,
  TabData tab,
  PaneEdge where,
) {
  final layout = ref.read(editorLayoutProvider.notifier);
  if (!layout.canSplitGroup(from: group, target: group, tab: tab)) {
    return false;
  }
  return layout.splitGroup(from: group, target: group, tab: tab, where: where);
}

/// Splits the active editor group towards [where].
///
/// The selected tab of the active group moves into the new group, which is
/// what splitting from a tab's own group does. Returns false when the group
/// has no tab, or when the split is not possible.
bool splitActiveEditor(WidgetRef ref, PaneEdge where) {
  final group = ref.read(activeEditorControllerProvider);
  final tab = group.selectedTab;
  if (tab == null) return false;
  return splitEditorGroup(ref, group, tab, where);
}

/// Closes every closable tab of [group], prompting for each dirty one.
///
/// The pinned welcome page is skipped rather than closed, so closing the
/// primary group cannot remove the editor's floor. Cancelling any prompt
/// stops the batch: the user asked to keep that file.
///
/// [last] is closed after the other tabs. A tab's own context menu runs in the
/// widget being removed, so closing it first would unmount the context the
/// remaining prompts still need.
Future<void> closeEditorGroup(
  BuildContext context,
  TabbedViewController group, {
  TabData? last,
}) {
  final targets = group.tabs.toList();
  if (last != null && targets.remove(last)) targets.add(last);
  return closeTabsInController(context, group, targets);
}

/// Closes every closable tab of the active editor group.
Future<void> closeActiveEditorGroup(BuildContext context, WidgetRef ref) {
  return closeEditorGroup(context, ref.read(activeEditorControllerProvider));
}

/// Collapses the editor area back into the primary group.
void resetEditorLayout(WidgetRef ref) {
  ref.read(editorLayoutProvider.notifier).resetLayout();
}

/// Reopens the local file tab closed most recently.
///
/// Returns true when a tab was opened or focused.
Future<bool> reopenClosedEditorTab(BuildContext context, WidgetRef ref) {
  return ref
      .read(tabbedViewControllerProvider.notifier)
      .reopenLastClosedTab(context);
}

/// Runs [command] with the widget layer's [context] and [ref].
///
/// This is the single entry point a palette or keybinding needs: it owns the
/// command-to-helper mapping and returns whether the command changed anything
/// (a disabled split, a cancelled close or an empty reopen history return
/// false).
Future<bool> runEditorLayoutCommand(
  BuildContext context,
  WidgetRef ref,
  EditorLayoutCommand command,
) async {
  switch (command) {
    case EditorLayoutCommand.splitRight:
      return splitActiveEditor(ref, PaneEdge.right);
    case EditorLayoutCommand.splitDown:
      return splitActiveEditor(ref, PaneEdge.bottom);
    case EditorLayoutCommand.closeGroup:
      await closeActiveEditorGroup(context, ref);
      return true;
    case EditorLayoutCommand.resetLayout:
      resetEditorLayout(ref);
      return true;
    case EditorLayoutCommand.reopenClosedTab:
      return reopenClosedEditorTab(context, ref);
  }
}
