// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/shared/tabbed_view/native_tab_drag.dart';
import 'package:pyrite_ide/shared/tabbed_view/tabbed_view.dart' as pyrite;
import 'package:pyrite_ide/shared/tabbed_view/tabs_area.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:tabbed_view/src/internal/tabbed_view_provider.dart';
import 'package:tabbed_view/tabbed_view.dart';

void main() {
  group('native tab edge auto-scroll', () {
    test('uses mirrored velocities at both edges', () {
      final leading = nativeTabAutoScrollVelocity(
        coordinate: 14,
        viewportExtent: 300,
      );
      final trailing = nativeTabAutoScrollVelocity(
        coordinate: 286,
        viewportExtent: 300,
      );

      expect(leading, lessThan(0));
      expect(trailing, greaterThan(0));
      expect(leading.abs(), closeTo(trailing.abs(), 0.0001));
      expect(
        nativeTabAutoScrollVelocity(coordinate: -20, viewportExtent: 300),
        -480,
      );
      expect(
        nativeTabAutoScrollVelocity(coordinate: 320, viewportExtent: 300),
        480,
      );
    });

    test('accelerates toward an edge and stops outside the edge zones', () {
      final shallow = nativeTabAutoScrollVelocity(
        coordinate: 48,
        viewportExtent: 300,
      );
      final deep = nativeTabAutoScrollVelocity(
        coordinate: 8,
        viewportExtent: 300,
      );

      expect(deep.abs(), greaterThan(shallow.abs()));
      expect(
        nativeTabAutoScrollVelocity(coordinate: 150, viewportExtent: 300),
        0,
      );
    });
  });

  test('native tab drag data resolves to its in-memory source', () {
    final tab = TabData(text: 'first');
    final controller = TabbedViewController([tab]);
    addTearDown(controller.dispose);

    final registration = NativeTabDragRegistry.register(
      controller: controller,
      tab: tab,
      dragScope: 'editor',
    );
    addTearDown(registration.dispose);

    final source = NativeTabDragRegistry.sourceForLocalData(
      registration.localData,
    );
    expect(source, isNotNull);
    expect(source!.controller, same(controller));
    expect(source.tab, same(tab));
    expect(source.dragScope, 'editor');

    registration.dispose();
    expect(
      NativeTabDragRegistry.sourceForLocalData(registration.localData),
      isNull,
    );
  });

  test('native tab drag item includes data required by Android', () {
    final tab = TabData(text: 'first');
    final controller = TabbedViewController([tab]);
    addTearDown(controller.dispose);
    final registration = NativeTabDragRegistry.register(
      controller: controller,
      tab: tab,
      dragScope: 'editor',
    );
    addTearDown(registration.dispose);

    final item = createNativeTabDragItem(registration, tab.text);

    expect(item.localData, registration.localData);
    expect(item.data, isNotEmpty);
  });

  group('native tab drag geometry', () {
    late TabData tab;
    late TabbedViewController controller;

    setUp(() {
      tab = TabData(text: 'source');
      controller = TabbedViewController([tab]);
    });
    tearDown(() => controller.dispose());

    NativeTabDragSource source({required double grabX}) {
      return NativeTabDragSource(
        controller: controller,
        tab: tab,
        dragScope: 'editor',
        dragStartGlobalPosition: Offset(grabX, 20),
        sourceGlobalRect: const Rect.fromLTWH(100, 0, 100, 40),
      );
    }

    test('projects the trailing edge while moving right', () {
      expect(
        source(
          grabX: 125,
        ).projectDropPosition(const Offset(175, 20), Axis.horizontal),
        const Offset(250, 20),
      );
      expect(
        source(
          grabX: 190,
        ).projectDropPosition(const Offset(240, 20), Axis.horizontal),
        const Offset(250, 20),
      );
    });

    test('projects the leading edge while moving left', () {
      expect(
        source(
          grabX: 125,
        ).projectDropPosition(const Offset(75, 20), Axis.horizontal),
        const Offset(50, 20),
      );
      expect(
        source(
          grabX: 190,
        ).projectDropPosition(const Offset(140, 20), Axis.horizontal),
        const Offset(50, 20),
      );
    });

    test('keeps the source center while the drag has not moved', () {
      expect(
        source(
          grabX: 125,
        ).projectDropPosition(const Offset(125, 20), Axis.horizontal),
        const Offset(150, 20),
      );
    });
  });

  group('native tab strip drop target', () {
    const horizontalRects = <Rect>[
      Rect.fromLTWH(20, 10, 80, 30),
      Rect.fromLTWH(120, 10, 100, 30),
      Rect.fromLTWH(240, 10, 60, 30),
    ];

    test('uses the first insertion point in leading space', () {
      final target = resolveNativeTabStripDropTarget(
        tabRects: horizontalRects,
        globalPosition: const Offset(0, 20),
        axis: Axis.horizontal,
      );

      expect(target?.insertionIndex, 0);
      expect(target?.indicatorGlobalPosition, horizontalRects.first.centerLeft);
    });

    test('uses the shared insertion point throughout a tab gap', () {
      final target = resolveNativeTabStripDropTarget(
        tabRects: horizontalRects,
        globalPosition: const Offset(110, 20),
        axis: Axis.horizontal,
      );

      expect(target?.insertionIndex, 1);
      expect(target?.indicatorGlobalPosition, horizontalRects[1].centerLeft);
    });

    test('uses the final insertion point in trailing blank space', () {
      final target = resolveNativeTabStripDropTarget(
        tabRects: horizontalRects,
        globalPosition: const Offset(500, 20),
        axis: Axis.horizontal,
      );

      expect(target?.insertionIndex, horizontalRects.length);
      expect(target?.indicatorGlobalPosition, horizontalRects.last.centerRight);
    });

    test('resolves vertical tab strips on the main axis', () {
      const rects = <Rect>[
        Rect.fromLTWH(10, 20, 80, 40),
        Rect.fromLTWH(10, 80, 80, 40),
      ];

      final target = resolveNativeTabStripDropTarget(
        tabRects: rects,
        globalPosition: const Offset(30, 70),
        axis: Axis.vertical,
      );

      expect(target?.insertionIndex, 1);
      expect(target?.indicatorGlobalPosition, rects[1].topCenter);
    });

    test('moves to an adjacent slot after half-width overlap', () {
      const rects = <Rect>[
        Rect.fromLTWH(0, 0, 100, 40),
        Rect.fromLTWH(100, 0, 100, 40),
        Rect.fromLTWH(200, 0, 100, 40),
      ];
      final tab = TabData(text: 'source');
      final controller = TabbedViewController([tab]);
      addTearDown(controller.dispose);
      final source = NativeTabDragSource(
        controller: controller,
        tab: tab,
        dragScope: 'editor',
        dragStartGlobalPosition: const Offset(125, 20),
        sourceGlobalRect: rects[1],
      );

      NativeTabStripDropTarget? targetAt(double x) {
        return resolveNativeTabStripDropTarget(
          tabRects: rects,
          globalPosition: source.projectDropPosition(
            Offset(x, 20),
            Axis.horizontal,
          ),
          axis: Axis.horizontal,
        );
      }

      expect(targetAt(174)?.insertionIndex, 2);
      expect(targetAt(176)?.insertionIndex, 3);
      expect(targetAt(76)?.insertionIndex, 1);
      expect(targetAt(74)?.insertionIndex, 0);
    });

    test('keeps an activated trend through imprecise final positions', () {
      const rects = <Rect>[
        Rect.fromLTWH(0, 0, 100, 40),
        Rect.fromLTWH(100, 0, 100, 40),
        Rect.fromLTWH(200, 0, 100, 40),
      ];
      final first = TabData(text: 'first');
      final sourceTab = TabData(text: 'source');
      final third = TabData(text: 'third');
      final controller = TabbedViewController([first, sourceTab, third]);
      addTearDown(controller.dispose);
      final source = NativeTabDragSource(
        controller: controller,
        tab: sourceTab,
        dragScope: 'editor',
        dragStartGlobalPosition: const Offset(125, 20),
        sourceGlobalRect: rects[1],
      );

      NativeTabStripDropTarget? targetFor(int trendDirection) {
        return resolveNativeTabStripTrendDropTarget(
          tabRects: rects,
          globalPosition: const Offset(130, 20),
          axis: Axis.horizontal,
          source: source,
          targetController: controller,
          trendDirection: trendDirection,
        );
      }

      expect(targetFor(0)?.insertionIndex, 2);
      expect(targetFor(1)?.insertionIndex, 3);
      expect(targetFor(-1)?.insertionIndex, 0);
    });
  });

  test('trend fallback moves one slot without a tab-strip drop', () {
    final first = TabData(text: 'first');
    final sourceTab = TabData(text: 'source');
    final third = TabData(text: 'third');
    final fourth = TabData(text: 'fourth');
    final controller = TabbedViewController([first, sourceTab, third, fourth]);
    addTearDown(controller.dispose);
    final registration = NativeTabDragRegistry.register(
      controller: controller,
      tab: sourceTab,
      dragScope: 'editor',
      dragStartGlobalPosition: const Offset(150, 20),
    );
    addTearDown(registration.dispose);
    final provider = _provider(controller, draggingTabIndex: 1);

    final reordered = performNativeTabTrendFallback(
      provider: provider,
      registration: registration,
      axis: Axis.horizontal,
      globalPosition: const Offset(365, 100),
    );

    expect(reordered, isTrue);
    expect(controller.tabs, orderedEquals([first, third, sourceTab, fourth]));
    expect(registration.dropHandled, isTrue);
    expect(
      performNativeTabTrendFallback(
        provider: provider,
        registration: registration,
        axis: Axis.horizontal,
        globalPosition: const Offset(50, 100),
      ),
      isFalse,
    );
  });

  test('trend fallback ignores movement below its activation distance', () {
    final first = TabData(text: 'first');
    final sourceTab = TabData(text: 'source');
    final controller = TabbedViewController([first, sourceTab]);
    addTearDown(controller.dispose);
    final registration = NativeTabDragRegistry.register(
      controller: controller,
      tab: sourceTab,
      dragScope: 'editor',
      dragStartGlobalPosition: const Offset(150, 20),
      sourceGlobalRect: const Rect.fromLTWH(100, 0, 100, 40),
    );
    addTearDown(registration.dispose);

    expect(
      performNativeTabTrendFallback(
        provider: _provider(controller, draggingTabIndex: 1),
        registration: registration,
        axis: Axis.horizontal,
        globalPosition: const Offset(160, 200),
      ),
      isFalse,
    );
    expect(controller.tabs, orderedEquals([first, sourceTab]));
    expect(registration.dropHandled, isFalse);
  });

  test('trend fallback honors a tracked insertion target', () {
    final first = TabData(text: 'first');
    final second = TabData(text: 'second');
    final third = TabData(text: 'third');
    final sourceTab = TabData(text: 'source');
    final controller = TabbedViewController([first, second, third, sourceTab]);
    addTearDown(controller.dispose);
    final registration = NativeTabDragRegistry.register(
      controller: controller,
      tab: sourceTab,
      dragScope: 'editor',
      dragStartGlobalPosition: const Offset(400, 20),
    );
    registration.intendedInsertionIndex = 1;
    addTearDown(registration.dispose);

    final reordered = performNativeTabTrendFallback(
      provider: _provider(controller, draggingTabIndex: 3),
      registration: registration,
      axis: Axis.horizontal,
      globalPosition: const Offset(100, 100),
    );

    expect(reordered, isTrue);
    expect(controller.tabs, orderedEquals([first, sourceTab, second, third]));
  });

  testWidgets('native drop region reorders a tab using local drag data', (
    tester,
  ) async {
    final first = TabData(text: 'first');
    final second = TabData(text: 'second');
    final third = TabData(text: 'third');
    final controller = TabbedViewController([first, second, third]);
    addTearDown(controller.dispose);

    final registration = NativeTabDragRegistry.register(
      controller: controller,
      tab: first,
      dragScope: 'editor',
    );
    addTearDown(registration.dispose);
    final session = _FakeDropSession(registration.localData);

    final provider = TabbedViewProvider(
      controller: controller,
      contentBuilder: null,
      tabReorderEnabled: true,
      contentClip: true,
      unselectedTabButtonsBehavior: UnselectedTabButtonsBehavior.allDisabled,
      closeButtonTooltip: null,
      tabsAreaButtonsBuilder: null,
      tabRemoveInterceptor: null,
      onTabSecondaryTap: null,
      onTabDrag: (_) {},
      draggingTabIndex: 0,
      onDraggableBuild: null,
      canDrop: null,
      onBeforeDropAccept: null,
      dragScope: 'editor',
      trailing: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 40,
            child: NativeTabDropRegion(
              provider: provider,
              position: TabBarPosition.top,
              targetTab: third,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );

    final region = tester.widget<DropRegion>(find.byType(DropRegion));
    final position = DropPosition(
      local: const Offset(90, 20),
      global: tester.getCenter(find.byType(NativeTabDropRegion)),
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

    expect(controller.tabs, orderedEquals([second, third, first]));
  });

  testWidgets('native tab strip accepts a drop in its blank area', (
    tester,
  ) async {
    final first = TabData(text: 'first');
    final second = TabData(text: 'second');
    final third = TabData(text: 'third');
    final controller = TabbedViewController([first, second, third]);
    addTearDown(controller.dispose);

    final registration = NativeTabDragRegistry.register(
      controller: controller,
      tab: first,
      dragScope: 'editor',
    );
    addTearDown(registration.dispose);
    final session = _FakeDropSession(registration.localData);
    final provider = _provider(controller, draggingTabIndex: 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 40,
            child: NativeTabStripDropRegion(
              provider: provider,
              position: TabBarPosition.top,
              resolveTarget: (_, _, _) => const NativeTabStripDropTarget(
                insertionIndex: 3,
                indicatorGlobalPosition: Offset(250, 20),
              ),
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );

    final region = tester.widget<DropRegion>(find.byType(DropRegion));
    final position = DropPosition(
      local: const Offset(250, 20),
      global: tester.getCenter(find.byType(NativeTabStripDropRegion)),
    );
    final operation = await Future<DropOperation>.value(
      region.onDropOver(DropOverEvent(session: session, position: position)),
    );
    expect(operation, DropOperation.move);
    await tester.pump();

    await region.onPerformDrop(
      PerformDropEvent(
        session: session,
        position: position,
        acceptedOperation: operation,
      ),
    );

    expect(controller.tabs, orderedEquals([second, third, first]));
  });

  testWidgets('native tab strip retains an activated trend until drop', (
    tester,
  ) async {
    final first = TabData(text: 'first');
    final sourceTab = TabData(text: 'source');
    final third = TabData(text: 'third');
    final controller = TabbedViewController([first, sourceTab, third]);
    addTearDown(controller.dispose);
    const rects = <Rect>[
      Rect.fromLTWH(0, 0, 100, 40),
      Rect.fromLTWH(100, 0, 100, 40),
      Rect.fromLTWH(200, 0, 100, 40),
    ];
    final registration = NativeTabDragRegistry.register(
      controller: controller,
      tab: sourceTab,
      dragScope: 'editor',
      dragStartGlobalPosition: const Offset(150, 20),
      sourceGlobalRect: rects[1],
    );
    addTearDown(registration.dispose);
    final session = _FakeDropSession(registration.localData);
    final provider = _provider(controller, draggingTabIndex: 1);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 40,
          child: NativeTabStripDropRegion(
            provider: provider,
            position: TabBarPosition.top,
            resolveTarget: (position, source, trendDirection) =>
                resolveNativeTabStripTrendDropTarget(
                  tabRects: rects,
                  globalPosition: position,
                  axis: Axis.horizontal,
                  source: source,
                  targetController: controller,
                  trendDirection: trendDirection,
                ),
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );

    final region = tester.widget<DropRegion>(find.byType(DropRegion));
    DropPosition position(double x) =>
        DropPosition(local: Offset(x, 20), global: Offset(x, 20));
    await Future<DropOperation>.value(
      region.onDropOver(
        DropOverEvent(session: session, position: position(180)),
      ),
    );
    await Future<DropOperation>.value(
      region.onDropOver(
        DropOverEvent(session: session, position: position(155)),
      ),
    );

    await region.onPerformDrop(
      PerformDropEvent(
        session: session,
        position: position(155),
        acceptedOperation: DropOperation.move,
      ),
    );

    expect(controller.tabs, orderedEquals([first, third, sourceTab]));
  });

  testWidgets('native tab draggable uses super drag gesture widgets', (
    tester,
  ) async {
    final tab = TabData(text: 'first');
    final controller = TabbedViewController([tab]);
    addTearDown(controller.dispose);
    final provider = _provider(controller, draggingTabIndex: null);

    await tester.pumpWidget(
      MaterialApp(
        home: NativeTabDraggable(
          provider: provider,
          tab: tab,
          index: 0,
          config: DraggableConfig.defaultConfig,
          feedback: const Text('preview'),
          child: const Text('tab'),
        ),
      ),
    );

    final dragItem = tester.widget<DragItemWidget>(find.byType(DragItemWidget));
    expect(dragItem.liftBuilder, isNotNull);
    expect(dragItem.dragBuilder, isNotNull);
    expect(find.byType(DraggableWidget), findsOneWidget);
    expect(find.byType(Draggable<Object>), findsNothing);
    expect(find.byType(LongPressDraggable<Object>), findsNothing);
  });

  testWidgets('starting a tab drag keeps the native drag source mounted', (
    tester,
  ) async {
    final controller = TabbedViewController([
      TabData(text: 'first'),
      TabData(text: 'second'),
    ]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: SizedBox(
            width: 400,
            height: 200,
            child: pyrite.TabbedView(controller: controller),
          ),
        ),
      ),
    );

    final before = tester
        .stateList<DragItemWidgetState>(find.byType(DragItemWidget))
        .toList(growable: false);
    expect(find.byType(NativeTabStripDropRegion), findsOneWidget);
    expect(find.byType(NativeTabDropRegion), findsOneWidget);
    final source = tester.widget<NativeTabDraggable>(
      find.byType(NativeTabDraggable).first,
    );

    source.provider.onTabDrag(0);
    await tester.pump();

    final after = tester
        .stateList<DragItemWidgetState>(find.byType(DragItemWidget))
        .toList(growable: false);
    expect(after, hasLength(before.length));
    expect(after.first, same(before.first));

    source.provider.onTabDrag(null);
    await tester.pump();
  });

  testWidgets('tab reordering preserves the drag scroll position', (
    tester,
  ) async {
    final controller = TabbedViewController([
      TabData(text: 'first', textSize: 140),
      TabData(text: 'source', textSize: 140),
      TabData(text: 'third', textSize: 140),
      TabData(text: 'fourth', textSize: 140),
    ]);
    controller.selectedIndex = 1;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: SizedBox(
            width: 260,
            height: 200,
            child: pyrite.TabbedView(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollView = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    final scrollable = find.descendant(
      of: scrollView,
      matching: find.byType(Scrollable),
    );
    final scrollPosition = tester.state<ScrollableState>(scrollable).position;
    scrollPosition.jumpTo(0);
    await tester.pump();

    final source = tester.widget<NativeTabDraggable>(
      find.byType(NativeTabDraggable).at(1),
    );
    source.provider.onTabDrag(1);
    await tester.pump();

    controller.reorderTab(1, 3);
    source.provider.onTabDrag(null);
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.tabs[2].text, 'source');
    expect(scrollPosition.pixels, 0);
  });

  testWidgets('tab strip tracks a target while the pointer is below it', (
    tester,
  ) async {
    final first = TabData(text: 'first', textSize: 100);
    final second = TabData(text: 'second', textSize: 100);
    final third = TabData(text: 'third', textSize: 100);
    final sourceTab = TabData(text: 'source', textSize: 100);
    final controller = TabbedViewController([first, second, third, sourceTab]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: SizedBox(
            width: 300,
            height: 200,
            child: pyrite.TabbedView(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sourceFinder = find.byType(NativeTabDraggable).at(3);
    final sourceWidget = tester.widget<NativeTabDraggable>(sourceFinder);
    final sourceRect = tester.getRect(sourceFinder);
    final targetCenter = tester.getCenter(
      find.byType(NativeTabDraggable).at(1),
    );
    final registration = NativeTabDragRegistry.register(
      controller: controller,
      tab: sourceTab,
      dragScope: 'editor',
      dragStartGlobalPosition: sourceRect.center,
      sourceGlobalRect: sourceRect,
    );
    addTearDown(registration.dispose);
    final session = _FakeDropSession(registration.localData);
    final globalPosition = Offset(targetCenter.dx, targetCenter.dy + 100);

    final monitor = tester.widget<DropMonitor>(find.byType(DropMonitor));
    monitor.onDropOver?.call(
      MonitorDropOverEvent(
        session: session,
        position: DropPosition(
          local: Offset(targetCenter.dx, 100),
          global: globalPosition,
        ),
        isInside: false,
      ),
    );

    expect(registration.intendedInsertionIndex, 1);
    expect(
      performNativeTabTrendFallback(
        provider: sourceWidget.provider,
        registration: registration,
        axis: Axis.horizontal,
        globalPosition: globalPosition,
      ),
      isTrue,
    );
    expect(controller.tabs, orderedEquals([first, sourceTab, second, third]));
  });

  test('only successful native operations count as accepted', () {
    expect(nativeTabDragWasAccepted(DropOperation.move), isTrue);
    expect(nativeTabDragWasAccepted(DropOperation.copy), isTrue);
    expect(nativeTabDragWasAccepted(DropOperation.link), isTrue);
    expect(nativeTabDragWasAccepted(DropOperation.none), isFalse);
    expect(nativeTabDragWasAccepted(DropOperation.userCancelled), isFalse);
    expect(nativeTabDragWasAccepted(DropOperation.forbidden), isFalse);
  });
}

TabbedViewProvider _provider(
  TabbedViewController controller, {
  required int? draggingTabIndex,
}) {
  return TabbedViewProvider(
    controller: controller,
    contentBuilder: null,
    tabReorderEnabled: true,
    contentClip: true,
    unselectedTabButtonsBehavior: UnselectedTabButtonsBehavior.allDisabled,
    closeButtonTooltip: null,
    tabsAreaButtonsBuilder: null,
    tabRemoveInterceptor: null,
    onTabSecondaryTap: null,
    onTabDrag: (_) {},
    draggingTabIndex: draggingTabIndex,
    onDraggableBuild: null,
    canDrop: null,
    onBeforeDropAccept: null,
    dragScope: 'editor',
    trailing: null,
  );
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
