// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/shared/tabbed_view/native_tab_drag.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:tabbed_view/src/internal/tabbed_view_provider.dart';
import 'package:tabbed_view/tabbed_view.dart';

void main() {
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

    expect(find.byType(DragItemWidget), findsOneWidget);
    expect(find.byType(DraggableWidget), findsOneWidget);
    expect(find.byType(Draggable<Object>), findsNothing);
    expect(find.byType(LongPressDraggable<Object>), findsNothing);
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
