// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';
import 'package:pyrite_ide/shared/tabbed_view/tab_close_actions.dart';
import 'package:tabbed_view/src/internal/tabbed_view_provider.dart';
import 'package:tabbed_view/src/unselected_tab_buttons_behavior.dart';
import 'package:tabbed_view/src/tab_data.dart';
import 'package:tabbed_view/src/tabbed_view_controller.dart';

TabData tab(String name) => TabData(text: name);

/// A minimal provider for [closeTabs]: only `controller` and the close path are
/// exercised, so every other field is left at its inert default.
TabbedViewProvider _provider(TabbedViewController controller) =>
    TabbedViewProvider(
      controller: controller,
      contentBuilder: null,
      tabReorderEnabled: false,
      contentClip: false,
      unselectedTabButtonsBehavior: UnselectedTabButtonsBehavior.allDisabled,
      closeButtonTooltip: null,
      tabsAreaButtonsBuilder: null,
      tabRemoveInterceptor: null,
      onTabSecondaryTap: null,
      onTabDrag: (int? index) {},
      draggingTabIndex: null,
      onDraggableBuild: null,
      canDrop: null,
      onBeforeDropAccept: null,
      dragScope: null,
      trailing: null,
    );

void main() {
  group('otherTabs', () {
    test('drops the kept tab', () {
      final tabs = [tab('a'), tab('b'), tab('c')];
      expect(otherTabs(tabs, tabs[1]).map((t) => t.text), ['a', 'c']);
    });

    test('keeps order', () {
      final tabs = [tab('a'), tab('b'), tab('c'), tab('d')];
      expect(otherTabs(tabs, tabs[0]).map((t) => t.text), ['b', 'c', 'd']);
    });

    test('is empty when the only tab is the kept one', () {
      final tabs = [tab('a')];
      expect(otherTabs(tabs, tabs.first), isEmpty);
    });

    test('a tab that is merely equal is not treated as the kept one', () {
      // TabData does not override ==, so identity is the only thing that can
      // tell two same-named tabs apart.
      final kept = tab('main.py');
      final other = tab('main.py');
      expect(otherTabs([kept, other], kept), [other]);
    });
  });

  group('tabsToTheRightOf', () {
    final tabs = [tab('a'), tab('b'), tab('c'), tab('d')];

    test('takes everything after the index', () {
      expect(tabsToTheRightOf(tabs, 1).map((t) => t.text), ['c', 'd']);
    });

    test('is empty for the last tab', () {
      expect(tabsToTheRightOf(tabs, 3), isEmpty);
    });

    test('is empty for an index past the end', () {
      expect(tabsToTheRightOf(tabs, 9), isEmpty);
    });

    test('takes everything but the first tab for index zero', () {
      expect(tabsToTheRightOf(tabs, 0).map((t) => t.text), ['b', 'c', 'd']);
    });
  });

  group('closeTabs', () {
    testWidgets('a non-closable tab survives a close-all', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        ProviderScope(
          child: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final container = ProviderScope.containerOf(context);
      final controller = container.read(tabbedViewControllerProvider);
      // The welcome page is pinned: closable:false, like the real floor tab.
      final welcome = TabData(
        closable: false,
        value: TabDataValue(type: 'page', filePath: 'welcome'),
        text: 'Welcome',
      );
      final normal = TabData(text: 'a.py');
      controller.addTab(welcome);
      controller.addTab(normal);

      final provider = _provider(controller);
      // "Close all" hands every tab over; the pinned one must be skipped.
      await closeTabs(context, provider, [welcome, normal]);

      expect(controller.tabs, isNot(contains(normal)));
      expect(controller.tabs, contains(welcome));
    });

    testWidgets('a document closed in a split group is released', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        ProviderScope(
          child: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final container = ProviderScope.containerOf(context);
      final primary = container.read(tabbedViewControllerProvider);
      const path = '/nonexistent/split_group_close.py';
      ensurePendingFileProviders(path);
      addTearDown(() => releasePendingFileProviders(path));
      final document = TabData(
        text: 'split_group_close.py',
        value: TabDataValue(type: 'file', filePath: path),
      );
      primary.addTab(document);
      final keep = TabData(text: 'keep');
      primary.addTab(keep);
      container
          .read(editorLayoutProvider.notifier)
          .splitGroup(
            from: primary,
            target: primary,
            tab: document,
            where: PaneEdge.right,
          );
      final split = allEditorControllers(container)[1];
      split.addTab(TabData(text: 'other'));

      // Closed from the split group's own strip, not the primary's.
      await closeTabs(context, _provider(split), [document]);

      expect(split.tabs, isNot(contains(document)));
      // The editor notifier saw the close: what it holds per path is gone.
      expect(pendingUploadProviderMap.containsKey(path), isFalse);
      expect(pendingDownloadProviderMap.containsKey(path), isFalse);
    });
  });
}
