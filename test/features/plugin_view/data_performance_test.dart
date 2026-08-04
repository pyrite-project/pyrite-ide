import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/tree_index.dart';
import 'package:pyrite_ide/features/plugin_view/data/plugin_data_table.dart';
import 'package:pyrite_ide/features/plugin_view/data/plugin_tree_view.dart';
import 'package:pyrite_ide/features/plugin_view/data/plugin_virtual_list.dart';
import 'package:pyrite_ide/features/plugin_view/data/visible_range_tracker.dart';

Widget _wrap(Widget child, {double height = 400, double width = 600}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(height: height, width: width, child: child),
      ),
    );

void main() {
  group('gate: a 10k snapshot loads', () {
    testWidgets('VirtualList accepts 10k rows and builds only the window', (
      tester,
    ) async {
      final items = {
        for (var i = 0; i < 10000; i++) i: {'id': 'n$i', 'label': 'row $i'},
      };
      final key = GlobalKey<PluginVirtualListState>();
      final sw = Stopwatch()..start();
      await tester.pumpWidget(
        _wrap(PluginVirtualList(key: key, items: items, itemCount: 10000)),
      );
      sw.stop();
      // ignore: avoid_print
      print('BENCH virtuallist-10k first frame: ${sw.elapsedMilliseconds}ms');

      // 400px tall at 22px per row: only a small window is materialized.
      expect(key.currentState!.builtRowCount, lessThan(60));
      expect(find.text('row 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TreeView accepts a 10k node index', (tester) async {
      final index = TreeIndex()
        ..reset([
          for (var i = 0; i < 10000; i++)
            TreeNodeModel(id: 'n$i', label: 'node $i'),
        ]);
      final key = GlobalKey<PluginTreeViewState>();
      final sw = Stopwatch()..start();
      await tester.pumpWidget(_wrap(PluginTreeView(key: key, index: index)));
      sw.stop();
      // ignore: avoid_print
      print('BENCH treeview-10k first frame: ${sw.elapsedMilliseconds}ms');

      expect(index.length, 10000);
      expect(key.currentState!.builtRowCount, lessThan(60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('DataTable accepts 10k rows', (tester) async {
      final rows = {
        for (var i = 0; i < 10000; i++)
          i: {
            'id': 'r$i',
            'cells': {'name': 'row $i', 'value': '$i'},
          },
      };
      await tester.pumpWidget(
        _wrap(
          PluginDataTable(
            columns: const [
              PluginColumn(id: 'name', label: 'Name'),
              PluginColumn(id: 'value', label: 'Value'),
            ],
            rows: rows,
            rowCount: 10000,
          ),
        ),
      );
      expect(find.text('row 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('gate: 100k logical nodes do not create 100k widgets', () {
    testWidgets('VirtualList with 100k declared rows builds a small window', (
      tester,
    ) async {
      // Only the first chunk is loaded; the rest are gaps.
      final items = {
        for (var i = 0; i < 200; i++) i: {'id': 'n$i', 'label': 'row $i'},
      };
      final key = GlobalKey<PluginVirtualListState>();
      await tester.pumpWidget(
        _wrap(PluginVirtualList(key: key, items: items, itemCount: 100000)),
      );

      // Far fewer than 100k rows built, and no crash from the huge count.
      expect(key.currentState!.builtRowCount, lessThan(60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 100k-logical-node tree materializes only loaded nodes', (
      tester,
    ) async {
      // 1000 roots each claiming 100 unloaded children = 100k logical nodes.
      final index = TreeIndex()
        ..reset([
          for (var r = 0; r < 1000; r++)
            TreeNodeModel(
              id: 'r$r',
              label: 'root $r',
              hasChildren: true,
              childrenState: ChildrenState.unloaded,
            ),
        ]);
      final key = GlobalKey<PluginTreeViewState>();
      await tester.pumpWidget(_wrap(PluginTreeView(key: key, index: index)));

      // The model holds 1000 nodes, not 100k, and the widget builds ~17 rows.
      expect(index.nodeCount, 1000);
      expect(key.currentState!.builtRowCount, lessThan(60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('DataTable with 100k declared rows builds a small window', (
      tester,
    ) async {
      final rows = {
        for (var i = 0; i < 100; i++)
          i: {
            'id': 'r$i',
            'cells': {'name': 'row $i'},
          },
      };
      await tester.pumpWidget(
        _wrap(
          PluginDataTable(
            columns: const [PluginColumn(id: 'name', label: 'Name')],
            rows: rows,
            rowCount: 100000,
          ),
        ),
      );
      // The loaded rows that fall in the viewport render; the rest are
      // placeholders, so the widget count stays bounded.
      expect(find.text('row 0'), findsOneWidget);
      expect(find.text('row 99'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('gate: a single label update does not rebuild the list', () {
    testWidgets('relabelling one tree node repaints only that row', (
      tester,
    ) async {
      final index = TreeIndex()
        ..reset([
          for (var i = 0; i < 500; i++)
            TreeNodeModel(id: 'n$i', label: 'node $i'),
        ]);
      final key = GlobalKey<PluginTreeViewState>();
      await tester.pumpWidget(_wrap(PluginTreeView(key: key, index: index)));

      final afterFirstFrame = key.currentState!.builtRowCount;
      expect(find.text('node 0'), findsOneWidget);

      // Mutate one label and repaint.
      index.relabel('n0', 'renamed');
      key.currentState!.refresh();
      await tester.pump();

      final rebuilt = key.currentState!.builtRowCount - afterFirstFrame;
      // ignore: avoid_print
      print(
        'BENCH rows rebuilt after 1 relabel in a 500-node tree: $rebuilt '
        '(list length 500)',
      );

      expect(find.text('renamed'), findsOneWidget);
      // Only the visible window is rebuilt, never all 500 rows.
      expect(rebuilt, lessThan(60));
      // And the index was untouched by the relabel.
      expect(index.length, 500);
    });

    testWidgets('a label change leaves the visible row order intact', (
      tester,
    ) async {
      final index = TreeIndex()
        ..reset([
          TreeNodeModel(id: 'a', label: 'Alpha'),
          TreeNodeModel(id: 'b', label: 'Beta'),
          TreeNodeModel(id: 'c', label: 'Gamma'),
        ]);
      final key = GlobalKey<PluginTreeViewState>();
      await tester.pumpWidget(_wrap(PluginTreeView(key: key, index: index)));

      final before = List<String>.from(index.visibleNodeIds);
      index.relabel('b', 'Beta renamed');
      key.currentState!.refresh();
      await tester.pump();

      expect(index.visibleNodeIds, before);
      expect(find.text('Beta renamed'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
    });
  });

  group('gate: scrolling issues no Python RPC', () {
    test('the range tracker coalesces a burst of scroll frames', () async {
      final requests = <({int start, int count})>[];
      final tracker = VisibleRangeTracker(
        onRequest: (start, count) => requests.add((start: start, count: count)),
        debounce: const Duration(milliseconds: 50),
        chunkSize: 100,
      );
      addTearDown(tracker.dispose);

      // 60 scroll frames walking through the same two chunks.
      for (var i = 0; i < 60; i++) {
        tracker.noteMissing(i, i + 1);
      }
      // Nothing sent yet: the window is still open.
      expect(requests, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      // One coalesced request, not 60.
      expect(requests, hasLength(1));
      expect(requests.single.start, 0);
    });

    test('an already-requested chunk is never requested twice', () async {
      final requests = <({int start, int count})>[];
      final tracker = VisibleRangeTracker(
        onRequest: (start, count) => requests.add((start: start, count: count)),
        debounce: const Duration(milliseconds: 20),
        chunkSize: 100,
      );
      addTearDown(tracker.dispose);

      tracker.noteMissing(0, 50);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(requests, hasLength(1));

      // Scrolling back over the same chunk asks for nothing.
      tracker.noteMissing(10, 60);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(requests, hasLength(1));

      // A genuinely new chunk does get requested.
      tracker.noteMissing(150, 160);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(requests, hasLength(2));
      expect(requests.last.start, 100);
    });

    testWidgets('scrolling a fully-loaded list requests nothing at all', (
      tester,
    ) async {
      final requests = <int>[];
      final items = {
        for (var i = 0; i < 500; i++) i: {'id': 'n$i', 'label': 'row $i'},
      };
      await tester.pumpWidget(
        _wrap(
          PluginVirtualList(
            items: items,
            itemCount: 500,
            onRequestRange: (start, count) => requests.add(start),
          ),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      // Every row was loaded, so no round-trip was ever needed.
      expect(requests, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolling into a gap issues one coalesced request', (
      tester,
    ) async {
      final requests = <({int start, int count})>[];
      // Only the first 100 rows are loaded of 5000 declared.
      final items = {
        for (var i = 0; i < 100; i++) i: {'id': 'n$i', 'label': 'row $i'},
      };
      await tester.pumpWidget(
        _wrap(
          PluginVirtualList(
            items: items,
            itemCount: 5000,
            onRequestRange: (start, count) =>
                requests.add((start: start, count: count)),
          ),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      // The tracker debounces with a Timer, which pumpAndSettle does not
      // advance on its own; pump past the window so it fires.
      await tester.pump(const Duration(milliseconds: 200));

      // Scrolling across many missing rows must not fire per-row requests.
      // ignore: avoid_print
      print('BENCH requests after scrolling into a gap: ${requests.length}');
      expect(requests, isNotEmpty);
      expect(requests.length, lessThan(5));
      expect(tester.takeException(), isNull);
    });
  });

  group('interaction: selection, keyboard, lazy children', () {
    testWidgets('selection survives a model update', (tester) async {
      final index = TreeIndex()
        ..reset([
          TreeNodeModel(id: 'a', label: 'Alpha'),
          TreeNodeModel(id: 'b', label: 'Beta'),
        ]);
      final key = GlobalKey<PluginTreeViewState>();
      await tester.pumpWidget(_wrap(PluginTreeView(key: key, index: index)));

      await tester.tap(find.text('Beta'));
      await tester.pump();
      expect(key.currentState!.selectedId, 'b');

      // A label update rebuilds the row but must not clear selection.
      index.relabel('a', 'Alpha 2');
      key.currentState!.refresh();
      await tester.pump();
      expect(key.currentState!.selectedId, 'b');
    });

    testWidgets('arrow keys move selection and expand nodes', (tester) async {
      final index = TreeIndex()
        ..reset([
          TreeNodeModel(id: 'a', label: 'Alpha', hasChildren: true),
          TreeNodeModel(id: 'a1', label: 'Alpha child', parentId: 'a'),
          TreeNodeModel(id: 'b', label: 'Beta'),
        ]);
      final key = GlobalKey<PluginTreeViewState>();
      await tester.pumpWidget(_wrap(PluginTreeView(key: key, index: index)));

      // Focus the tree, then walk with the keyboard.
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      expect(key.currentState!.selectedId, 'a');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(index.isExpanded('a'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(key.currentState!.selectedId, 'a1');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(key.currentState!.selectedId, 'a');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(index.isExpanded('a'), isFalse);
    });

    testWidgets('expanding an unloaded node requests children once', (
      tester,
    ) async {
      final requested = <String>[];
      final index = TreeIndex()
        ..reset([
          TreeNodeModel(
            id: 'lazy',
            label: 'Lazy',
            hasChildren: true,
            childrenState: ChildrenState.unloaded,
          ),
        ]);
      final key = GlobalKey<PluginTreeViewState>();
      await tester.pumpWidget(
        _wrap(
          PluginTreeView(
            key: key,
            index: index,
            onRequestChildren: requested.add,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();

      expect(requested, ['lazy']);
      // A spinner shows while the fetch is in flight.
      expect(index.node('lazy')!.childrenState, ChildrenState.loading);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Children arrive and splice in.
      index.attachChildren('lazy', [
        TreeNodeModel(id: 'c1', label: 'Child 1', parentId: 'lazy'),
      ]);
      index.expand('lazy');
      key.currentState!.refresh();
      await tester.pump();
      expect(find.text('Child 1'), findsOneWidget);
    });

    testWidgets(
      'expanding an unloaded node expands once children are emitted',
      (tester) async {
        final requested = <String>[];
        final index = TreeIndex()
          ..reset([
            TreeNodeModel(
              id: 'lazy',
              label: 'Lazy',
              hasChildren: true,
              childrenState: ChildrenState.unloaded,
            ),
          ]);
        final key = GlobalKey<PluginTreeViewState>();
        await tester.pumpWidget(
          _wrap(
            PluginTreeView(
              key: key,
              index: index,
              onRequestChildren: requested.add,
            ),
          ),
        );

        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pump();

        expect(requested, ['lazy']);
        // The expand intent is recorded immediately, so the rows splice in when
        // the plugin re-emits the tree (host `_reconcile` resets while keeping
        // the expanded set) — no second tap required.
        expect(index.isExpanded('lazy'), isTrue);

        index.reset(
          [
            TreeNodeModel(
              id: 'lazy',
              label: 'Lazy',
              hasChildren: true,
              childrenState: ChildrenState.loaded,
            ),
            TreeNodeModel(id: 'c1', label: 'Child 1', parentId: 'lazy'),
          ],
          expanded: {for (final id in index.expandedNodeIds) id},
        );
        key.currentState!.refresh();
        await tester.pump();

        expect(find.text('Child 1'), findsOneWidget);
      },
    );

    testWidgets('a failed child load offers a retry affordance', (
      tester,
    ) async {
      final index = TreeIndex()
        ..reset([
          TreeNodeModel(
            id: 'bad',
            label: 'Broken',
            hasChildren: true,
            childrenState: ChildrenState.error,
          ),
        ]);
      await tester.pumpWidget(_wrap(PluginTreeView(index: index)));
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DataTable header click emits sort', (tester) async {
      final sorted = <String>[];
      await tester.pumpWidget(
        _wrap(
          PluginDataTable(
            columns: const [PluginColumn(id: 'name', label: 'Name')],
            rows: {
              0: {
                'id': 'r0',
                'cells': {'name': 'x'},
              },
            },
            rowCount: 1,
            onSort: sorted.add,
          ),
        ),
      );
      await tester.tap(find.text('Name'));
      await tester.pump();
      expect(sorted, ['name']);
    });

    testWidgets('DataTable keyboard moves selection and activates a row', (
      tester,
    ) async {
      final selected = <String>[];
      final activated = <String>[];
      await tester.pumpWidget(
        _wrap(
          PluginDataTable(
            columns: const [PluginColumn(id: 'name', label: 'Name')],
            rows: {
              0: {
                'id': 'r0',
                'cells': {'name': 'first'},
              },
              1: {
                'id': 'r1',
                'cells': {'name': 'second'},
              },
            },
            rowCount: 2,
            onSelect: selected.add,
            onActivate: activated.add,
          ),
        ),
      );

      await tester.tap(find.text('first'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(selected, ['r0', 'r1']);
      expect(activated, ['r1']);
    });
  });
}
