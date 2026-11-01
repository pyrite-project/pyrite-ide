import 'package:pyrite_ide/features/function_page/console_surface_actions.dart';
import 'package:pyrite_ide/features/function_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/features/function_page/console_tabs.dart';
import 'package:super_context_menu/super_context_menu.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

TabData _repl(ProviderContainer container) {
  final console = container.read(consoleTabbedViewControllerProvider);
  return console.tabs.firstWhere(
    (tab) => (tab.value! as ConsoleTabValue).id == ConsoleTabId.repl,
  );
}

void main() {
  group('resetTerminalLayout', () {
    test('returns a docked-away console tab to the bottom panel', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // The user dragged the console to the right; the reset must restore bottom.
      container.read(consoleDockSideProvider.notifier).state = PaneEdge.right;

      final console = container.read(consoleTabbedViewControllerProvider);
      final repl = _repl(container);

      // Drag the REPL surface into the editor area as its own group.
      expect(
        container
            .read(editorLayoutProvider.notifier)
            .splitArea(from: console, tab: repl, where: PaneEdge.right),
        isTrue,
      );
      expect(console.tabs, hasLength(3));
      expect(
        allEditorControllers(container).any((c) => c.tabs.contains(repl)),
        isTrue,
      );

      resetTerminalLayout(container);

      // The REPL is back in the panel...
      final after = container.read(consoleTabbedViewControllerProvider);
      expect(after.tabs, contains(repl));
      // ...in its canonical order (REPL first)...
      expect(
        (after.tabs.first.value! as ConsoleTabValue).id,
        ConsoleTabId.repl,
      );
      // ...the dock side resets to the bottom...
      expect(container.read(consoleDockSideProvider), PaneEdge.bottom);
      // ...and no editor group keeps a console tab.
      expect(
        allEditorControllers(container).expand((c) => c.tabs).any(isConsoleTab),
        isFalse,
      );
    });

    test('leaves the editor own tabs untouched', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final primary = container.read(tabbedViewControllerProvider);
      primary.addTab(TabData(text: 'keep.py'));
      final console = container.read(consoleTabbedViewControllerProvider);
      final repl = _repl(container);
      container
          .read(editorLayoutProvider.notifier)
          .splitArea(from: console, tab: repl, where: PaneEdge.left);

      resetTerminalLayout(container);

      // The file tab the editor already held is still there, ungrouped-from nothing.
      expect(
        allEditorControllers(
          container,
        ).expand((c) => c.tabs).map((t) => t.text),
        contains('keep.py'),
      );
    });
  });

  group('evacuateConsoleTabsToPanel', () {
    test('moves console tabs out of the editor area, keeps the dock side', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // A dock side the user chose; evacuation must not override it.
      container.read(consoleDockSideProvider.notifier).state = PaneEdge.right;

      final console = container.read(consoleTabbedViewControllerProvider);
      final repl = _repl(container);
      container
          .read(editorLayoutProvider.notifier)
          .splitArea(from: console, tab: repl, where: PaneEdge.right);
      expect(
        allEditorControllers(container).expand((c) => c.tabs).any(isConsoleTab),
        isTrue,
      );

      evacuateConsoleTabsToPanel(container);

      expect(
        container.read(consoleTabbedViewControllerProvider).tabs,
        contains(repl),
      );
      expect(
        allEditorControllers(container).expand((c) => c.tabs).any(isConsoleTab),
        isFalse,
      );
      // Dock side is left as the user set it, not forced to bottom.
      expect(container.read(consoleDockSideProvider), PaneEdge.right);
    });

    test('is a no-op when the editor area holds no console tab', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final console = container.read(consoleTabbedViewControllerProvider);
      final before = List<TabData>.from(console.tabs);
      evacuateConsoleTabsToPanel(container);

      // The panel keeps exactly its original surfaces, in their order.
      expect(
        container.read(consoleTabbedViewControllerProvider).tabs,
        orderedEquals(before),
      );
    });
  });

  group('reset', () {
    test('recreates surfaces that went missing, in canonical order', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final console = container.read(consoleTabbedViewControllerProvider);
      // Every surface dragged out and lost: the panel has nothing left.
      console.removeTabs();

      resetTerminalLayout(container);

      expect(
        console.tabs.map((tab) => (tab.value! as ConsoleTabValue).id),
        ConsoleTabId.values,
      );
      expect(console.selectedIndex, 0);
      // The panel keeps its one controller through the reset.
      expect(
        container.read(consoleTabbedViewControllerProvider),
        same(console),
      );
    });

    test('keeps the surface the user was looking at selected', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final console = container.read(consoleTabbedViewControllerProvider);
      final repl = _repl(container);
      container
          .read(editorLayoutProvider.notifier)
          .splitArea(from: console, tab: repl, where: PaneEdge.right);
      final problems = console.tabs.last;
      console.selectedIndex = console.tabs.indexOf(problems);

      resetTerminalLayout(container);

      expect(console.selectedTab, same(problems));
    });
  });

  group('the Problems label', () {
    test('follows the count while the tab sits in an editor group', () {
      final count = StateProvider<int>((ref) => 0);
      final container = ProviderContainer(
        overrides: [
          consoleProblemCountProvider.overrideWith((ref) => ref.watch(count)),
        ],
      );
      addTearDown(container.dispose);
      final console = container.read(consoleTabbedViewControllerProvider);
      final problems = console.tabs.firstWhere(
        (tab) => (tab.value! as ConsoleTabValue).id == ConsoleTabId.problems,
      );
      container
          .read(editorLayoutProvider.notifier)
          .splitArea(from: console, tab: problems, where: PaneEdge.right);
      expect(problems.text, isNot(contains('(')));

      container.read(count.notifier).state = 3;
      container.read(consoleProblemCountProvider);

      expect(problems.text, endsWith('(3)'));
    });
  });

  group('surface buttons', () {
    testWidgets('the strip shows the selected surface\'s own buttons', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ConsolePage())),
        ),
      );
      final console = container.read(consoleTabbedViewControllerProvider);

      expect(find.byType(ReplSurfaceActions), findsOneWidget);

      console.selectedIndex = ConsoleTabId.log.index;
      await tester.pump();
      expect(find.byType(ReplSurfaceActions), findsNothing);
      expect(find.byType(LogSurfaceActions), findsOneWidget);

      console.selectedIndex = ConsoleTabId.problems.index;
      await tester.pump();
      expect(find.byType(ProblemsSurfaceActions), findsOneWidget);

      // The terminal brings no buttons of its own.
      final context = tester.element(find.byType(ConsolePage));
      expect(
        const ConsoleTabValue(ConsoleTabId.terminal).buildTabActions(context),
        isNull,
      );
    });
  });

  group('buildConsoleTabMenu', () {
    testWidgets('offers the panel position and the reset', (tester) async {
      late BuildContext context;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Dock a console tab into the editor area so reset has something to do.
      container.read(consoleDockSideProvider.notifier).state = PaneEdge.right;
      final console = container.read(consoleTabbedViewControllerProvider);
      final repl = _repl(container);
      container
          .read(editorLayoutProvider.notifier)
          .splitArea(from: console, tab: repl, where: PaneEdge.right);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (ctx) {
                context = ctx;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final menu = buildConsoleTabMenu(context);
      final position = menu.children.first as Menu;
      final sides = position.children.cast<MenuAction>();
      expect(sides, hasLength(PaneEdge.values.length));
      // The current side is the one marked.
      expect(
        sides.indexWhere((side) => side.state == MenuActionState.radioOn),
        PaneEdge.right.index,
      );
      sides.first.callback();
      expect(container.read(consoleDockSideProvider), PaneEdge.left);

      // The last entry is the terminal-layout reset.
      (menu.children.last as MenuAction).callback();
      expect(container.read(consoleDockSideProvider), PaneEdge.bottom);
      expect(
        container.read(consoleTabbedViewControllerProvider).tabs,
        contains(repl),
      );
    });
  });
}
