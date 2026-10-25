import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
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

/// Opens another outline tab in the group the user is working in.
///
/// The outline is an ordinary member of the editor layout: the new tab joins
/// the active group like any file tab would, and from there it can be dragged
/// into another group or used to split one. Several outlines can coexist, in
/// the same or in different groups.
void openOutlineTab(WidgetRef ref) {
  ref
      .read(tabbedViewControllerProvider.notifier)
      .openTab(
        buildOutlineTab(translateForWidget(ref, I18nKey.editorOutlineTitle)),
      );
}
