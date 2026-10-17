import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/problems_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/features/function_page.dart';
import 'package:pyrite_ide/features/function_page/problems_view.dart';
import 'package:pyrite_ide/shared/tabbed_view/tab_widget.dart';
import 'package:super_context_menu/super_context_menu.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

/// One of the console panel's fixed surfaces.
///
/// The id survives a drag, which is what lets a tab keep its identity while it
/// moves between the console strip and the editor strip.
enum ConsoleTabId { repl, log, terminal, problems }

/// Value carried by every console tab.
///
/// The console and the editor share one drag-and-drop system, so a tab has to
/// say which strip it was created for: [ConsolePage] reads it back to update
/// the Problems label, and it keeps a console tab distinguishable from a file
/// tab after the two strips have exchanged tabs.
@immutable
class ConsoleTabValue {
  const ConsoleTabValue(this.id);

  final ConsoleTabId id;
}

/// Total problem count, rendered as a suffix on the Problems tab.
final Provider<int> consoleProblemCountProvider = Provider<int>((ref) {
  var count = 0;
  for (final file in ref.watch(problemsProvider)) {
    count += file.errorCount + file.warningCount;
  }
  return count;
});

/// Appends the open-problem count to an already translated [baseLabel].
///
/// Takes the label rather than a ref so both a [WidgetRef] (the page) and a
/// provider's [Ref] (the controller) can build it.
String consoleProblemsLabel(String baseLabel, int count) {
  return count > 0 ? '$baseLabel ($count)' : baseLabel;
}

/// A controller holding the panel's default surfaces.
///
/// Exposed because the pane goes away once its last tab is dragged out, and
/// nothing else can repopulate a group that has been emptied: without this the
/// console would stay empty for the rest of the session. The labels are the
/// caller's because translating them needs a [Ref] (the provider) or a
/// [WidgetRef] (the reset entry), and this stays free of either.
TabbedViewController createConsoleController({
  required String logLabel,
  required String terminalLabel,
  required String problemsLabel,
}) {
  final controller = TabbedViewController([
    _consoleTab(
      text: 'REPL',
      icon: Icons.terminal,
      id: ConsoleTabId.repl,
      content: const ReplView(),
    ),
    _consoleTab(
      text: logLabel,
      icon: Icons.article_outlined,
      id: ConsoleTabId.log,
      content: const OutputLogView(),
    ),
    _consoleTab(
      text: terminalLabel,
      icon: Icons.terminal_outlined,
      id: ConsoleTabId.terminal,
      content: const DesktopTerminalView(),
    ),
    _consoleTab(
      text: problemsLabel,
      icon: Icons.report_problem_outlined,
      id: ConsoleTabId.problems,
      content: const ProblemsView(),
    ),
  ]);
  // A fresh controller selects nothing, which would leave the panel blank.
  controller.selectedIndex = 0;
  return controller;
}

/// The console's own tab strip.
///
/// It is a [TabbedViewController] exactly like the editor's, so both strips
/// render the same widget and a tab can be dragged from one to the other: the
/// native drag already moves tabs across controllers.
final StateProvider<TabbedViewController> consoleTabbedViewControllerProvider =
    StateProvider<TabbedViewController>(
      (ref) => createConsoleController(
        logLabel: translate(ref, I18nKey.bottomPanelLogTab),
        terminalLabel: translate(ref, I18nKey.bottomPanelTerminalTab),
        problemsLabel: consoleProblemsLabel(
          translate(ref, I18nKey.bottomPanelProblemsTab),
          ref.read(consoleProblemCountProvider),
        ),
      ),
    );

/// Brings the panel back after its tabs have all been dragged out.
void resetConsoleTabs(WidgetRef ref) {
  ref
      .read(consoleTabbedViewControllerProvider.notifier)
      .state = createConsoleController(
    logLabel: translateForWidget(ref, I18nKey.bottomPanelLogTab),
    terminalLabel: translateForWidget(ref, I18nKey.bottomPanelTerminalTab),
    problemsLabel: consoleProblemsLabel(
      translateForWidget(ref, I18nKey.bottomPanelProblemsTab),
      ref.read(consoleProblemCountProvider),
    ),
  );
}

TabData _consoleTab({
  required String text,
  required IconData icon,
  required ConsoleTabId id,
  required Widget content,
}) {
  return TabData(
    // The surfaces are permanent: closing one would leave no way back.
    closable: false,
    keepAlive: true,
    value: ConsoleTabValue(id),
    text: text,
    content: content,
    leading: (context, status) => Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// Rewrites the Problems tab label after the count changes, keeping selection.
///
/// The count rides on the translated label so a locale switch re-renders it
/// together with the tab text; there is no badge slot to write it to.
void updateConsoleProblemsLabel(WidgetRef ref, int count) {
  final controller = ref.read(consoleTabbedViewControllerProvider);
  final index = controller.tabs.indexWhere(
    (tab) =>
        tab.value is ConsoleTabValue &&
        (tab.value! as ConsoleTabValue).id == ConsoleTabId.problems,
  );
  if (index < 0) return;

  final tab = controller.tabs[index];
  final label = consoleProblemsLabel(
    translateForWidget(ref, I18nKey.bottomPanelProblemsTab),
    count,
  );
  if (tab.text == label) return;
  tab.text = label;

  // The same [TabData] instances are reused, so selection can be restored by
  // object rather than by index.
  final next = TabbedViewController(List<TabData>.from(controller.tabs));
  final selected = controller.selectedTab;
  if (selected != null) next.selectTab(selected);
  ref.read(consoleTabbedViewControllerProvider.notifier).state = next;
}

/// The surfaces' canonical order in the bottom console panel.
const List<ConsoleTabId> _consoleOrder = [
  ConsoleTabId.repl,
  ConsoleTabId.log,
  ConsoleTabId.terminal,
  ConsoleTabId.problems,
];

int _consoleRank(TabData tab) {
  final id = (tab.value as ConsoleTabValue?)?.id;
  final index = id == null ? -1 : _consoleOrder.indexOf(id);
  return index < 0 ? _consoleOrder.length : index;
}

/// Whether [tab] is one of the console panel's fixed surfaces.
bool isConsoleTab(TabData tab) => tab.value is ConsoleTabValue;

/// The right-click menu for a console surface -- the same system-native styling
/// as an editor tab, with the terminal-layout actions added.
///
/// Built in the console layer so the shared [TabWidget] stays free of any
/// feature-specific knowledge; it only forwards the menu builder.
Menu buildConsoleTabContextMenu(BuildContext context, int index) {
  final container = ProviderScope.containerOf(context);
  final registry = container.read(dataRegistryProvider);
  final locale = container.read(activeLocaleProvider);
  String tr(I18nKey key) => translateFromRegistry(registry, locale, key);

  return Menu(
    children: [
      MenuAction(
        title: tr(I18nKey.consoleResetLayout),
        callback: () => resetTerminalLayout(container),
      ),
    ],
  );
}

/// Restores the terminal to its preset bottom layout.
///
/// Every console tab -- wherever it sits, in the bottom panel or dragged into
/// an editor group -- returns to the bottom panel in its canonical order, and
/// the dock side resets to the bottom. The editor's own tab groups are left
/// exactly where they were.
void resetTerminalLayout(ProviderContainer container) {
  final console = container.read(consoleTabbedViewControllerProvider);
  final collected = <TabData>[];

  // Pull console tabs out of every editor group they were dragged into.
  for (final controller in allEditorControllers(container)) {
    for (final tab in List<TabData>.from(controller.tabs)) {
      if (isConsoleTab(tab)) {
        controller.removeTab(controller.tabs.indexOf(tab));
        collected.add(tab);
      }
    }
  }

  // Reassemble the panel: what it already held, then what came back, both in
  // the canonical surface order.
  final all = [...console.tabs, ...collected];
  all.sort((a, b) => _consoleRank(a).compareTo(_consoleRank(b)));
  final next = TabbedViewController(all);
  if (next.tabs.isNotEmpty) next.selectedIndex = 0;
  container.read(consoleTabbedViewControllerProvider.notifier).state = next;

  // The preset is the bottom dock, whatever side it was last dragged to.
  container.read(consoleDockSideProvider.notifier).state =
      ConsoleDockSide.bottom;
}

/// Moves every console tab out of the editor area and into the bottom panel.
///
/// Used when the window narrows to a mobile width, where grouping is unavailable
/// and the terminal lives in its bottom popup instead. The editor's own tabs
/// stay put; only the console surfaces relocate.
void evacuateConsoleTabsToPanel(ProviderContainer container) {
  final console = container.read(consoleTabbedViewControllerProvider);
  final collected = <TabData>[];
  for (final controller in allEditorControllers(container)) {
    for (final tab in List<TabData>.from(controller.tabs)) {
      if (isConsoleTab(tab)) {
        controller.removeTab(controller.tabs.indexOf(tab));
        collected.add(tab);
      }
    }
  }
  if (collected.isEmpty) return;
  final all = [...console.tabs, ...collected];
  all.sort((a, b) => _consoleRank(a).compareTo(_consoleRank(b)));
  final next = TabbedViewController(all);
  if (next.tabs.isNotEmpty) next.selectedIndex = 0;
  container.read(consoleTabbedViewControllerProvider.notifier).state = next;
}
