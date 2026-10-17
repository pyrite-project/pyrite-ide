// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/features/function_page.dart';
import 'package:pyrite_ide/features/function_page/console_tabs.dart';
import 'package:pyrite_ide/features/function_page/editor_split_drop.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:pyrite_ide/shared/tabbed_view/native_tab_drag.dart';

void main() {
  testWidgets('a document is refused by a group outside the layout tree', (
    tester,
  ) async {
    // The console panel: a group the editor layout does not contain, which is
    // exactly what `accept` guards.
    final consoleTab = TabData(
      text: 'REPL',
      value: const ConsoleTabValue(ConsoleTabId.repl),
    );
    final consoleController = TabbedViewController([consoleTab]);
    addTearDown(consoleController.dispose);
    final fileTab = TabData(
      text: 'main.py',
      value: TabDataValue(type: 'file', filePath: '/tmp/main.py'),
    );
    final fileController = TabbedViewController([fileTab]);
    addTearDown(fileController.dispose);

    final registration = NativeTabDragRegistry.register(
      controller: fileController,
      tab: fileTab,
      dragScope: null,
    );
    addTearDown(registration.dispose);
    final session = _FakeDropSession(registration.localData);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Center(
            child: SizedBox(
              width: 800,
              height: 600,
              child: EditorSplitDropRegion(
                controller: consoleController,
                edgeTarget: consoleController,
                accept: (tab) => tab.value is ConsoleTabValue,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );

    final region = tester.widget<DropRegion>(find.byType(DropRegion));
    final center = tester.getCenter(find.byType(EditorSplitDropRegion));
    final position = DropPosition(local: center, global: center);

    // Not even the preview is offered: the drop could not be honoured.
    final operation = await Future<DropOperation>.value(
      region.onDropOver(DropOverEvent(session: session, position: position)),
    );
    expect(operation, DropOperation.none);

    await region.onPerformDrop(
      PerformDropEvent(
        session: session,
        position: position,
        acceptedOperation: operation,
      ),
    );

    // The document stays in the group it came from. Letting it through would
    // park it outside the layout tree, where persistence, the unsaved guard
    // and the open-file dedup cannot see it at all.
    expect(fileController.tabs, orderedEquals([fileTab]));
    expect(consoleController.tabs, orderedEquals([consoleTab]));
  });

  testWidgets('the console strip itself refuses a document', (tester) async {
    // The strip's own tab drop targets sit inside the panel's region and are
    // hit first; the region's `accept` alone would not keep a document out.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final console = container.read(consoleTabbedViewControllerProvider);
    final fileTab = TabData(
      text: 'main.py',
      value: TabDataValue(type: 'file', filePath: '/tmp/main.py'),
    );
    final fileController = TabbedViewController([fileTab]);
    addTearDown(fileController.dispose);
    final documentDrag = NativeTabDragRegistry.register(
      controller: fileController,
      tab: fileTab,
      dragScope: null,
    );
    addTearDown(documentDrag.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 800, height: 300, child: ConsolePage()),
          ),
        ),
      ),
    );

    final regions = tester.widgetList<DropRegion>(find.byType(DropRegion));
    expect(regions, isNotEmpty);
    final center = tester.getCenter(find.byType(ConsolePage));
    final position = DropPosition(local: center, global: center);
    for (final region in regions) {
      final operation = await Future<DropOperation>.value(
        region.onDropOver(
          DropOverEvent(
            session: _FakeDropSession(documentDrag.localData),
            position: position,
          ),
        ),
      );
      expect(operation, DropOperation.none);
    }
    expect(console.tabs.any((tab) => identical(tab, fileTab)), isFalse);
  });

  testWidgets('a console surface still splits a group outside the tree', (
    tester,
  ) async {
    final consoleTab = TabData(
      text: 'REPL',
      value: const ConsoleTabValue(ConsoleTabId.repl),
    );
    final consoleController = TabbedViewController([consoleTab]);
    addTearDown(consoleController.dispose);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // The group the panel's edges split: the editor's primary, which is what
    // the production wiring names.
    final primary = container.read(tabbedViewControllerProvider);

    final registration = NativeTabDragRegistry.register(
      controller: consoleController,
      tab: consoleTab,
      dragScope: null,
    );
    addTearDown(registration.dispose);
    final session = _FakeDropSession(registration.localData);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Center(
            child: SizedBox(
              width: 800,
              height: 600,
              child: EditorSplitDropRegion(
                controller: consoleController,
                edgeTarget: primary,
                accept: (tab) => tab.value is ConsoleTabValue,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );

    final region = tester.widget<DropRegion>(find.byType(DropRegion));
    final center = tester.getCenter(find.byType(EditorSplitDropRegion));
    // Near the left edge, so the drop asks for a split rather than a move.
    final position = DropPosition(
      local: center + const Offset(-390, 0),
      global: center + const Offset(-390, 0),
    );

    final operation = await Future<DropOperation>.value(
      region.onDropOver(DropOverEvent(session: session, position: position)),
    );
    expect(operation, DropOperation.move);

    await region.onPerformDrop(
      PerformDropEvent(
        session: session,
        position: position,
        acceptedOperation: operation,
      ),
    );

    // The panel's own surface is gone, and the editor area has a second group
    // holding it -- the new group is a leaf of the tree, not stranded outside.
    expect(consoleController.tabs, isEmpty);
    final controllers = allEditorControllers(container);
    expect(controllers, hasLength(2));
    // A drop near the left edge puts the new group first.
    expect(controllers.first.tabs, orderedEquals([consoleTab]));
  });

  testWidgets('the boundary strip promises the area, deeper drops the leaf', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // The region stands for a group that sits on the area's boundary: the
    // single group every fresh session starts with.
    final primary = container.read(tabbedViewControllerProvider);
    primary.addTab(TabData(text: 'second'));

    final registration = NativeTabDragRegistry.register(
      controller: primary,
      tab: primary.tabs.last,
      dragScope: null,
    );
    addTearDown(registration.dispose);
    final session = _FakeDropSession(registration.localData);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Center(
            child: SizedBox(
              width: 800,
              height: 600,
              child: EditorSplitDropRegion(
                controller: primary,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );

    final region = tester.widget<DropRegion>(find.byType(DropRegion));
    final center = tester.getCenter(find.byType(EditorSplitDropRegion));
    Future<DropOperation> hover(double dx) {
      return Future<DropOperation>.value(
        region.onDropOver(
          DropOverEvent(
            session: session,
            position: DropPosition(
              local: center + Offset(-400 + dx, 0),
              global: center + Offset(-400 + dx, 0),
            ),
          ),
        ),
      );
    }

    // The outermost strip of the boundary edge is the area's own gesture, and
    // the area draws that preview -- the root has no pane to draw it in.
    await hover(10);
    expect(container.read(editorAreaSplitPreviewProvider), PaneEdge.left);
    // The strip is wide enough to hit without aiming for the very edge.
    await hover(36);
    expect(container.read(editorAreaSplitPreviewProvider), PaneEdge.left);

    // Just inside the strip the promise falls back to the leaf, which draws
    // its own preview; nothing is published for the area any more.
    await hover(60);
    expect(container.read(editorAreaSplitPreviewProvider), isNull);

    await region.onPerformDrop(
      PerformDropEvent(
        session: session,
        position: DropPosition(
          local: center + const Offset(-340, 0),
          global: center + const Offset(-340, 0),
        ),
        acceptedOperation: DropOperation.move,
      ),
    );

    // So the drop splits the leaf: the new group is nested inside the group it
    // was dragged from, and the primary group stays in the tree.
    expect(container.read(editorAreaSplitPreviewProvider), isNull);
    final layout = container.read(editorLayoutProvider) as SplitLayout;
    expect(layout.children, hasLength(2));
    final created = layout.children[0] as GroupLayout;
    expect(created.controller.tabs.single.text, 'second');
    expect(
      layout.children[1],
      GroupLayout(container.read(tabbedViewControllerProvider)),
    );
  });
}

class _FakeDropSession with Diagnosticable implements DropSession {
  _FakeDropSession(Object localData)
    : items = <DropItem>[_FakeDropItem(localData)];

  @override
  final List<DropItem> items;

  @override
  Set<DropOperation> get allowedOperations => const {
    DropOperation.move,
    DropOperation.copy,
  };

  @override
  Listenable get onDisposed => _disposed;

  final ChangeNotifier _disposed = ChangeNotifier();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDropItem with Diagnosticable implements DropItem {
  const _FakeDropItem(this.localData);

  @override
  final Object? localData;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
