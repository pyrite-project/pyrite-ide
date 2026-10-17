import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
      container.read(consoleDockSideProvider.notifier).state =
          ConsoleDockSide.right;

      final console = container.read(consoleTabbedViewControllerProvider);
      final repl = _repl(container);

      // Drag the REPL surface into the editor area as its own group.
      expect(
        splitEditorArea(
          container,
          from: console,
          tab: repl,
          where: EditorSplit.right,
        ),
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
      expect(container.read(consoleDockSideProvider), ConsoleDockSide.bottom);
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
      splitEditorArea(
        container,
        from: console,
        tab: repl,
        where: EditorSplit.left,
      );

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
      container.read(consoleDockSideProvider.notifier).state =
          ConsoleDockSide.right;

      final console = container.read(consoleTabbedViewControllerProvider);
      final repl = _repl(container);
      splitEditorArea(
        container,
        from: console,
        tab: repl,
        where: EditorSplit.right,
      );
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
      expect(container.read(consoleDockSideProvider), ConsoleDockSide.right);
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

  group('buildConsoleTabContextMenu', () {
    testWidgets('offers the reset action and runs it', (tester) async {
      late BuildContext context;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Dock a console tab into the editor area so reset has something to do.
      container.read(consoleDockSideProvider.notifier).state =
          ConsoleDockSide.right;
      final console = container.read(consoleTabbedViewControllerProvider);
      final repl = _repl(container);
      splitEditorArea(
        container,
        from: console,
        tab: repl,
        where: EditorSplit.right,
      );

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

      final menu = buildConsoleTabContextMenu(context, 0);
      expect(menu.children, hasLength(1));
      final action = menu.children.first;
      expect(action, isA<MenuAction>());
      // The single action is the terminal-layout reset.
      (action as MenuAction).callback.call();

      expect(container.read(consoleDockSideProvider), ConsoleDockSide.bottom);
      expect(
        container.read(consoleTabbedViewControllerProvider).tabs,
        contains(repl),
      );
    });
  });
}
