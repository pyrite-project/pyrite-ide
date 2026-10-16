import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/problems_provider.dart';
import 'package:pyrite_ide/features/function_page.dart';
import 'package:pyrite_ide/features/function_page/problems_view.dart';
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

/// The console's own tab strip.
///
/// It is a [TabbedViewController] exactly like the editor's, so both strips
/// render the same widget and a tab can be dragged from one to the other: the
/// native drag already moves tabs across controllers.
final StateProvider<TabbedViewController> consoleTabbedViewControllerProvider =
    StateProvider<TabbedViewController>((ref) {
      final controller = TabbedViewController([
        _consoleTab(
          text: 'REPL',
          icon: Icons.terminal,
          id: ConsoleTabId.repl,
          content: const ReplView(),
        ),
        _consoleTab(
          text: translate(ref, I18nKey.bottomPanelLogTab),
          icon: Icons.article_outlined,
          id: ConsoleTabId.log,
          content: const OutputLogView(),
        ),
        _consoleTab(
          text: translate(ref, I18nKey.bottomPanelTerminalTab),
          icon: Icons.terminal_outlined,
          id: ConsoleTabId.terminal,
          content: const DesktopTerminalView(),
        ),
        _consoleTab(
          text: consoleProblemsLabel(
            translate(ref, I18nKey.bottomPanelProblemsTab),
            ref.read(consoleProblemCountProvider),
          ),
          icon: Icons.report_problem_outlined,
          id: ConsoleTabId.problems,
          content: const ProblemsView(),
        ),
      ]);
      // A fresh controller selects nothing, which would leave the panel blank.
      controller.selectedIndex = 0;
      return controller;
    });

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
