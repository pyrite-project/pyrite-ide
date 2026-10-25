import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The workspace panes a plugin view can be placed in.
///
/// The editor area is the main pane: its split groups are the editor layout
/// tree, and one of them always holds focus. The docked console panel is the
/// only pane outside it.
enum WorkspacePane { editor, console }

/// The pane the user last interacted with, and the target of a view opened
/// without an explicit pane.
///
/// The editor pane is the starting value: it is the workspace's center, and
/// every session starts there before anything else was clicked.
final StateProvider<WorkspacePane> focusedWorkspacePaneProvider =
    StateProvider<WorkspacePane>((ref) => WorkspacePane.editor);

/// Where a plugin view should be placed, as `sdk.tab.create_view`'s `pane`
/// argument resolves to.
sealed class ViewPaneTarget {
  const ViewPaneTarget();

  /// The focused pane: the focused editor group, or the console when the user
  /// was last working there.
  const factory ViewPaneTarget.focused() = FocusedPaneTarget;

  /// The editor area's active group -- the focused one, or the primary group
  /// when none has focus.
  const factory ViewPaneTarget.editor() = EditorPaneTarget;

  /// The docked console panel.
  const factory ViewPaneTarget.console() = ConsolePaneTarget;

  /// A specific editor group, by its index in layout order -- the same index
  /// `sdk.tab.list` reports.
  const factory ViewPaneTarget.group(int index) = GroupPaneTarget;
}

/// The focused pane's target.
class FocusedPaneTarget extends ViewPaneTarget {
  const FocusedPaneTarget();
}

/// The editor area's active group.
class EditorPaneTarget extends ViewPaneTarget {
  const EditorPaneTarget();
}

/// The docked console panel.
class ConsolePaneTarget extends ViewPaneTarget {
  const ConsolePaneTarget();
}

/// One editor group, by its index in layout order.
class GroupPaneTarget extends ViewPaneTarget {
  const GroupPaneTarget(this.index);

  final int index;
}

/// Resolves the `pane` argument: `focused` (or no argument at all), `editor`,
/// `console`, or a group index -- a JSON number, or its decimal string.
/// Anything else is unknown and rejected by the caller.
ViewPaneTarget? viewPaneFromPayload(Object? pane) {
  if (pane == null || pane == '' || pane == 'focused') {
    return const ViewPaneTarget.focused();
  }
  if (pane == 'editor') return const ViewPaneTarget.editor();
  if (pane == 'console') return const ViewPaneTarget.console();
  final index = pane is int ? pane : int.tryParse(pane.toString());
  if (index != null) return ViewPaneTarget.group(index);
  return null;
}
