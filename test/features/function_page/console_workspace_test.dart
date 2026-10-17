import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/features/function_page.dart';
import 'package:pyrite_ide/features/function_page/console_tabs.dart';

const _workspaceKey = ValueKey<String>('test-console-workspace');
const _primaryContentKey = ValueKey<String>('test-primary-content');
const _consoleContentKey = ValueKey<String>('test-console-content');

void main() {
  testWidgets('dragging console to the top hides the editor content', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpWorkspace(tester, container);

    await _dragHandle(tester, -600);

    expect(
      tester.getSize(find.byKey(_primaryContentKey)).height,
      closeTo(44, 0.01),
    );
    expect(
      tester.getRect(find.byKey(_consoleContentKey)).bottom,
      closeTo(tester.getRect(find.byKey(_workspaceKey)).bottom, 0.01),
    );
    expect(find.bySemanticsLabel('调整底部面板大小'), findsOneWidget);
  });

  testWidgets('dragging a maximized console down restores the editor', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpWorkspace(tester, container);
    await _dragHandle(tester, -600);

    await _dragHandle(tester, 180);

    expect(
      tester.getSize(find.byKey(_primaryContentKey)).height,
      greaterThan(44),
    );
  });

  testWidgets('hiding a maximized console restores the primary pane', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpWorkspace(tester, container);
    await _dragHandle(tester, -600);

    container.read(consolePageShow.notifier).state = false;
    await tester.pump();

    expect(find.byKey(_consoleContentKey), findsNothing);
    expect(
      tester.getRect(find.byKey(_primaryContentKey)),
      tester.getRect(find.byKey(_workspaceKey)),
    );

    container.read(consolePageShow.notifier).state = true;
    await tester.pump();

    expect(find.byKey(_consoleContentKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(_primaryContentKey)).height,
      greaterThan(240),
    );
  });

  testWidgets('the console docks to the right of the editor', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpWorkspace(tester, container);

    container.read(consoleDockSideProvider.notifier).state = PaneEdge.right;
    await tester.pump();

    final workspace = tester.getRect(find.byKey(_workspaceKey));
    final primary = tester.getRect(find.byKey(_primaryContentKey));
    final console = tester.getRect(find.byKey(_consoleContentKey));
    // Side by side: both panes span the full height and the console owns the
    // trailing edge, separated from the editor only by the resize dragger.
    expect(primary.height, closeTo(workspace.height, 0.01));
    expect(console.height, closeTo(workspace.height, 0.01));
    expect(primary.left, closeTo(workspace.left, 0.01));
    expect(console.right, closeTo(workspace.right, 0.01));
    expect(console.left, greaterThanOrEqualTo(primary.right));
    expect(console.left - primary.right, lessThan(20));
  });

  testWidgets('the console docks above the editor', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpWorkspace(tester, container);

    container.read(consoleDockSideProvider.notifier).state = PaneEdge.top;
    await tester.pump();

    final workspace = tester.getRect(find.byKey(_workspaceKey));
    final primary = tester.getRect(find.byKey(_primaryContentKey));
    final console = tester.getRect(find.byKey(_consoleContentKey));
    // Stacked with the console on top: it owns the leading edge and spans the
    // full width, mirroring how the bottom dock owns the trailing edge.
    expect(console.width, closeTo(workspace.width, 0.01));
    expect(console.top, closeTo(workspace.top, 0.01));
    expect(primary.bottom, closeTo(workspace.bottom, 0.01));
    expect(console.bottom, lessThanOrEqualTo(primary.top));
    expect(primary.top - console.bottom, lessThan(20));
  });

  testWidgets('the console strip hosts the same tabs as a tabbed view', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpDockableWorkspace(tester, container);

    final controller = container.read(consoleTabbedViewControllerProvider);
    expect(controller.tabs.length, 4);
    expect(
      controller.tabs.map((tab) => (tab.value! as ConsoleTabValue).id),
      orderedEquals(ConsoleTabId.values),
    );
    // A fresh strip selects its first tab, so the panel is never blank.
    expect(controller.selectedIndex, 0);
  });

  testWidgets('the console pane goes away once its last tab is dragged out', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpDockableWorkspace(tester, container);

    final console = container.read(consoleTabbedViewControllerProvider);
    expect(find.byType(ConsoleWorkspace), findsOneWidget);
    expect(console.tabs, hasLength(4));

    // Dragging every tab out empties the group, and a group with no tabs is not
    // a group: the pane disappears instead of leaving an empty strip behind.
    for (final tab in console.tabs.toList()) {
      console.removeTab(console.tabs.indexOf(tab));
    }
    await tester.pump();
    await tester.pumpAndSettle();

    expect(console.tabs, isEmpty);
    // The primary pane now owns the whole workspace.
    final primary = tester.getRect(find.byKey(_primaryContentKey));
    final workspace = tester.getRect(find.byKey(_workspaceKey));
    expect(primary.height, closeTo(workspace.height, 0.01));
  });

  testWidgets('an emptied console is brought back by the reset entry', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpDockableWorkspace(tester, container);

    // The pane -- and with it the menu that resets it -- is gone once the last
    // tab has been dragged out, so the way back has to exist independently.
    final console = container.read(consoleTabbedViewControllerProvider);
    console.removeTabs();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(console.tabs, isEmpty);

    resetTerminalLayout(container);

    await tester.pump();
    await tester.pumpAndSettle();
    // The default surfaces are back, and so is the pane that shows them.
    expect(container.read(consoleTabbedViewControllerProvider).tabs.length, 4);
    expect(
      container.read(consoleTabbedViewControllerProvider).selectedIndex,
      0,
    );
    expect(
      tester.getSize(find.byKey(_primaryContentKey)).height,
      lessThan(tester.getSize(find.byKey(_workspaceKey)).height),
    );
  });
}

Future<void> _pumpWorkspace(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await _pump(
    tester,
    container,
    const ColoredBox(key: _consoleContentKey, color: Colors.green),
  );
}

Future<void> _pumpDockableWorkspace(
  WidgetTester tester,
  ProviderContainer container,
) async {
  // No `console`, so the workspace builds the real console page and with it
  // the dock handle.
  await _pump(tester, container, null);
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget? console,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => buildShadcnLayer(
              context,
              SizedBox.expand(
                key: _workspaceKey,
                child: ConsoleWorkspace(
                  collapsedPrimarySize: 44,
                  primary: const ColoredBox(
                    key: _primaryContentKey,
                    color: Colors.blue,
                  ),
                  console: console,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _dragHandle(WidgetTester tester, double delta) async {
  final handle = find.byKey(ConsoleWorkspace.draggerKey);
  final gesture = await tester.startGesture(
    tester.getCenter(handle),
    kind: PointerDeviceKind.mouse,
    buttons: kPrimaryButton,
  );
  const steps = 12;
  for (var index = 0; index < steps; index++) {
    await gesture.moveBy(Offset(0, delta / steps));
  }
  await gesture.up();
  await tester.pump();
}
