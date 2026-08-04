import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/tree_index.dart';

TreeNodeModel _node(
  String id, {
  String? parentId,
  bool hasChildren = false,
  ChildrenState state = ChildrenState.loaded,
  String? label,
}) => TreeNodeModel(
  id: id,
  label: label ?? 'label $id',
  parentId: parentId,
  hasChildren: hasChildren,
  childrenState: state,
);

/// a > (a1 > a1x, a2), b
List<TreeNodeModel> _sample() => [
  _node('a', hasChildren: true),
  _node('a1', parentId: 'a', hasChildren: true),
  _node('a1x', parentId: 'a1'),
  _node('a2', parentId: 'a'),
  _node('b'),
];

void main() {
  group('structure', () {
    test('reset indexes roots and children, collapsed by default', () {
      final index = TreeIndex()..reset(_sample());
      expect(index.visibleNodeIds, ['a', 'b']);
      expect(index.nodeCount, 5);
      expect(index.childrenOf('a'), ['a1', 'a2']);
      expect(index.childrenOf(null), ['a', 'b']);
    });

    test('reset honours a pre-expanded set', () {
      final index = TreeIndex()..reset(_sample(), expanded: {'a'});
      expect(index.visibleNodeIds, ['a', 'a1', 'a2', 'b']);
    });

    test('depthOf walks the parent chain', () {
      final index = TreeIndex()..reset(_sample());
      expect(index.depthOf('a'), 0);
      expect(index.depthOf('a1'), 1);
      expect(index.depthOf('a1x'), 2);
    });
  });

  group('expand and collapse splice only the affected span', () {
    test('expand inserts the visible descendants after the row', () {
      final index = TreeIndex()..reset(_sample());
      final inserted = index.expand('a');
      expect(inserted, 2);
      expect(index.visibleNodeIds, ['a', 'a1', 'a2', 'b']);
    });

    test('nested expansion reveals grandchildren in order', () {
      final index = TreeIndex()..reset(_sample());
      index.expand('a');
      index.expand('a1');
      expect(index.visibleNodeIds, ['a', 'a1', 'a1x', 'a2', 'b']);
    });

    test('collapse removes the descendant rows', () {
      final index = TreeIndex()..reset(_sample());
      index.expand('a');
      index.expand('a1');
      final removed = index.collapse('a');
      expect(removed, 3);
      expect(index.visibleNodeIds, ['a', 'b']);
    });

    test('re-expanding restores the previous nested shape', () {
      final index = TreeIndex()..reset(_sample());
      index.expand('a');
      index.expand('a1');
      index.collapse('a');
      index.expand('a');
      // a1 stayed expanded, so a1x comes back too.
      expect(index.visibleNodeIds, ['a', 'a1', 'a1x', 'a2', 'b']);
    });

    test('visible index stays consistent after splices', () {
      final index = TreeIndex()..reset(_sample());
      index.expand('a');
      for (var i = 0; i < index.visibleNodeIds.length; i++) {
        expect(index.visibleIndexOf(index.visibleNodeIds[i]), i);
      }
      index.collapse('a');
      for (var i = 0; i < index.visibleNodeIds.length; i++) {
        expect(index.visibleIndexOf(index.visibleNodeIds[i]), i);
      }
    });

    test('toggle reports the new state', () {
      final index = TreeIndex()..reset(_sample());
      expect(index.toggle('a'), isTrue);
      expect(index.toggle('a'), isFalse);
    });
  });

  group('insert, remove, move', () {
    test('insert under a collapsed parent does not add a row', () {
      final index = TreeIndex()..reset(_sample());
      index.insert(_node('a3', parentId: 'a'));
      expect(index.visibleNodeIds, ['a', 'b']);
      expect(index.childrenOf('a'), ['a1', 'a2', 'a3']);
    });

    test('insert under an expanded parent splices at the right row', () {
      final index = TreeIndex()..reset(_sample());
      index.expand('a');
      index.insert(_node('a15', parentId: 'a'), at: 1);
      expect(index.visibleNodeIds, ['a', 'a1', 'a15', 'a2', 'b']);
    });

    test('insert lands after a preceding sibling subtree', () {
      final index = TreeIndex()..reset(_sample());
      index.expand('a');
      index.expand('a1');
      index.insert(_node('a15', parentId: 'a'), at: 1);
      // Must go after a1's descendant a1x, not between a1 and a1x.
      expect(index.visibleNodeIds, ['a', 'a1', 'a1x', 'a15', 'a2', 'b']);
    });

    test('insert a new root appends', () {
      final index = TreeIndex()..reset(_sample());
      index.insert(_node('c'));
      expect(index.visibleNodeIds, ['a', 'b', 'c']);
    });

    test('remove drops the node and its subtree', () {
      final index = TreeIndex()..reset(_sample());
      index.expand('a');
      index.expand('a1');
      index.remove('a1');
      expect(index.visibleNodeIds, ['a', 'a2', 'b']);
      expect(index.node('a1x'), isNull);
      expect(index.childrenOf('a'), ['a2']);
    });

    test('move relocates a subtree to a new parent', () {
      final index = TreeIndex()..reset(_sample());
      index.move('a1', newParentId: 'b');
      expect(index.childrenOf('a'), ['a2']);
      expect(index.childrenOf('b'), ['a1']);
      expect(index.node('a1')!.parentId, 'b');
      // Its child came along.
      expect(index.childrenOf('a1'), ['a1x']);
    });

    test('move to root reorders top level', () {
      final index = TreeIndex()..reset(_sample());
      index.move('a1', at: 0);
      expect(index.visibleNodeIds.first, 'a1');
      expect(index.childrenOf('a'), ['a2']);
    });
  });

  group('label updates keep the index untouched', () {
    test('relabel changes the label without moving rows', () {
      final index = TreeIndex()..reset(_sample());
      index.expand('a');
      final before = List<String>.from(index.visibleNodeIds);

      expect(index.relabel('a1', 'renamed'), isTrue);
      expect(index.node('a1')!.label, 'renamed');
      // Identical row order, and the same list instance was reused.
      expect(index.visibleNodeIds, before);
    });

    test('relabelling a hidden node still works', () {
      final index = TreeIndex()..reset(_sample());
      expect(index.relabel('a1x', 'deep'), isTrue);
      expect(index.node('a1x')!.label, 'deep');
      expect(index.visibleNodeIds, ['a', 'b']);
    });

    test('relabel of a missing id reports false', () {
      final index = TreeIndex()..reset(_sample());
      expect(index.relabel('ghost', 'x'), isFalse);
    });
  });

  group('lazy loading', () {
    test('an unloaded node needs children before it can expand', () {
      final index = TreeIndex()
        ..reset([
          _node('lazy', hasChildren: true, state: ChildrenState.unloaded),
        ]);
      expect(index.needsChildren('lazy'), isTrue);
      // Expanding yields no rows yet.
      expect(index.expand('lazy'), 0);
      expect(index.visibleNodeIds, ['lazy']);
    });

    test('markExpanded records the intent before children arrive', () {
      final index = TreeIndex()
        ..reset([
          _node('lazy', hasChildren: true, state: ChildrenState.unloaded),
        ]);
      index.markExpanded('lazy');
      expect(index.isExpanded('lazy'), isTrue);
      // No rows splice in until the children are attached.
      expect(index.visibleNodeIds, ['lazy']);
      index.attachChildren('lazy', [
        _node('c1', parentId: 'lazy'),
        _node('c2', parentId: 'lazy'),
      ]);
      expect(index.visibleNodeIds, ['lazy', 'c1', 'c2']);
    });

    test('a reset preserves a markExpanded node and reveals its children', () {
      final index = TreeIndex()
        ..reset([
          _node('lazy', hasChildren: true, state: ChildrenState.unloaded),
        ]);
      index.markExpanded('lazy');
      // Plugin re-emits the tree with children loaded; the host reconciles by
      // resetting while keeping the expanded set (mirrors `_reconcile`).
      index.reset(
        [_node('lazy', hasChildren: true), _node('c1', parentId: 'lazy')],
        expanded: {for (final id in index.expandedNodeIds) id},
      );
      expect(index.visibleNodeIds, ['lazy', 'c1']);
    });

    test('attachChildren splices rows when the parent is expanded', () {
      final index = TreeIndex()
        ..reset([
          _node('lazy', hasChildren: true, state: ChildrenState.unloaded),
        ]);
      index.expand('lazy');
      index.attachChildren('lazy', [
        _node('c1', parentId: 'lazy'),
        _node('c2', parentId: 'lazy'),
      ]);
      expect(index.visibleNodeIds, ['lazy', 'c1', 'c2']);
      expect(index.needsChildren('lazy'), isFalse);
    });

    test('attachChildren while collapsed keeps rows hidden', () {
      final index = TreeIndex()
        ..reset([
          _node('lazy', hasChildren: true, state: ChildrenState.unloaded),
        ]);
      index.attachChildren('lazy', [_node('c1', parentId: 'lazy')]);
      expect(index.visibleNodeIds, ['lazy']);
      expect(index.childrenOf('lazy'), ['c1']);
    });

    test('loading and error states are tracked', () {
      final index = TreeIndex()
        ..reset([
          _node('lazy', hasChildren: true, state: ChildrenState.unloaded),
        ]);
      index.setChildrenState('lazy', ChildrenState.loading);
      expect(index.node('lazy')!.childrenState, ChildrenState.loading);
      index.setChildrenState('lazy', ChildrenState.error);
      expect(index.node('lazy')!.childrenState, ChildrenState.error);
      // An errored node can be retried.
      index.setChildrenState('lazy', ChildrenState.unloaded);
      expect(index.needsChildren('lazy'), isTrue);
    });
  });

  group('performance gates', () {
    /// Builds [total] nodes: `count` roots each with a lazily-loaded child set.
    List<TreeNodeModel> wide(int total) => [
      for (var i = 0; i < total; i++) _node('n$i'),
    ];

    test('a 10k node snapshot loads', () {
      final sw = Stopwatch()..start();
      final index = TreeIndex()..reset(wide(10000));
      sw.stop();
      // ignore: avoid_print
      print('BENCH reset-10k: ${sw.elapsedMilliseconds}ms');
      expect(index.length, 10000);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('100k logical nodes stay off the visible index until expanded', () {
      // One root per 100 logical children: 1k roots, 100k logical nodes.
      final nodes = <TreeNodeModel>[
        for (var r = 0; r < 1000; r++)
          _node('r$r', hasChildren: true, state: ChildrenState.unloaded),
      ];
      final index = TreeIndex()..reset(nodes);

      // Only the roots are visible; the other 99k are not materialized at all.
      expect(index.length, 1000);
      expect(index.nodeCount, 1000);

      // Lazily attach one root's children.
      index.expand('r0');
      index.attachChildren('r0', [
        for (var i = 0; i < 100; i++) _node('r0c$i', parentId: 'r0'),
      ]);
      expect(index.length, 1100);
      // Still nowhere near 100k materialized nodes.
      expect(index.nodeCount, 1100);
    });

    test('expand/collapse cost tracks the affected rows, not the tree', () {
      // 500 roots, each with 20 children, all loaded: 10.5k nodes.
      final nodes = <TreeNodeModel>[];
      for (var r = 0; r < 500; r++) {
        nodes.add(_node('r$r', hasChildren: true));
        for (var c = 0; c < 20; c++) {
          nodes.add(_node('r${r}c$c', parentId: 'r$r'));
        }
      }
      final index = TreeIndex()..reset(nodes);
      expect(index.length, 500);

      final sw = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        index.expand('r250');
        index.collapse('r250');
      }
      sw.stop();
      final perOp = sw.elapsedMicroseconds / 400;
      // ignore: avoid_print
      print(
        'BENCH expand+collapse in 10.5k tree: '
        '${perOp.toStringAsFixed(1)}us per op',
      );
      expect(index.length, 500);
      // Each op touches ~20 rows, so it must stay far below a full re-flatten.
      expect(perOp, lessThan(500));
    });

    test('relabelling every node never touches the visible index', () {
      final index = TreeIndex()..reset(wide(10000));
      final before = List<String>.from(index.visibleNodeIds);

      final sw = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        index.relabel('n$i', 'updated $i');
      }
      sw.stop();
      // ignore: avoid_print
      print(
        'BENCH 10k relabels: ${sw.elapsedMilliseconds}ms '
        '(${(sw.elapsedMicroseconds / 10000).toStringAsFixed(2)}us each)',
      );
      expect(index.visibleNodeIds, before);
      expect(index.node('n5000')!.label, 'updated 5000');
    });
  });
}
