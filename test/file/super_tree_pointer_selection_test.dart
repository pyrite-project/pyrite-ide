import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_tree/super_tree.dart';

void main() {
  TreeNode<String> nestedTree() {
    return TreeNode<String>(
      id: 'folder',
      data: 'Folder',
      children: <TreeNode<String>>[TreeNode<String>(id: 'file', data: 'File')],
    )..isExpanded = true;
  }

  Widget buildTree({
    required TreeController<String> controller,
    TreeViewConfig<String> logic = const TreeViewConfig<String>(),
    Widget Function(BuildContext, TreeNode<String>, Widget?)? contentBuilder,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SuperTreeView<String>(
          controller: controller,
          prefixBuilder: (context, node) => const SizedBox.shrink(),
          contentBuilder:
              contentBuilder ?? (context, node, renameField) => Text(node.data),
          logic: logic,
        ),
      ),
    );
  }

  test('selecting child removes selected ancestor', () {
    final controller = TreeController<String>(
      roots: <TreeNode<String>>[nestedTree()],
    );

    controller.toggleSelection('folder');
    controller.toggleSelection('file');

    expect(controller.selectedNodeIds, isNot(contains('folder')));
    expect(controller.selectedNodeIds, contains('file'));
  });

  test('selecting ancestor removes selected descendants', () {
    final controller = TreeController<String>(
      roots: <TreeNode<String>>[nestedTree()],
    );

    controller.toggleSelection('file');
    controller.toggleSelection('folder');

    expect(controller.selectedNodeIds, contains('folder'));
    expect(controller.selectedNodeIds, isNot(contains('file')));
  });

  test('range selection prunes descendants when ancestor is selected', () {
    final controller = TreeController<String>(
      roots: <TreeNode<String>>[nestedTree()],
    );

    controller.setSelectedNodeId('folder');
    controller.selectRange('file');

    expect(controller.selectedNodeIds, contains('folder'));
    expect(controller.selectedNodeIds, isNot(contains('file')));
  });

  testWidgets('selects on primary pointer down before tap resolves', (
    WidgetTester tester,
  ) async {
    final controller = TreeController<String>(
      roots: <TreeNode<String>>[TreeNode<String>(id: 'node', data: 'Node')],
    );
    final tappedIds = <String>[];

    await tester.pumpWidget(
      buildTree(
        controller: controller,
        logic: TreeViewConfig<String>(
          onNodeTap: tappedIds.add,
          onNodeDoubleTap: (_) {},
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Node')),
      buttons: kPrimaryButton,
    );

    expect(controller.selectedNodeId, 'node');
    expect(tappedIds, isEmpty);

    await gesture.up();
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('does not apply multi-selection twice for one click', (
    WidgetTester tester,
  ) async {
    final controller = TreeController<String>(
      roots: <TreeNode<String>>[
        TreeNode<String>(id: 'node_a', data: 'Node A'),
        TreeNode<String>(id: 'node_b', data: 'Node B'),
      ],
    );

    await tester.pumpWidget(
      buildTree(
        controller: controller,
        logic: const TreeViewConfig<String>(
          selectionMode: SelectionMode.multiple,
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Node A'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(controller.selectedNodeIds, contains('node_a'));
  });

  testWidgets('expands tap-triggered nodes on primary pointer down', (
    WidgetTester tester,
  ) async {
    final root = TreeNode<String>(
      id: 'root',
      data: 'Root',
      children: <TreeNode<String>>[
        TreeNode<String>(id: 'child', data: 'Child'),
      ],
    );
    final controller = TreeController<String>(roots: <TreeNode<String>>[root]);
    final tappedIds = <String>[];

    await tester.pumpWidget(
      buildTree(
        controller: controller,
        logic: TreeViewConfig<String>(onNodeTap: tappedIds.add),
      ),
    );

    expect(find.text('Child'), findsNothing);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Root')),
      buttons: kPrimaryButton,
    );

    expect(root.isExpanded, isTrue);
    expect(tappedIds, isEmpty);

    await tester.pump();
    expect(find.text('Child'), findsOneWidget);

    await gesture.up();
  });

  testWidgets('tapping caret does not toggle expansion twice', (
    WidgetTester tester,
  ) async {
    final root = TreeNode<String>(
      id: 'root',
      data: 'Root',
      children: <TreeNode<String>>[
        TreeNode<String>(id: 'child', data: 'Child'),
      ],
    );
    final controller = TreeController<String>(roots: <TreeNode<String>>[root]);

    await tester.pumpWidget(buildTree(controller: controller));

    await tester.tap(find.byKey(const Key('expansion_caret_root')));
    await tester.pump();

    expect(root.isExpanded, isTrue);
    expect(find.text('Child'), findsOneWidget);
  });

  testWidgets('ignored primary pointer down does not expand row', (
    WidgetTester tester,
  ) async {
    final root = TreeNode<String>(
      id: 'root',
      data: 'Root',
      children: <TreeNode<String>>[
        TreeNode<String>(id: 'child', data: 'Child'),
      ],
    );
    final controller = TreeController<String>(roots: <TreeNode<String>>[root]);

    await tester.pumpWidget(
      buildTree(
        controller: controller,
        logic: TreeViewConfig<String>(
          ignorePrimaryPointerDown: (node, event) => true,
        ),
      ),
    );

    await tester.tap(find.text('Root'));
    await tester.pump();

    expect(root.isExpanded, isFalse);
    expect(find.text('Child'), findsNothing);
  });

  testWidgets('does not expand folders during ctrl multi-select', (
    WidgetTester tester,
  ) async {
    final root = TreeNode<String>(
      id: 'root',
      data: 'Root',
      children: <TreeNode<String>>[
        TreeNode<String>(id: 'child', data: 'Child'),
      ],
    );
    final controller = TreeController<String>(roots: <TreeNode<String>>[root]);

    await tester.pumpWidget(
      buildTree(
        controller: controller,
        logic: const TreeViewConfig<String>(
          selectionMode: SelectionMode.multiple,
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Root')),
      buttons: kPrimaryButton,
    );

    expect(controller.selectedNodeIds, contains('root'));
    expect(root.isExpanded, isFalse);

    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('does not collapse a tap-expanded node on double-click down', (
    WidgetTester tester,
  ) async {
    final root = TreeNode<String>(
      id: 'root',
      data: 'Root',
      children: <TreeNode<String>>[
        TreeNode<String>(id: 'child', data: 'Child'),
      ],
    );
    final controller = TreeController<String>(roots: <TreeNode<String>>[root]);
    final doubleTappedIds = <String>[];

    await tester.pumpWidget(
      buildTree(
        controller: controller,
        logic: TreeViewConfig<String>(onNodeDoubleTap: doubleTappedIds.add),
      ),
    );

    final firstClick = await tester.startGesture(
      tester.getCenter(find.text('Root')),
      buttons: kPrimaryButton,
    );
    expect(root.isExpanded, isTrue);
    await firstClick.up();
    await tester.pump();

    final secondClick = await tester.startGesture(
      tester.getCenter(find.text('Root')),
      buttons: kPrimaryButton,
    );

    expect(root.isExpanded, isTrue);

    await secondClick.up();
    await tester.pump();

    expect(root.isExpanded, isTrue);
    expect(doubleTappedIds, contains('root'));
  });
}
