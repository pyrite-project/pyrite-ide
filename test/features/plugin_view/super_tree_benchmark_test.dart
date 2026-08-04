import 'package:flutter_test/flutter_test.dart';
import 'package:super_tree/super_tree.dart';

/// Builds a tree of [total] nodes with [breadth] children per branch node.
List<TreeNode<String>> _buildTree({
  required int total,
  int breadth = 10,
  bool expanded = false,
}) {
  var made = 0;
  TreeNode<String> node(int depth) {
    final id = 'n${made++}';
    final children = <TreeNode<String>>[];
    if (depth > 0) {
      for (var i = 0; i < breadth && made < total; i++) {
        children.add(node(depth - 1));
      }
    }
    return TreeNode<String>(
      id: id,
      data: id,
      children: children,
      isExpanded: expanded,
    );
  }

  final roots = <TreeNode<String>>[];
  while (made < total) {
    roots.add(node(3));
  }
  return roots;
}

void main() {
  test('BENCH: build controller with 10k nodes', () {
    final roots = _buildTree(total: 10000, expanded: true);
    final sw = Stopwatch()..start();
    final controller = TreeController<String>(roots: roots);
    sw.stop();
    // ignore: avoid_print
    print(
      'BENCH build-10k: ${sw.elapsedMilliseconds}ms, '
      'visible=${controller.flatVisibleNodes.length}',
    );
    expect(controller.flatVisibleNodes, isNotEmpty);
  });

  test('BENCH: build controller with 100k nodes', () {
    final roots = _buildTree(total: 100000, expanded: true);
    final sw = Stopwatch()..start();
    final controller = TreeController<String>(roots: roots);
    sw.stop();
    // ignore: avoid_print
    print(
      'BENCH build-100k: ${sw.elapsedMilliseconds}ms, '
      'visible=${controller.flatVisibleNodes.length}',
    );
    expect(controller.flatVisibleNodes, isNotEmpty);
  });

  test('BENCH: expand one node in a 100k tree', () {
    // Collapsed so expanding is a genuine incremental splice.
    final roots = _buildTree(total: 100000);
    final controller = TreeController<String>(roots: roots);
    final target = controller.flatVisibleNodes.firstWhere((n) => n.hasChildren);

    final sw = Stopwatch()..start();
    controller.expandNode(target);
    sw.stop();
    // ignore: avoid_print
    print(
      'BENCH expand-in-100k: ${sw.elapsedMicroseconds}us, '
      'visible=${controller.flatVisibleNodes.length}',
    );
  });

  test('BENCH: collapse one node in a 100k tree', () {
    final roots = _buildTree(total: 100000, expanded: true);
    final controller = TreeController<String>(roots: roots);
    final target = controller.flatVisibleNodes.firstWhere((n) => n.hasChildren);

    final sw = Stopwatch()..start();
    controller.collapseNode(target);
    sw.stop();
    // ignore: avoid_print
    print('BENCH collapse-in-100k: ${sw.elapsedMicroseconds}us');
  });

  test('BENCH: repeated expand/collapse cycles in a 100k tree', () {
    final roots = _buildTree(total: 100000);
    final controller = TreeController<String>(roots: roots);
    final target = controller.flatVisibleNodes.firstWhere((n) => n.hasChildren);

    final sw = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      controller.expandNode(target);
      controller.collapseNode(target);
    }
    sw.stop();
    // ignore: avoid_print
    print(
      'BENCH 50x expand+collapse in 100k: ${sw.elapsedMilliseconds}ms '
      '(${sw.elapsedMicroseconds / 100}us per op)',
    );
  });

  test('BENCH: addRoot into a 100k tree (full re-flatten path)', () {
    final roots = _buildTree(total: 100000, expanded: true);
    final controller = TreeController<String>(roots: roots);
    final sw = Stopwatch()..start();
    controller.addRoot(TreeNode<String>(id: 'extra', data: 'extra'));
    sw.stop();
    // ignore: avoid_print
    print('BENCH addRoot-in-100k: ${sw.elapsedMicroseconds}us');
  });

  test('BENCH: mutating a payload label touches no index', () {
    // TreeNode.data is final, so changing a label must either replace the node
    // (which re-flattens the tree) or mutate a payload object in place. A
    // mutable payload keeps a label update entirely off the index.
    final nodes = [
      for (var i = 0; i < 10000; i++)
        TreeNode<Map<String, String>>(id: 'n$i', data: {'label': 'label $i'}),
    ];
    final controller = TreeController<Map<String, String>>(roots: nodes);
    final before = controller.flatVisibleNodes.length;

    final sw = Stopwatch()..start();
    controller.findNodeById('n5000')!.data['label'] = 'changed';
    sw.stop();
    // ignore: avoid_print
    print('BENCH label-mutate-in-10k: ${sw.elapsedMicroseconds}us');
    expect(controller.flatVisibleNodes.length, before);
    expect(controller.findNodeById('n5000')!.data['label'], 'changed');
  });
}
