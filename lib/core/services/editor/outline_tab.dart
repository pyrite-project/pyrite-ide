import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
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

/// The tab group column the outline is born into, docked to the right of the
/// editor tabs. Null while no outline column exists.
///
/// The column only ever holds outline tabs — its [TabbedView] rejects drops
/// of anything else — so a plain count is all its persistence needs.
final StateProvider<TabbedViewController?> editorOutlineColumnProvider =
    StateProvider<TabbedViewController?>((ref) => null);

/// Builds an outline tab.
///
/// An ordinary tab — draggable, closable, [TabData.keepAlive] like a file tab
/// so its collapse state survives being deselected — whose content is the
/// outline panel.
TabData buildOutlineTab(String title) {
  return TabData(
    value: const OutlineTabValue(),
    text: title,
    keepAlive: true,
    content: const EditorOutlinePanel(),
  );
}

/// Opens another outline tab, born into the rightmost outline column.
///
/// The column is created on first use; while it exists the new tab joins it
/// as a sibling, which is what makes several outlines possible. Tabs dragged
/// out into the editor bar keep living there — the saved layout wins over the
/// birth position, and a column whose tabs are all gone closes itself.
void openOutlineTab(BuildContext context, WidgetRef ref) {
  final column = ref.read(editorOutlineColumnProvider);
  if (column != null && column.tabs.isNotEmpty) {
    column.addTab(
      buildOutlineTab(translateInContext(context, I18nKey.editorOutlineTitle)),
    );
    return;
  }
  ref.read(editorOutlineColumnProvider.notifier).state = TabbedViewController([
    buildOutlineTab(translateInContext(context, I18nKey.editorOutlineTitle)),
  ]);
}
