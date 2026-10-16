import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/file_tab_title.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/features/function_page.dart';
import 'package:pyrite_ide/pages/editor/main.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

void main() {
  group('editor split geometry', () {
    test('side splits run horizontally, stacked ones vertically', () {
      expect(EditorSplit.left.axis, Axis.horizontal);
      expect(EditorSplit.right.axis, Axis.horizontal);
      expect(EditorSplit.top.axis, Axis.vertical);
      expect(EditorSplit.bottom.axis, Axis.vertical);
    });

    test('only the leading splits put the new group first', () {
      expect(EditorSplit.left.secondaryFirst, isTrue);
      expect(EditorSplit.top.secondaryFirst, isTrue);
      expect(EditorSplit.right.secondaryFirst, isFalse);
      expect(EditorSplit.bottom.secondaryFirst, isFalse);
    });
  });

  group('splitting a group', () {
    test('moves the tab into a new group nested in the tree', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      final second = TabData(text: 'second');
      primary.addTab(second);

      final split = splitEditorGroup(
        container,
        from: primary,
        target: primary,
        tab: second,
        where: EditorSplit.right,
      );

      expect(split, isTrue);
      expect(primary.tabs.any((tab) => tab.text == 'second'), isFalse);

      final layout = container.read(editorLayoutProvider) as SplitLayout;
      expect(layout.axis, Axis.horizontal);
      expect(layout.children, hasLength(2));
      // The primary keeps its role, so the tab it still holds survives the
      // controller swap the next tab operation performs.
      expect(layout.children.first, isA<PrimaryGroupLayout>());
      // `right` puts the existing group first and the new one after it.
      final created = layout.children[1] as GroupLayout;
      expect(created.controller.tabs.single.text, 'second');
      expect(
        container.read(focusedEditorGroupProvider),
        same(created.controller),
      );
    });

    test('the primary strip follows the swapped tab controller', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      primary.addTab(TabData(text: 'second'));
      splitEditorGroup(
        container,
        from: primary,
        target: primary,
        tab: primary.tabs[1],
        where: EditorSplit.right,
      );

      // Opening a file publishes a brand-new controller instance. The layout
      // holds the primary by role, so it must resolve to that new instance
      // instead of keeping a stale twin of the group alive.
      final swapped = TabbedViewController(primary.tabs);
      container.read(tabbedViewControllerProvider.notifier).state = swapped;

      expect(
        groupController(container, const PrimaryGroupLayout()),
        same(swapped),
      );
      expect(allEditorControllers(container), hasLength(2));
      expect(allEditorControllers(container).contains(primary), isFalse);
      expect(needsEditorLayoutRefresh(container), isFalse);
    });

    test('splits the group it landed on, so splits nest', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      primary.addTab(TabData(text: 'second'));
      splitEditorGroup(
        container,
        from: primary,
        target: primary,
        tab: primary.tabs[1],
        where: EditorSplit.right,
      );
      // The group split off the right edge, now holding the moved tab.
      final nested =
          ((container.read(editorLayoutProvider) as SplitLayout).children[1]
                  as GroupLayout)
              .controller;
      nested.addTab(TabData(text: 'nested'));

      // Splitting the *nested* group, not the root, is what makes a second
      // split appear inside the first.
      final split = splitEditorGroup(
        container,
        from: nested,
        target: nested,
        tab: nested.tabs.last,
        where: EditorSplit.bottom,
      );

      expect(split, isTrue);
      final inner =
          (container.read(editorLayoutProvider) as SplitLayout).children[1]
              as SplitLayout;
      expect(inner.axis, Axis.vertical);
      expect(inner.children, hasLength(2));
      expect(allEditorControllers(container), hasLength(3));
    });

    test('splits when the tab is dragged in from another group', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      primary.addTab(TabData(text: 'second'));
      splitEditorGroup(
        container,
        from: primary,
        target: primary,
        tab: primary.tabs[1],
        where: EditorSplit.right,
      );
      final nested =
          ((container.read(editorLayoutProvider) as SplitLayout).children[1]
                  as GroupLayout)
              .controller;
      // The primary now holds only the welcome page, so it needs a file tab to
      // drag across.
      final dragged = TabData(text: 'third');
      primary.addTab(dragged);

      // Dragging a tab that lives in the *root* group onto the nested group's
      // edge: the tab is not in the target, which used to make the drop a
      // no-op after the preview promised a split.
      final split = splitEditorGroup(
        container,
        from: primary,
        target: nested,
        tab: dragged,
        where: EditorSplit.bottom,
      );

      expect(split, isTrue);
      expect(primary.tabs.any((tab) => tab.text == 'third'), isFalse);
      // The welcome page stays: it is the editor's floor, so the primary group
      // is never emptied and never pruned.
      expect(primary.tabs.single.draggable, isFalse);
      expect(nested.tabs.single.text, 'second');

      final layout = container.read(editorLayoutProvider) as SplitLayout;
      expect(layout.axis, Axis.horizontal);
      // The nested split is now the root's second child, so it can be split
      // again inside itself.
      expect((layout.children[1] as SplitLayout).axis, Axis.vertical);
      expect(allEditorControllers(container), hasLength(3));
      expect(allEditorControllers(container).contains(primary), isTrue);
    });

    test('the preview is only promised when the drop can honour it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      final only = primary.tabs.single;

      expect(
        canSplitEditorGroup(from: primary, target: primary, tab: only),
        isFalse,
        reason: 'splitting a group\'s own last tab would be undone by pruning',
      );

      primary.addTab(TabData(text: 'second'));
      expect(
        canSplitEditorGroup(from: primary, target: primary, tab: only),
        isTrue,
      );
    });

    test('brings the primary back when it gains a tab while away', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      // The primary can no longer be emptied -- the welcome page is pinned --
      // so this state is reached by a group the primary is not part of.
      container.read(editorLayoutProvider.notifier).state = GroupLayout(
        TabbedViewController([TabData(text: 'other')]),
      );

      // A new file opens in the primary, so the primary has to come back into
      // the tree or the file would open in a strip nothing renders.
      primary.addTab(TabData(text: 'new'));
      expect(needsEditorLayoutRefresh(container), isTrue);

      final layout = refreshEditorLayout(container);
      container.read(editorLayoutProvider.notifier).state = layout;
      expect(layout, isA<SplitLayout>());
      expect((layout as SplitLayout).axis, Axis.horizontal);
      expect(layout.children.first, isA<PrimaryGroupLayout>());
      expect(
        allEditorControllers(container).contains(primary),
        isTrue,
        reason: 'exactly one leaf is bound to the primary controller',
      );
      expect(allEditorControllers(container), hasLength(2));
    });

    test('closes the group whose last tab was closed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      final moved = TabData(text: 'second');
      primary.addTab(moved);
      splitEditorGroup(
        container,
        from: primary,
        target: primary,
        tab: moved,
        where: EditorSplit.right,
      );
      final secondary = allEditorControllers(container)[1];

      // Closing is not a move, so nothing pruned on its behalf. The frame hook
      // in [Editor] catches it through this flag.
      secondary.removeTab(0);
      expect(needsEditorLayoutRefresh(container), isTrue);
      // What the frame hook in [Editor] writes back after the build.
      container.read(editorLayoutProvider.notifier).state = refreshEditorLayout(
        container,
      );
      expect(container.read(editorLayoutProvider), isA<PrimaryGroupLayout>());
      expect(allEditorControllers(container), hasLength(1));
    });

    test('keeps the last tab of a group in place', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      final only = primary.tabs.single;

      final split = splitEditorGroup(
        container,
        from: primary,
        target: primary,
        tab: only,
        where: EditorSplit.bottom,
      );

      expect(split, isFalse);
      expect(container.read(editorLayoutProvider), isA<PrimaryGroupLayout>());
      expect(primary.tabs, orderedEquals([only]));
    });

    test('prunes a group that lost its last tab', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      final moved = TabData(text: 'second');
      primary.addTab(moved);
      splitEditorGroup(
        container,
        from: primary,
        target: primary,
        tab: moved,
        where: EditorSplit.right,
      );
      expect(container.read(editorLayoutProvider), isA<SplitLayout>());

      // Dragging the only tab of the second group back empties it, and the
      // group goes away with it.
      final secondary = allEditorControllers(container)[1];
      final back = moveTabToEditorGroup(
        container,
        from: secondary,
        tab: secondary.tabs.single,
        into: primary,
      );

      expect(back, isTrue);
      expect(container.read(editorLayoutProvider), isA<PrimaryGroupLayout>());
      expect(allEditorControllers(container), hasLength(1));
    });

    test('a new file opens in the group that has focus', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      primary.addTab(TabData(text: 'second'));
      splitEditorGroup(
        container,
        from: primary,
        target: primary,
        tab: primary.tabs[1],
        where: EditorSplit.right,
      );
      final focused = allEditorControllers(container)[1];
      container.read(focusedEditorGroupProvider.notifier).state = focused;

      // What the tab notifier does after building a tab on the primary group.
      final created = TabData(text: 'new');
      primary.addTab(created);
      final moved = moveTabToFocusedGroup(
        container,
        from: primary,
        tab: created,
      );

      expect(moved, isTrue);
      expect(primary.tabs.contains(created), isFalse);
      expect(focused.tabs.last.text, 'new');
      expect(focused.selectedTab, same(created));
      // The group the tab left keeps the tab it was showing.
      expect(primary.selectedTab, isNotNull);
    });

    test('a new file opens in the primary group when nothing is focused', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      final created = TabData(text: 'new');
      primary.addTab(created);

      final moved = moveTabToFocusedGroup(
        container,
        from: primary,
        tab: created,
      );

      expect(moved, isFalse);
      expect(primary.tabs.contains(created), isTrue);
    });

    test('the welcome page is pinned: it can never be moved or split', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      final welcome = primary.tabs.first;
      // The editor's floor is unclosable and, now, undraggable.
      expect(welcome.closable, isFalse);
      expect(welcome.draggable, isFalse);
      expect(canTabLeaveGroup(welcome), isFalse);

      final other = TabData(text: 'other');
      primary.addTab(other);
      splitEditorGroup(
        container,
        from: primary,
        target: primary,
        tab: other,
        where: EditorSplit.right,
      );
      final second = allEditorControllers(container)[1];

      // Neither a split nor a move will take it out of the primary group.
      expect(
        splitEditorGroup(
          container,
          from: primary,
          target: primary,
          tab: welcome,
          where: EditorSplit.bottom,
        ),
        isFalse,
      );
      expect(
        moveTabToEditorGroup(
          container,
          from: primary,
          tab: welcome,
          into: second,
        ),
        isFalse,
      );
      expect(primary.tabs.first, same(welcome));
      expect(container.read(editorLayoutProvider), isA<SplitLayout>());
    });

    test('a tab from a group outside the tree can split an editor group', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      // The docked console panel is a group the editor layout does not
      // contain, which is where a dragged-out tab comes from.
      final console = TabbedViewController([TabData(text: 'REPL')]);
      addTearDown(console.dispose);

      final split = splitEditorGroup(
        container,
        from: console,
        target: primary,
        tab: console.tabs.single,
        where: EditorSplit.right,
      );

      expect(split, isTrue);
      expect(console.tabs, isEmpty);
      expect(container.read(focusedEditorGroupProvider), isNotNull);
      final layout = container.read(editorLayoutProvider) as SplitLayout;
      expect(layout.axis, Axis.horizontal);
      final created = layout.children[1] as GroupLayout;
      expect(created.controller.tabs.single.text, 'REPL');
    });

    test('the last group survives empty, so the editor always has a strip', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final primary = container.read(tabbedViewControllerProvider);
      primary.removeTab(0);

      final pruned = pruneEditorGroups(container, GroupLayout(primary));
      expect(pruned, isA<GroupLayout>());
      expect((pruned as GroupLayout).controller, same(primary));
      // Nothing to collapse against, so no refresh is scheduled.
      expect(needsEditorLayoutRefresh(container), isFalse);
    });

    testWidgets('closing a group last tab removes the group from the screen', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final primary = container.read(tabbedViewControllerProvider);
      primary.addTab(TabData(text: 'second'));
      splitEditorGroup(
        container,
        from: primary,
        target: primary,
        tab: primary.tabs[1],
        where: EditorSplit.right,
      );
      final secondary = allEditorControllers(container)[1];

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => buildShadcnLayer(context, const Editor()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(container.read(editorLayoutProvider), isA<SplitLayout>());
      // The action bar belongs to the editor area, not to a group: two groups
      // still share the one bar.
      expect(find.byType(EditorGroup), findsNWidgets(2));
      expect(find.byIcon(Icons.save_outlined), findsOneWidget);

      // Closing is what empties the group: it notifies the group controller,
      // never the layout provider, which is why the strip used to survive.
      secondary.removeTab(0);
      await tester.pump();
      await tester.pump();

      expect(container.read(editorLayoutProvider), isA<PrimaryGroupLayout>());
      expect(allEditorControllers(container), hasLength(1));
      // Only one toolbar is left on screen -- the emptied group is gone.
      expect(find.byType(EditorGroup), findsOneWidget);
    });
  });

  test('same-named files in different groups are disambiguated', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final primary = container.read(tabbedViewControllerProvider);
    final parked = TabData(text: 'parked');
    primary.addTab(parked);
    splitEditorGroup(
      container,
      from: primary,
      target: primary,
      tab: parked,
      where: EditorSplit.right,
    );
    final second = allEditorControllers(container)[1];

    // Same basename, different directories -- one tab per group. Refreshing a
    // single group's tabs is what left both of these reading `README.md`.
    final client = TabData(
      text: 'README.md',
      value: TabDataValue(type: 'file', filePath: '/proj/client/README.md'),
    );
    final server = TabData(
      text: 'README.md',
      value: TabDataValue(type: 'file', filePath: '/proj/server/README.md'),
    );
    primary.addTab(client);
    second.addTab(server);

    refreshFileTabTitles(allEditorTabs(container));

    expect(client.text, 'client/README.md');
    expect(server.text, 'server/README.md');
  });

}
