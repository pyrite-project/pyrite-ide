import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/problems_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/features/function_page.dart';
import 'package:pyrite_ide/features/function_page/console_surface_actions.dart';
import 'package:pyrite_ide/features/function_page/problems_view.dart';
import 'package:pyrite_ide/shared/tabbed_view/tab_chrome.dart';
import 'package:super_context_menu/super_context_menu.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

/// One of the console panel's fixed surfaces, in their canonical order.
///
/// The id survives a drag, which is what lets a tab keep its identity while it
/// moves between the console strip and the editor strip.
enum ConsoleTabId { repl, log, terminal, problems }

/// Value carried by every console tab.
///
/// The console and the editor share one drag-and-drop system, so a tab has to
/// say which surface it is: it keeps a console tab distinguishable from a file
/// tab after the strips have exchanged tabs, and it brings the surface's menu
/// and buttons into whichever strip hosts it.
@immutable
class ConsoleTabValue implements TabChrome {
  const ConsoleTabValue(this.id);

  final ConsoleTabId id;

  @override
  Menu buildTabMenu(BuildContext context) => buildConsoleTabMenu(context);

  @override
  Widget? buildTabActions(BuildContext context) => switch (id) {
    ConsoleTabId.repl => const ReplSurfaceActions(),
    ConsoleTabId.log => const LogSurfaceActions(),
    ConsoleTabId.terminal => null,
    ConsoleTabId.problems => const ProblemsSurfaceActions(),
  };
}

/// Whether [tab] is one of the console panel's fixed surfaces.
bool isConsoleTab(TabData tab) => tab.value is ConsoleTabValue;

/// Total problem count, rendered as a suffix on the Problems tab.
final Provider<int> consoleProblemCountProvider = Provider<int>((ref) {
  var count = 0;
  for (final file in ref.watch(problemsProvider)) {
    count += file.errorCount + file.warningCount;
  }
  return count;
});

/// Appends the open-problem count to an already translated [baseLabel].
String consoleProblemsLabel(String baseLabel, int count) {
  return count > 0 ? '$baseLabel ($count)' : baseLabel;
}

/// The label of surface [id], with the Problems count when there is one.
String _consoleLabel(
  ConsoleTabId id,
  String Function(I18nKey key) tr,
  int problemCount,
) => switch (id) {
  ConsoleTabId.repl => 'REPL',
  ConsoleTabId.log => tr(I18nKey.bottomPanelLogTab),
  ConsoleTabId.terminal => tr(I18nKey.bottomPanelTerminalTab),
  ConsoleTabId.problems => consoleProblemsLabel(
    tr(I18nKey.bottomPanelProblemsTab),
    problemCount,
  ),
};

TabData _consoleTab(ConsoleTabId id, String label) {
  final (icon, content) = switch (id) {
    ConsoleTabId.repl => (Icons.terminal, const ReplView() as Widget),
    ConsoleTabId.log => (Icons.article_outlined, const OutputLogView()),
    ConsoleTabId.terminal => (
      Icons.terminal_outlined,
      const DesktopTerminalView(),
    ),
    ConsoleTabId.problems => (
      Icons.report_problem_outlined,
      const ProblemsView(),
    ),
  };
  return TabData(
    // The surfaces are permanent: closing one would leave no way back.
    closable: false,
    keepAlive: true,
    value: ConsoleTabValue(id),
    text: label,
    content: content,
    leading: (context, status) => Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// The console panel's tab strip.
///
/// One controller for the whole session, changed in place like every editor
/// group: its tabs travel between this strip and the editor groups. The labels
/// follow the problem count and the language wherever the tabs sit, so the
/// Problems count stays live inside an editor group, or while the panel is
/// hidden.
final Provider<TabbedViewController> consoleTabbedViewControllerProvider =
    Provider<TabbedViewController>((ref) {
      String label(ConsoleTabId id) => _consoleLabel(
        id,
        (key) => translate(ref, key),
        ref.read(consoleProblemCountProvider),
      );
      final controller = TabbedViewController([
        for (final id in ConsoleTabId.values) _consoleTab(id, label(id)),
      ]);

      void relabel() {
        for (final tab in [
          ...controller.tabs,
          ...ref.read(editorLayoutProvider).tabs,
        ]) {
          if (tab.value case ConsoleTabValue(:final id)) tab.text = label(id);
        }
      }

      ref.listen(consoleProblemCountProvider, (_, _) => relabel());
      ref.listen(activeLocaleProvider, (_, _) => relabel());
      ref.listen(dataRegistryProvider, (_, _) => relabel());
      return controller;
    });

/// The right-click menu of a console surface, in whichever strip it sits.
///
/// The panel's position is chosen here, like VS Code's "Panel Position": the
/// panel is moved by a command, its tabs by a drag.
Menu buildConsoleTabMenu(BuildContext context) {
  final container = ProviderScope.containerOf(context);
  final registry = container.read(dataRegistryProvider);
  final locale = container.read(activeLocaleProvider);
  String tr(I18nKey key) => translateFromRegistry(registry, locale, key);
  final docked = container.read(consoleDockSideProvider);

  return Menu(
    children: [
      Menu(
        title: tr(I18nKey.consolePanelPosition),
        children: [
          for (final edge in PaneEdge.values)
            MenuAction(
              title: tr(_dockLabel(edge)),
              state: edge == docked
                  ? MenuActionState.radioOn
                  : MenuActionState.radioOff,
              callback: () =>
                  container.read(consoleDockSideProvider.notifier).state = edge,
            ),
        ],
      ),
      MenuSeparator(),
      MenuAction(
        title: tr(I18nKey.consoleResetLayout),
        callback: () => resetTerminalLayout(container),
      ),
    ],
  );
}

I18nKey _dockLabel(PaneEdge edge) => switch (edge) {
  PaneEdge.left => I18nKey.consoleDockLeft,
  PaneEdge.top => I18nKey.consoleDockTop,
  PaneEdge.right => I18nKey.consoleDockRight,
  PaneEdge.bottom => I18nKey.consoleDockBottom,
};

/// Restores the terminal to its preset bottom layout.
///
/// Every console surface -- in the panel or dragged into an editor group --
/// returns to the panel in its canonical order, and the panel docks at the
/// bottom again. A surface missing altogether is created anew, so this is also
/// the way back once every surface was dragged out and the panel disappeared.
/// The editor's own tabs stay where they are.
void resetTerminalLayout(ProviderContainer container) {
  _gatherConsoleSurfaces(container, createMissing: true);
  container.read(consoleDockSideProvider.notifier).state = PaneEdge.bottom;
}

/// Moves every console surface out of the editor area and into the panel.
///
/// Used when the window narrows to the mobile layout, where the terminal lives
/// in its bottom popup and grouping is unavailable. The dock side is kept.
void evacuateConsoleTabsToPanel(ProviderContainer container) {
  _gatherConsoleSurfaces(container, createMissing: false);
}

void _gatherConsoleSurfaces(
  ProviderContainer container, {
  required bool createMissing,
}) {
  final console = container.read(consoleTabbedViewControllerProvider);
  final surfaces = <ConsoleTabId, TabData>{
    for (final tab in console.tabs)
      if (tab.value case ConsoleTabValue(:final id)) id: tab,
  };
  var changed = false;
  // A group the evacuation empties is dropped by the layout notifier.
  for (final group in allEditorControllers(container)) {
    for (final tab in List.of(group.tabs)) {
      if (tab.value case ConsoleTabValue(:final id)) {
        group.removeTab(group.tabs.indexOf(tab));
        surfaces[id] = tab;
        changed = true;
      }
    }
  }
  if (createMissing) {
    final registry = container.read(dataRegistryProvider);
    final locale = container.read(activeLocaleProvider);
    final problemCount = container.read(consoleProblemCountProvider);
    for (final id in ConsoleTabId.values) {
      if (surfaces.containsKey(id)) continue;
      final label = _consoleLabel(
        id,
        (key) => translateFromRegistry(registry, locale, key),
        problemCount,
      );
      surfaces[id] = _consoleTab(id, label);
      changed = true;
    }
  }
  final ordered = [for (final id in ConsoleTabId.values) ?surfaces[id]];
  if (!changed && _sameTabs(console.tabs, ordered)) return;

  final selected = console.selectedTab;
  console
    ..removeTabs()
    ..addTabs(ordered);
  final keep = selected == null ? -1 : console.tabs.indexOf(selected);
  if (console.tabs.isNotEmpty) console.selectedIndex = keep < 0 ? 0 : keep;
}

bool _sameTabs(List<TabData> a, List<TabData> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}
