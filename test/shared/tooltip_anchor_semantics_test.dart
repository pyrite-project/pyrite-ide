import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';

/// A tooltip popup is grafted into the semantics tree on the node holding its
/// anchor's traversal-parent identifier. When two anchors resolve to one node
/// only one identifier survives, the losing popup names a parent no node holds,
/// and every frame after that throws:
///
/// ```
/// 'package:flutter/src/semantics/semantics.dart': Failed assertion:
///   '!child.attached': is not true.
/// ```
///
/// while the Windows bridge drops whole accessibility updates. This is
/// flutter/flutter#182444, worked around by [TooltipAnchor]'s own container
/// node.
///
/// These tests pin the invariant: every grafted popup finds the node its
/// identifier points at, and every visible anchor keeps an identifier of its
/// own. They cover the shapes this app actually builds -- adjacent toolbar
/// buttons inside a scrollable (the device page, the status bar) and a tooltip
/// inside a `MenuAnchor` builder (the serial filter menu).
void main() {
  List<SemanticsNode> flatten(SemanticsNode root) {
    final nodes = <SemanticsNode>[];
    void visit(SemanticsNode node) {
      nodes.add(node);
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(root);
    return nodes;
  }

  List<SemanticsNode> currentNodes(WidgetTester tester) => flatten(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );

  /// Identifier-holding nodes, read off the node itself: a merging ancestor
  /// folds its descendants' data into `getSemanticsData()`, which would hide
  /// exactly the collision these tests look for.
  Set<Object> anchors(List<SemanticsNode> nodes) => nodes
      .map((node) => node.traversalParentIdentifier)
      .whereType<Object>()
      .toSet();

  List<SemanticsNode> popups(List<SemanticsNode> nodes) =>
      nodes.where((node) => node.traversalChildIdentifier != null).toList();

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    return gesture;
  }

  Future<void> hover(
    WidgetTester tester,
    TestGesture gesture,
    Finder finder,
  ) async {
    await gesture.moveTo(tester.getCenter(finder));
    // Past the tooltip's wait duration, so the popup is really in the tree.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 300));
  }

  void expectNoOrphanedPopups(WidgetTester tester, {required int anchorCount}) {
    final nodes = currentNodes(tester);
    final held = anchors(nodes);
    expect(held, hasLength(anchorCount));
    final grafted = popups(nodes);
    expect(grafted, isNotEmpty, reason: 'no popup was grafted at all');
    for (final popup in grafted) {
      expect(
        held,
        contains(popup.traversalChildIdentifier),
        reason: 'semantics node #${popup.id} names a parent nobody holds',
      );
    }
  }

  testWidgets('adjacent anchors in a scrollable keep separate identifiers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              Row(
                children: [
                  TooltipAnchor(
                    message: 'refresh',
                    child: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                  TooltipAnchor(
                    message: 'disconnect',
                    child: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.link_off),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final gesture = await mouse(tester);
    await hover(tester, gesture, find.byIcon(Icons.link_off));
    expect(find.text('disconnect'), findsOneWidget);

    expectNoOrphanedPopups(tester, anchorCount: 2);
    semantics.dispose();
  });

  testWidgets('a tooltip inside a menu anchor keeps its own identifier', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MenuAnchor(
              menuChildren: const [MenuItemButton(child: Text('only item'))],
              builder: (context, controller, _) => TooltipAnchor(
                message: 'filter ports',
                child: IconButton(
                  onPressed: controller.open,
                  icon: const Icon(Icons.filter_list),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await mouse(tester);
    await hover(tester, gesture, find.byType(IconButton));
    expect(find.text('filter ports'), findsOneWidget);

    expectNoOrphanedPopups(tester, anchorCount: 2);
    semantics.dispose();
  });

  testWidgets('an anchor whose child carries button semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    // The find-bar toggles carry `Semantics(button: true)` inside the anchor;
    // the container node has to stay outside the tooltip either way.
    Widget toggle(String message) => TooltipAnchor(
      message: message,
      child: Semantics(
        container: true,
        button: true,
        child: IconButton(
          onPressed: () {},
          icon: const Icon(Icons.text_fields),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              Row(children: [toggle('case sensitive'), toggle('regex')]),
            ],
          ),
        ),
      ),
    );
    final gesture = await mouse(tester);
    await hover(tester, gesture, find.byIcon(Icons.text_fields).last);
    expect(find.text('regex'), findsOneWidget);

    expectNoOrphanedPopups(tester, anchorCount: 2);
    semantics.dispose();
  });
}
