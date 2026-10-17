import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/file_tab_title.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:pyrite_ide/features/function_page.dart';
import 'package:pyrite_ide/pages/editor/main.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

/// The layout notifier of a fresh container, and its primary group.
({
  ProviderContainer container,
  EditorLayoutNotifier layout,
  TabbedViewController primary,
})
_editor() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return (
    container: container,
    layout: container.read(editorLayoutProvider.notifier),
    primary: container.read(tabbedViewControllerProvider),
  );
}

TabData _fileTab(String path, {bool isSaved = true}) => TabData(
  text: path.split('/').last,
  value: TabDataValue(type: 'file', filePath: path, isSaved: isSaved),
);

void main() {
  group('editor split geometry', () {
    test('side splits run horizontally, stacked ones vertically', () {
      expect(PaneEdge.left.axis, Axis.horizontal);
      expect(PaneEdge.right.axis, Axis.horizontal);
      expect(PaneEdge.top.axis, Axis.vertical);
      expect(PaneEdge.bottom.axis, Axis.vertical);
    });

    test('only the leading splits put the new group first', () {
      expect(PaneEdge.left.isLeading, isTrue);
      expect(PaneEdge.top.isLeading, isTrue);
      expect(PaneEdge.right.isLeading, isFalse);
      expect(PaneEdge.bottom.isLeading, isFalse);
    });
  });

  group('splitting a group', () {
    test('moves the tab into a new group nested in the tree', () {
      final editor = _editor();
      final second = TabData(text: 'second');
      editor.primary.addTab(second);

      final split = editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: second,
        where: PaneEdge.right,
      );

      expect(split, isTrue);
      expect(editor.primary.tabs, isNot(contains(second)));
      final layout = editor.container.read(editorLayoutProvider) as SplitLayout;
      expect(layout.axis, Axis.horizontal);
      // `right` puts the existing group first and the new one after it.
      expect(layout.children.first, GroupLayout(editor.primary));
      final created = (layout.children[1] as GroupLayout).controller;
      expect(created.tabs.single, same(second));
      expect(editor.container.read(focusedEditorGroupProvider), same(created));
    });

    test('every group keeps one controller for the whole session', () {
      final editor = _editor();
      final a = _fileTab('/proj/a.py');
      final b = _fileTab('/proj/b.py');
      editor.primary
        ..addTab(a)
        ..addTab(b);
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: b,
        where: PaneEdge.right,
      );
      final notifier = editor.container.read(
        tabbedViewControllerProvider.notifier,
      );

      // Opening, focusing and closing tabs change the groups in place: the
      // provider and the layout keep the very controllers they started with.
      notifier.openTab(TabData(text: 'opened'));
      notifier.focusTab(a);
      editor.primary.removeTab(editor.primary.tabs.indexOf(a));
      notifier.afterTabClose(a);

      expect(
        editor.container.read(tabbedViewControllerProvider),
        same(editor.primary),
      );
      expect(
        allEditorControllers(editor.container).first,
        same(editor.primary),
      );
    });

    test('splits the group it landed on, so splits nest', () {
      final editor = _editor();
      editor.primary.addTab(TabData(text: 'second'));
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: editor.primary.tabs[1],
        where: PaneEdge.right,
      );
      final nested = allEditorControllers(editor.container)[1];
      nested.addTab(TabData(text: 'nested'));

      // Splitting the *nested* group, not the root, is what makes a second
      // split appear inside the first.
      final split = editor.layout.splitGroup(
        from: nested,
        target: nested,
        tab: nested.tabs.last,
        where: PaneEdge.bottom,
      );

      expect(split, isTrue);
      final inner =
          (editor.container.read(editorLayoutProvider) as SplitLayout)
                  .children[1]
              as SplitLayout;
      expect(inner.axis, Axis.vertical);
      expect(inner.children, hasLength(2));
      expect(allEditorControllers(editor.container), hasLength(3));
    });

    test('splits when the tab is dragged in from another group', () {
      final editor = _editor();
      editor.primary.addTab(TabData(text: 'second'));
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: editor.primary.tabs[1],
        where: PaneEdge.right,
      );
      final nested = allEditorControllers(editor.container)[1];
      final dragged = TabData(text: 'third');
      editor.primary.addTab(dragged);

      // A tab from the root group dropped on the nested group's edge: the tab
      // is not in the target, and the split still happens.
      final split = editor.layout.splitGroup(
        from: editor.primary,
        target: nested,
        tab: dragged,
        where: PaneEdge.bottom,
      );

      expect(split, isTrue);
      expect(editor.primary.tabs, isNot(contains(dragged)));
      // The welcome page stays: it is the editor's floor, so the primary group
      // is never emptied and never pruned.
      expect(editor.primary.tabs.single.draggable, isFalse);
      expect(nested.tabs.single.text, 'second');
      final layout = editor.container.read(editorLayoutProvider) as SplitLayout;
      expect((layout.children[1] as SplitLayout).axis, Axis.vertical);
      expect(allEditorControllers(editor.container), hasLength(3));
    });

    test('the preview is only promised when the drop can honour it', () {
      final editor = _editor();
      final welcome = editor.primary.tabs.single;
      final a = TabData(text: 'a');
      editor.primary.addTab(a);

      // The welcome page is pinned, however many tabs share its group.
      expect(
        editor.layout.canSplitGroup(
          from: editor.primary,
          target: editor.primary,
          tab: welcome,
        ),
        isFalse,
      );
      expect(
        editor.layout.canSplitGroup(
          from: editor.primary,
          target: editor.primary,
          tab: a,
        ),
        isTrue,
      );

      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: a,
        where: PaneEdge.right,
      );
      final created = allEditorControllers(editor.container)[1];
      expect(
        editor.layout.canSplitGroup(from: created, target: created, tab: a),
        isFalse,
        reason: 'splitting a group\'s own last tab would be undone by pruning',
      );
      created.addTab(TabData(text: 'b'));
      expect(
        editor.layout.canSplitGroup(from: created, target: created, tab: a),
        isTrue,
      );
    });

    test('refuses a tab its source no longer holds', () {
      final editor = _editor();
      editor.primary.addTab(TabData(text: 'second'));
      final gone = TabData(text: 'gone');

      // The drag captured the source when it started; the tab may have closed
      // since. `removeTab` validates its index, so a stale source must be
      // refused, not thrown at.
      expect(
        editor.layout.splitGroup(
          from: editor.primary,
          target: editor.primary,
          tab: gone,
          where: PaneEdge.bottom,
        ),
        isFalse,
      );
      expect(
        editor.container.read(editorLayoutProvider),
        GroupLayout(editor.primary),
      );
      expect(editor.primary.tabs, hasLength(2));
    });

    test('a tab split into a new group can be selected there', () {
      for (final splitArea in [false, true]) {
        final editor = _editor();
        final moved = TabData(text: 'moved');
        editor.primary
          ..addTab(TabData(text: 'stays'))
          ..addTab(moved);

        if (splitArea) {
          editor.layout.splitArea(
            from: editor.primary,
            tab: moved,
            where: PaneEdge.right,
          );
        } else {
          editor.layout.splitGroup(
            from: editor.primary,
            target: editor.primary,
            tab: moved,
            where: PaneEdge.right,
          );
        }
        final created = editor.container.read(activeEditorControllerProvider);

        // Reopening the tab's file focuses it with `selectTab`, which reads the
        // index the tab stores: it must point into the new group, not be the
        // -1 its old group left behind.
        expect(() => created.selectTab(moved), returnsNormally);
        expect(created.selectedTab, same(moved));
      }
    });

    test('the primary group is never left out while it holds tabs', () {
      final editor = _editor();
      // A tree without the primary: only a damaged restore produces one.
      editor.layout.replace(
        GroupLayout(TabbedViewController([TabData(text: 'other')])),
      );

      final layout = editor.container.read(editorLayoutProvider);
      expect(layout, isA<SplitLayout>());
      expect(
        (layout as SplitLayout).children.first,
        GroupLayout(editor.primary),
      );
      expect(allEditorControllers(editor.container), hasLength(2));
    });

    test('closes the group whose last tab was closed', () {
      final editor = _editor();
      final moved = TabData(text: 'second');
      editor.primary.addTab(moved);
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: moved,
        where: PaneEdge.right,
      );
      final secondary = allEditorControllers(editor.container)[1];
      editor.container.read(focusedEditorGroupProvider.notifier).state =
          secondary;

      // Closing goes through the group's own controller, never through the
      // layout -- the notifier follows the groups to notice.
      secondary.removeTab(0);

      expect(
        editor.container.read(editorLayoutProvider),
        GroupLayout(editor.primary),
      );
      // The focus does not outlive the group.
      expect(editor.container.read(focusedEditorGroupProvider), isNull);
      expect(
        editor.container.read(activeEditorControllerProvider),
        same(editor.primary),
      );
    });

    test('keeps the last tab of a group in place', () {
      final editor = _editor();
      final only = editor.primary.tabs.single;

      final split = editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: only,
        where: PaneEdge.bottom,
      );

      expect(split, isFalse);
      expect(
        editor.container.read(editorLayoutProvider),
        GroupLayout(editor.primary),
      );
      expect(editor.primary.tabs, orderedEquals([only]));
    });

    test('prunes a group that lost its last tab', () {
      final editor = _editor();
      final moved = TabData(text: 'second');
      editor.primary.addTab(moved);
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: moved,
        where: PaneEdge.right,
      );

      // Dragging the only tab of the second group back empties it, and the
      // group goes away with it.
      final secondary = allEditorControllers(editor.container)[1];
      final back = editor.layout.moveTab(
        from: secondary,
        tab: moved,
        into: editor.primary,
      );

      expect(back, isTrue);
      expect(
        editor.container.read(editorLayoutProvider),
        GroupLayout(editor.primary),
      );
      expect(editor.primary.selectedTab, same(moved));
    });

    test('a new tab opens in the group that has focus', () {
      final editor = _editor();
      final parked = TabData(text: 'parked');
      editor.primary.addTab(parked);
      editor.primary.selectedIndex = 1;
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: parked,
        where: PaneEdge.right,
      );
      final focused = allEditorControllers(editor.container)[1];
      final primarySelection = editor.primary.selectedTab;

      final created = TabData(text: 'new');
      editor.container
          .read(tabbedViewControllerProvider.notifier)
          .openTab(created);

      expect(focused.tabs.last, same(created));
      expect(focused.selectedTab, same(created));
      // The group the tab did not open in keeps what it was showing.
      expect(editor.primary.tabs, isNot(contains(created)));
      expect(editor.primary.selectedTab, same(primarySelection));
    });

    test('a new tab opens in the primary group when nothing is focused', () {
      final editor = _editor();
      final created = TabData(text: 'new');

      editor.container
          .read(tabbedViewControllerProvider.notifier)
          .openTab(created);

      expect(editor.primary.tabs.last, same(created));
      expect(editor.primary.selectedTab, same(created));
    });

    test('focusing a tab focuses the group holding it', () {
      final editor = _editor();
      final a = TabData(text: 'a');
      final b = TabData(text: 'b');
      editor.primary
        ..addTab(a)
        ..addTab(b);
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: b,
        where: PaneEdge.right,
      );
      final notifier = editor.container.read(
        tabbedViewControllerProvider.notifier,
      );

      expect(notifier.focusTab(a), isTrue);
      expect(editor.primary.selectedTab, same(a));
      expect(
        editor.container.read(activeEditorControllerProvider),
        same(editor.primary),
      );
      expect(notifier.focusTab(TabData(text: 'closed')), isFalse);
    });

    test('the welcome page is pinned: it can never be moved or split', () {
      final editor = _editor();
      final welcome = editor.primary.tabs.first;
      expect(welcome.closable, isFalse);
      expect(welcome.draggable, isFalse);
      expect(canTabLeaveGroup(welcome), isFalse);

      final other = TabData(text: 'other');
      editor.primary.addTab(other);
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: other,
        where: PaneEdge.right,
      );
      final second = allEditorControllers(editor.container)[1];

      expect(
        editor.layout.splitGroup(
          from: editor.primary,
          target: editor.primary,
          tab: welcome,
          where: PaneEdge.bottom,
        ),
        isFalse,
      );
      expect(
        editor.layout.moveTab(from: editor.primary, tab: welcome, into: second),
        isFalse,
      );
      expect(editor.primary.tabs.first, same(welcome));
    });

    test('a tab from a group outside the tree can split an editor group', () {
      final editor = _editor();
      // The docked console panel is a group the editor layout does not
      // contain, which is where a dragged-out tab comes from.
      final console = TabbedViewController([TabData(text: 'REPL')]);
      addTearDown(console.dispose);

      final split = editor.layout.splitGroup(
        from: console,
        target: editor.primary,
        tab: console.tabs.single,
        where: PaneEdge.right,
      );

      expect(split, isTrue);
      expect(console.tabs, isEmpty);
      final layout = editor.container.read(editorLayoutProvider) as SplitLayout;
      final created = (layout.children[1] as GroupLayout).controller;
      expect(created.tabs.single.text, 'REPL');
      expect(editor.container.read(focusedEditorGroupProvider), same(created));
    });

    test('only a group on the area boundary offers a root-level split', () {
      // The shape split nesting builds: root = [a1 | b1], a1 = [primary / a2].
      final editor = _editor();
      editor.primary.addTab(TabData(text: 'second'));
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: editor.primary.tabs[1],
        where: PaneEdge.right,
      );
      final b1 = allEditorControllers(editor.container)[1];
      editor.primary.addTab(TabData(text: 'a2 tab'));
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: editor.primary.tabs.last,
        where: PaneEdge.bottom,
      );
      final a2 = allEditorControllers(editor.container)[1];

      // a2 sits on the area's left edge -- primary and a1 are both entered
      // through their first child -- but not on its right or top edge.
      expect(editor.layout.isAtAreaEdge(a2, PaneEdge.left), isTrue);
      expect(editor.layout.isAtAreaEdge(a2, PaneEdge.right), isFalse);
      expect(editor.layout.isAtAreaEdge(a2, PaneEdge.top), isFalse);
      // b1 is on the right edge and, spanning the horizontal root's full
      // height, on the top and bottom edges too.
      expect(editor.layout.isAtAreaEdge(b1, PaneEdge.right), isTrue);
      expect(editor.layout.isAtAreaEdge(b1, PaneEdge.left), isFalse);
      expect(editor.layout.isAtAreaEdge(b1, PaneEdge.top), isTrue);
    });

    test('a drop on the area boundary adds a group above the top split', () {
      final editor = _editor();
      editor.primary.addTab(TabData(text: 'second'));
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: editor.primary.tabs[1],
        where: PaneEdge.right,
      );
      final b1 = allEditorControllers(editor.container)[1];
      editor.primary.addTab(TabData(text: 'a2 tab'));
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: editor.primary.tabs.last,
        where: PaneEdge.bottom,
      );
      final a2 = allEditorControllers(editor.container)[1];
      final moved = TabData(text: 'moved');
      a2.addTab(moved);

      final split = editor.layout.splitArea(
        from: a2,
        tab: moved,
        where: PaneEdge.left,
      );

      expect(split, isTrue);
      final layout = editor.container.read(editorLayoutProvider) as SplitLayout;
      expect(layout.axis, Axis.horizontal);
      // The new group wraps the whole previous tree instead of nesting inside
      // the leaf it was dragged from.
      expect(layout.children, hasLength(2));
      final created = (layout.children[0] as GroupLayout).controller;
      expect(created.tabs.single, same(moved));
      final kept = layout.children[1] as SplitLayout;
      expect(kept.axis, Axis.horizontal);
      expect(kept.children, hasLength(2));
      expect(allEditorControllers(editor.container), hasLength(4));
      expect(a2.tabs.map((tab) => tab.text), ['a2 tab']);
      expect(b1.tabs, isNotEmpty);
    });

    test('the area split refuses what a group split refuses', () {
      final editor = _editor();
      final welcome = editor.primary.tabs.single;

      expect(
        editor.layout.canSplitArea(from: editor.primary, tab: welcome),
        isFalse,
      );
      expect(
        editor.layout.splitArea(
          from: editor.primary,
          tab: welcome,
          where: PaneEdge.left,
        ),
        isFalse,
      );
      expect(
        editor.layout.canSplitArea(
          from: editor.primary,
          tab: TabData(text: 'gone'),
        ),
        isFalse,
      );
      expect(
        editor.container.read(editorLayoutProvider),
        GroupLayout(editor.primary),
      );
    });

    test('the last group survives empty, so the editor always has a strip', () {
      final editor = _editor();
      editor.primary.removeTab(0);

      expect(
        editor.container.read(editorLayoutProvider),
        GroupLayout(editor.primary),
      );
    });

    test('an unchanged tree is not written again', () {
      final editor = _editor();
      var writes = 0;
      editor.container.listen(editorLayoutProvider, (_, _) => writes++);

      editor.layout.replace(GroupLayout(editor.primary));
      editor.primary.addTab(TabData(text: 'a'));

      expect(writes, 0);
    });

    testWidgets('closing a group last tab removes the group from the screen', (
      tester,
    ) async {
      final editor = _editor();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      editor.primary.addTab(TabData(text: 'second'));
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: editor.primary.tabs[1],
        where: PaneEdge.right,
      );
      final secondary = allEditorControllers(editor.container)[1];

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: editor.container,
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
      // The action bar belongs to the editor area, not to a group: two groups
      // still share the one bar.
      expect(find.byType(EditorGroup), findsNWidgets(2));
      expect(find.byIcon(Icons.save_outlined), findsOneWidget);

      secondary.removeTab(0);
      await tester.pump();

      expect(
        editor.container.read(editorLayoutProvider),
        GroupLayout(editor.primary),
      );
      expect(find.byType(EditorGroup), findsOneWidget);
    });

    testWidgets('reshaping the tree keeps a group\'s subtree alive', (
      tester,
    ) async {
      final editor = _editor();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final moved = TabData(text: 'moved');
      editor.primary.addTab(moved);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: editor.container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => buildShadcnLayer(context, const Editor()),
              ),
            ),
          ),
        ),
      );
      final before = tester.element(find.byType(EditorGroup));

      // The primary group moves from the root into the new split's first pane.
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: moved,
        where: PaneEdge.right,
      );
      await tester.pump();

      final primaryGroup = find.byWidgetPredicate(
        (widget) =>
            widget is EditorGroup &&
            identical(widget.controller, editor.primary),
      );
      expect(tester.element(primaryGroup), same(before));
    });
  });

  group('every group, not only the primary one', () {
    test('saving a tab in another group clears its modified dot', () {
      final editor = _editor();
      final tab = _fileTab('/nonexistent/s.py', isSaved: false);
      editor.primary.addTab(tab);
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: tab,
        where: PaneEdge.right,
      );

      editor.container
          .read(tabbedViewControllerProvider.notifier)
          .afterFileSave(tab);

      expect(editorTabValueOf(tab)!.isSaved, isTrue);
    });

    test('renaming a file open in another group renames its tab', () {
      final editor = _editor();
      final tab = _fileTab('/proj/old.py');
      editor.primary.addTab(tab);
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: tab,
        where: PaneEdge.right,
      );

      editor.container
          .read(tabbedViewControllerProvider.notifier)
          .renameLocalOpenPath('/proj/old.py', '/proj/new.py');

      expect(editorTabValueOf(tab)!.filePath, '/proj/new.py');
      expect(tab.text, 'new.py');
    });

    test('the active tab follows a selection made inside a split group', () {
      final editor = _editor();
      final a = _fileTab('/proj/a.py');
      final b = _fileTab('/proj/b.py');
      editor.primary.addTab(a);
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: a,
        where: PaneEdge.right,
      );
      final group = editor.container.read(activeEditorControllerProvider);
      group.addTab(b);
      final seen = <TabData?>[];
      editor.container.listen(
        activeEditorTabProvider,
        (_, next) => seen.add(next.tab),
        fireImmediately: true,
      );

      // What a tap on a tab does: the group is changed in place.
      group.selectedIndex = group.tabs.indexOf(b);

      expect(editor.container.read(activeEditorTabProvider).tab, same(b));
      expect(seen.last, same(b));
    });

    test('same-named files in different groups are disambiguated', () {
      final editor = _editor();
      final parked = TabData(text: 'parked');
      editor.primary.addTab(parked);
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: parked,
        where: PaneEdge.right,
      );
      final second = allEditorControllers(editor.container)[1];
      final client = _fileTab('/proj/client/README.md');
      final server = _fileTab('/proj/server/README.md');
      editor.primary.addTab(client);
      second.addTab(server);

      refreshFileTabTitles(allEditorTabs(editor.container));

      expect(client.text, 'client/README.md');
      expect(server.text, 'server/README.md');
    });
  });

  group('layout persistence', () {
    test('a split tree round-trips through its persisted shape', () {
      final editor = _editor();
      final a = TabData(text: 'a');
      final c = TabData(text: 'c');
      editor.primary
        ..addTab(a)
        ..addTab(TabData(text: 'b'));
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: a,
        where: PaneEdge.right,
      );
      final nested = allEditorControllers(editor.container)[1];
      nested.addTab(c);
      editor.layout.splitGroup(
        from: nested,
        target: nested,
        tab: c,
        where: PaneEdge.bottom,
      );

      final persisted = persistEditorLayout(
        editor.container.read(editorLayoutProvider),
        primary: editor.primary,
        convert: (group) => PersistedEditorGroup(tabs: const []),
      );
      expect(persisted.groups, hasLength(3));
      expect(persisted.primaryIndex, 0);
      final node = persisted.node;
      expect(node.axis, 'horizontal');
      // The right-hand child is itself a split, so the nesting survives.
      expect(node.children[1].axis, 'vertical');
      expect(node.children[1].children, hasLength(2));

      final fresh = TabbedViewController([]);
      final restored = restoreEditorLayout(
        persisted.groups,
        node,
        primary: fresh,
        primaryIndex: persisted.primaryIndex,
      );
      final restoredSplit = restored.node as SplitLayout;
      expect(restoredSplit.axis, Axis.horizontal);
      expect(restoredSplit.children.first, GroupLayout(fresh));
      final inner = restoredSplit.children[1] as SplitLayout;
      expect(inner.axis, Axis.vertical);
      expect(inner.children, hasLength(2));
      expect(restored.controllers, hasLength(3));
      expect(restored.controllers.first, same(fresh));
    });

    test('the primary role stays with its group across a restore', () {
      final editor = _editor();
      final a = TabData(text: 'a');
      editor.primary.addTab(a);
      // A split to the left puts the new group first, ahead of the primary.
      editor.layout.splitGroup(
        from: editor.primary,
        target: editor.primary,
        tab: a,
        where: PaneEdge.left,
      );

      final persisted = persistEditorLayout(
        editor.container.read(editorLayoutProvider),
        primary: editor.primary,
        convert: (group) => PersistedEditorGroup(tabs: const []),
      );
      expect(persisted.primaryIndex, 1);

      final fresh = TabbedViewController([]);
      final restored = restoreEditorLayout(
        persisted.groups,
        persisted.node,
        primary: fresh,
        primaryIndex: persisted.primaryIndex,
      );
      // The welcome page's group is still the right-hand one.
      final split = restored.node as SplitLayout;
      expect(split.children.last, GroupLayout(fresh));
      expect(split.children.first, isNot(GroupLayout(fresh)));
    });

    test('a single group persists without a tree', () {
      final editor = _editor();

      final persisted = persistEditorLayout(
        editor.container.read(editorLayoutProvider),
        primary: editor.primary,
        convert: (group) => PersistedEditorGroup(tabs: []),
      );

      expect(persisted.groups, hasLength(1));
      expect(persisted.node.isSplit, isFalse);
      final restored = restoreEditorLayout(
        persisted.groups,
        persisted.node,
        primary: editor.primary,
      );
      expect(restored.node, GroupLayout(editor.primary));
    });

    test('leaves pointing past the groups, or repeated, are dropped', () {
      final groups = [
        PersistedEditorGroup(tabs: []),
        PersistedEditorGroup(tabs: []),
      ];
      final node = PersistedEditorLayout.split('horizontal', [
        PersistedEditorLayout.group(0),
        PersistedEditorLayout.split('vertical', [
          PersistedEditorLayout.group(2),
          PersistedEditorLayout.group(1),
          PersistedEditorLayout.group(1),
        ]),
      ]);
      final primary = TabbedViewController([]);

      final restored = restoreEditorLayout(groups, node, primary: primary);
      final split = restored.node as SplitLayout;

      expect(split.children, hasLength(2));
      expect(split.children.first, GroupLayout(primary));
      // The dangling and the repeated leaf are gone, so the inner split
      // collapses into its one surviving leaf.
      expect(split.children[1], GroupLayout(restored.controllers[1]));
    });

    test(
      'restoreEditorGroups seeds the controllers the tree points at',
      () async {
        final editor = _editor();
        final node = PersistedEditorLayout.split('horizontal', [
          PersistedEditorLayout.group(0),
          PersistedEditorLayout.group(1),
        ]);

        await editor.container
            .read(tabbedViewControllerProvider.notifier)
            .restoreEditorGroups([
              PersistedEditorGroup(tabs: []),
              PersistedEditorGroup(tabs: []),
            ], node);

        // The second group restored empty -- its files are gone -- so it is
        // dropped, and the primary keeps the welcome page it was built with.
        expect(
          editor.container.read(editorLayoutProvider),
          GroupLayout(editor.primary),
        );
        expect(
          editor.container.read(tabbedViewControllerProvider),
          same(editor.primary),
        );
        final welcomeCount = allEditorTabs(
          editor.container,
        ).where((tab) => editorTabValueOf(tab)?.type == 'page').length;
        expect(welcomeCount, 1);
      },
    );
  });
}
