import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/features/edit_core/editor_outline_panel.dart';
import 'package:tabbed_view/tabbed_view.dart';

/// Identity of an outline tab's [TabData.value].
///
/// Deliberately not a [TabDataValue]: every loop that walks the tab strip for
/// files, plugin views or persistence guards with `value is TabDataValue`, so
/// an outline tab is skipped in all of them for free — it is an ordinary tab
/// whose only payload is the outline panel itself.
class OutlineTabValue {
  const OutlineTabValue();
}

/// Whether [tab] is an outline tab.
bool isOutlineTab(TabData tab) => tab.value is OutlineTabValue;

/// Builds an outline tab.
///
/// An ordinary tab — draggable, closable, [TabData.keepAlive] like a file tab
/// so its collapse state survives being deselected — whose content is the
/// outline panel. It lives in whatever editor group holds it, so it splits,
/// drags and persists exactly like a file tab does; persistence stores it as
/// an outline marker in its group's tab list.
TabData buildOutlineTab(String title) {
  return TabData(
    value: const OutlineTabValue(),
    text: title,
    keepAlive: true,
    content: const EditorOutlinePanel(),
  );
}

/// Opens the outline: shows the one that exists, or births a new group.
///
/// With no outline anywhere, a fresh tab is born into a group split off the
/// active group's right edge — the outline reads the tab the user is working
/// on, so it belongs beside it. The split takes no focus: the panel watches
/// the focused group's selected tab, so on its first build it must still see
/// the file that had focus before the button press to parse anything at all.
/// An outline that already exists, wherever the user has dragged it, is
/// focused instead: a second press of the toolbar toggle must not stack a
/// second outline group beside the first.
void openOutlineTab(WidgetRef ref) {
  for (final tab in ref.read(editorLayoutProvider).tabs) {
    if (isOutlineTab(tab)) {
      ref.read(tabbedViewControllerProvider.notifier).focusTab(tab);
      return;
    }
  }
  ref.read(editorLayoutProvider.notifier).splitGroupWithNewTab(
    target: ref.read(activeEditorControllerProvider),
    tab: buildOutlineTab(translateForWidget(ref, I18nKey.editorOutlineTitle)),
    where: PaneEdge.right,
    focusCreated: false,
  );
}
