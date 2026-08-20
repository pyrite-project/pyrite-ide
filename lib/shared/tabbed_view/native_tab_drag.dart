// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:tabbed_view/src/draggable_config.dart';
import 'package:tabbed_view/src/draggable_data.dart';
import 'package:tabbed_view/src/internal/tabs_area/hidden_tabs.dart';
import 'package:tabbed_view/src/internal/tabs_area/tabs_area_buttons_widget.dart';
import 'package:tabbed_view/src/internal/tabbed_view_provider.dart';
import 'package:tabbed_view/src/tab_bar_position.dart';
import 'package:tabbed_view/src/tab_data.dart';
import 'package:tabbed_view/src/tabbed_view_controller.dart';
import 'package:tabbed_view/src/theme/side_tabs_layout.dart';
import 'package:tabbed_view/src/theme/tabs_area_cross_axis_fit.dart';
import 'package:tabbed_view/src/theme/theme_widget.dart';

const String _nativeTabDragKindKey = 'kind';
const String _nativeTabDragTokenKey = 'token';
const String _nativeTabDragKind = 'pyrite.tab';
const double _dropIndicatorExtent = 8;
const double _trendActivationDistance = 24;

@immutable
class NativeTabDragSource {
  const NativeTabDragSource({
    required this.controller,
    required this.tab,
    required this.dragScope,
    this.dragStartGlobalPosition,
    this.sourceGlobalRect,
  });

  final TabbedViewController controller;
  final TabData tab;
  final String? dragScope;
  final Offset? dragStartGlobalPosition;
  final Rect? sourceGlobalRect;

  DraggableData get draggableData => DraggableData(controller, tab, dragScope);

  double mainAxisDragDelta(Offset globalPosition, Axis axis) {
    final start = dragStartGlobalPosition;
    if (start == null) return 0;
    return axis == Axis.horizontal
        ? globalPosition.dx - start.dx
        : globalPosition.dy - start.dy;
  }

  Offset projectDropPosition(Offset globalPosition, Axis axis) {
    final start = dragStartGlobalPosition;
    final rect = sourceGlobalRect;
    if (start == null || rect == null) return globalPosition;

    final startCoordinate = axis == Axis.horizontal ? start.dx : start.dy;
    final currentCoordinate = axis == Axis.horizontal
        ? globalPosition.dx
        : globalPosition.dy;
    final leading = axis == Axis.horizontal ? rect.left : rect.top;
    final trailing = axis == Axis.horizontal ? rect.right : rect.bottom;
    final center = axis == Axis.horizontal ? rect.center.dx : rect.center.dy;

    final projectedCoordinate = switch (currentCoordinate.compareTo(
      startCoordinate,
    )) {
      < 0 => currentCoordinate + leading - startCoordinate,
      > 0 => currentCoordinate + trailing - startCoordinate,
      _ => center,
    };
    return axis == Axis.horizontal
        ? Offset(projectedCoordinate, globalPosition.dy)
        : Offset(globalPosition.dx, projectedCoordinate);
  }
}

@immutable
class NativeTabStripDropTarget {
  const NativeTabStripDropTarget({
    required this.insertionIndex,
    required this.indicatorGlobalPosition,
  });

  final int insertionIndex;
  final Offset indicatorGlobalPosition;
}

typedef NativeTabStripDropTargetResolver =
    NativeTabStripDropTarget? Function(
      Offset globalPosition,
      NativeTabDragSource source,
      int trendDirection,
    );

NativeTabStripDropTarget? resolveNativeTabStripDropTarget({
  required List<Rect> tabRects,
  required Offset globalPosition,
  required Axis axis,
}) {
  if (tabRects.isEmpty) return null;

  final coordinate = axis == Axis.horizontal
      ? globalPosition.dx
      : globalPosition.dy;
  for (var index = 0; index < tabRects.length; index++) {
    final rect = tabRects[index];
    final midpoint = axis == Axis.horizontal ? rect.center.dx : rect.center.dy;
    if (coordinate < midpoint) {
      return NativeTabStripDropTarget(
        insertionIndex: index,
        indicatorGlobalPosition: axis == Axis.horizontal
            ? rect.centerLeft
            : rect.topCenter,
      );
    }
  }

  final lastRect = tabRects.last;
  return NativeTabStripDropTarget(
    insertionIndex: tabRects.length,
    indicatorGlobalPosition: axis == Axis.horizontal
        ? lastRect.centerRight
        : lastRect.bottomCenter,
  );
}

NativeTabStripDropTarget? resolveNativeTabStripTrendDropTarget({
  required List<Rect> tabRects,
  required Offset globalPosition,
  required Axis axis,
  required NativeTabDragSource source,
  required TabbedViewController targetController,
  required int trendDirection,
}) {
  final rawTarget = resolveNativeTabStripDropTarget(
    tabRects: tabRects,
    globalPosition: source.projectDropPosition(globalPosition, axis),
    axis: axis,
  );
  if (rawTarget == null ||
      trendDirection == 0 ||
      !identical(source.controller, targetController)) {
    return rawTarget;
  }

  final sourceIndex = targetController.tabs.indexOf(source.tab);
  if (sourceIndex < 0) return rawTarget;

  var insertionIndex = rawTarget.insertionIndex;
  if (trendDirection > 0 && sourceIndex < targetController.length - 1) {
    insertionIndex = insertionIndex < sourceIndex + 2
        ? sourceIndex + 2
        : insertionIndex;
  } else if (trendDirection < 0 && sourceIndex > 0) {
    insertionIndex = insertionIndex > sourceIndex - 1
        ? sourceIndex - 1
        : insertionIndex;
  }
  return _nativeTabStripTargetAtInsertion(
    tabRects: tabRects,
    insertionIndex: insertionIndex,
    axis: axis,
  );
}

NativeTabStripDropTarget _nativeTabStripTargetAtInsertion({
  required List<Rect> tabRects,
  required int insertionIndex,
  required Axis axis,
}) {
  final index = insertionIndex.clamp(0, tabRects.length);
  final indicatorRect = index == tabRects.length
      ? tabRects.last
      : tabRects[index];
  final indicatorPosition = axis == Axis.horizontal
      ? (index == tabRects.length
            ? indicatorRect.centerRight
            : indicatorRect.centerLeft)
      : (index == tabRects.length
            ? indicatorRect.bottomCenter
            : indicatorRect.topCenter);
  return NativeTabStripDropTarget(
    insertionIndex: index,
    indicatorGlobalPosition: indicatorPosition,
  );
}

class NativeTabDragRegistration {
  NativeTabDragRegistration._({required this.token, required this.source});

  final String token;
  final NativeTabDragSource source;
  bool _disposed = false;
  bool dropHandled = false;
  int trendDirection = 0;
  int? intendedInsertionIndex;

  bool get isDisposed => _disposed;

  void updateTrend(Offset globalPosition, Axis axis) {
    final delta = source.mainAxisDragDelta(globalPosition, axis);
    if (delta > _trendActivationDistance) {
      trendDirection = 1;
    } else if (delta < -_trendActivationDistance) {
      trendDirection = -1;
    }
  }

  Map<String, Object> get localData => <String, Object>{
    _nativeTabDragKindKey: _nativeTabDragKind,
    _nativeTabDragTokenKey: token,
  };

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    NativeTabDragRegistry._unregister(this);
  }
}

class NativeTabDragRegistry {
  NativeTabDragRegistry._();

  static int _nextToken = 0;
  static final Map<String, NativeTabDragRegistration> _registrations = {};

  static NativeTabDragRegistration register({
    required TabbedViewController controller,
    required TabData tab,
    required String? dragScope,
    Offset? dragStartGlobalPosition,
    Rect? sourceGlobalRect,
  }) {
    final registration = NativeTabDragRegistration._(
      token: '${_nextToken++}',
      source: NativeTabDragSource(
        controller: controller,
        tab: tab,
        dragScope: dragScope,
        dragStartGlobalPosition: dragStartGlobalPosition,
        sourceGlobalRect: sourceGlobalRect,
      ),
    );
    _registrations[registration.token] = registration;
    return registration;
  }

  static NativeTabDragSource? sourceForSession(DropSession session) {
    return registrationForSession(session)?.source;
  }

  static NativeTabDragRegistration? registrationForSession(
    DropSession session,
  ) {
    for (final item in session.items) {
      final registration = _registrationForLocalData(item.localData);
      if (registration != null) return registration;
    }
    return null;
  }

  @visibleForTesting
  static NativeTabDragSource? sourceForLocalData(Object? localData) {
    return _registrationForLocalData(localData)?.source;
  }

  static NativeTabDragRegistration? _registrationForLocalData(
    Object? localData,
  ) {
    if (localData is! Map ||
        localData[_nativeTabDragKindKey] != _nativeTabDragKind) {
      return null;
    }
    final token = localData[_nativeTabDragTokenKey];
    if (token is! String) return null;
    return _registrations[token];
  }

  static void _unregister(NativeTabDragRegistration registration) {
    if (identical(_registrations[registration.token], registration)) {
      _registrations.remove(registration.token);
    }
  }
}

@visibleForTesting
DragItem createNativeTabDragItem(
  NativeTabDragRegistration registration,
  String label,
) {
  final item = DragItem(localData: registration.localData);
  // Android requires a native representation before it will start a drag
  // session. The in-memory token remains the source of truth for tab moves.
  item.add(Formats.plainText(label));
  return item;
}

typedef NativeTabDragEnded =
    void Function(DropOperation operation, Offset location);

class NativeTabDragSessionBinding {
  NativeTabDragSessionBinding({
    required this.session,
    required this.registration,
    required this.onStarted,
    required this.onUpdated,
    required this.onEnded,
  }) : _lastLocation =
           registration.source.dragStartGlobalPosition ?? Offset.zero {
    session.dragging.addListener(_handleDragging);
    session.lastScreenLocation.addListener(_handleLocation);
    session.dragCompleted.addListener(_handleCompleted);
    _handleDragging();
  }

  final DragSession session;
  final NativeTabDragRegistration registration;
  final VoidCallback onStarted;
  final ValueChanged<Offset> onUpdated;
  final NativeTabDragEnded onEnded;

  bool _started = false;
  bool _disposed = false;
  Offset _lastLocation;

  void _handleDragging() {
    if (!_started && session.dragging.value) {
      _started = true;
      onStarted();
    }
  }

  void _handleLocation() {
    final location = session.lastScreenLocation.value;
    if (location == null) return;
    _lastLocation = location;
    if (_started) onUpdated(location);
  }

  void _handleCompleted() {
    final operation = session.dragCompleted.value;
    if (operation == null) return;
    if (_started) onEnded(operation, _lastLocation);
    _dispose();
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    session.dragging.removeListener(_handleDragging);
    session.lastScreenLocation.removeListener(_handleLocation);
    session.dragCompleted.removeListener(_handleCompleted);
    registration.dispose();
  }
}

bool nativeTabDragWasAccepted(DropOperation operation) {
  return operation == DropOperation.move ||
      operation == DropOperation.copy ||
      operation == DropOperation.link;
}

bool _nativeTabCanDrop(
  TabbedViewProvider provider,
  NativeTabDragSource source,
) {
  final targetScope = provider.dragScope;
  if (targetScope != null &&
      source.dragScope != null &&
      targetScope != source.dragScope) {
    return false;
  }
  return provider.canDrop?.call(source.draggableData, provider.controller) ??
      true;
}

bool _performNativeTabDrop({
  required TabbedViewProvider provider,
  required NativeTabDragSource source,
  required int insertionIndex,
}) {
  final newIndex = insertionIndex.clamp(0, provider.controller.length);
  if (provider.onBeforeDropAccept?.call(
        source.draggableData,
        provider.controller,
        newIndex,
      ) ==
      false) {
    return false;
  }

  final oldIndex = source.controller.tabs.indexOf(source.tab);
  if (oldIndex < 0) return false;

  if (identical(source.controller, provider.controller)) {
    return source.controller.reorderTab(oldIndex, newIndex);
  } else {
    source.controller.removeTab(oldIndex);
    final targetIndex = newIndex.clamp(0, provider.controller.length);
    provider.controller.insertTab(targetIndex, source.tab);
  }
  return true;
}

bool performNativeTabTrendFallback({
  required TabbedViewProvider provider,
  required NativeTabDragRegistration registration,
  required Axis axis,
  required Offset globalPosition,
}) {
  if (registration.dropHandled) return false;
  final source = registration.source;
  if (!identical(source.controller, provider.controller) ||
      !_nativeTabCanDrop(provider, source)) {
    return false;
  }

  final delta = source.mainAxisDragDelta(globalPosition, axis);
  if (delta.abs() <= _trendActivationDistance) return false;

  final oldIndex = source.controller.tabs.indexOf(source.tab);
  if (oldIndex < 0 || source.controller.length < 2) return false;
  final intendedInsertionIndex = registration.intendedInsertionIndex;
  final int insertionIndex;
  final int destinationIndex;
  if (intendedInsertionIndex != null) {
    insertionIndex = intendedInsertionIndex.clamp(0, source.controller.length);
    destinationIndex = insertionIndex > oldIndex
        ? insertionIndex - 1
        : insertionIndex;
  } else {
    final direction = delta > 0 ? 1 : -1;
    destinationIndex = (oldIndex + direction).clamp(
      0,
      source.controller.length - 1,
    );
    insertionIndex = destinationIndex > oldIndex
        ? destinationIndex + 1
        : destinationIndex;
  }
  if (destinationIndex == oldIndex) return false;

  registration.dropHandled = true;
  final reordered = _performNativeTabDrop(
    provider: provider,
    source: source,
    insertionIndex: insertionIndex,
  );
  return reordered;
}

class NativeTabDraggable extends StatelessWidget {
  const NativeTabDraggable({
    super.key,
    required this.child,
    required this.provider,
    required this.tab,
    required this.index,
    required this.config,
    required this.feedback,
  });

  final Widget child;
  final TabbedViewProvider provider;
  final TabData tab;
  final int index;
  final DraggableConfig config;
  final Widget feedback;

  @override
  Widget build(BuildContext context) {
    final tabBarPosition = TabbedViewTheme.of(context).tabsArea.position;
    final dragAxis = tabBarPosition.isHorizontal
        ? Axis.horizontal
        : Axis.vertical;
    return DragItemWidget(
      allowedOperations: () => const [DropOperation.move, DropOperation.copy],
      dragItemProvider: (request) {
        final renderObject = context.findRenderObject();
        final sourceGlobalRect =
            renderObject is RenderBox && renderObject.attached
            ? renderObject.localToGlobal(Offset.zero) & renderObject.size
            : null;
        final registration = NativeTabDragRegistry.register(
          controller: provider.controller,
          tab: tab,
          dragScope: provider.dragScope,
          dragStartGlobalPosition: request.location,
          sourceGlobalRect: sourceGlobalRect,
        );
        NativeTabDragSessionBinding(
          session: request.session,
          registration: registration,
          onStarted: () {
            final currentIndex = provider.controller.tabs.indexOf(tab);
            provider.onTabDrag(currentIndex < 0 ? index : currentIndex);
            config.onDragStarted?.call();
          },
          onUpdated: (location) {
            config.onDragUpdate?.call(
              DragUpdateDetails(globalPosition: location),
            );
          },
          onEnded: (operation, location) {
            final reorderedByTrend =
                operation != DropOperation.userCancelled &&
                operation != DropOperation.forbidden &&
                performNativeTabTrendFallback(
                  provider: provider,
                  registration: registration,
                  axis: dragAxis,
                  globalPosition: location,
                );
            final accepted =
                nativeTabDragWasAccepted(operation) || reorderedByTrend;
            provider.onTabDrag(null);
            config.onDragEnd?.call(
              DraggableDetails(
                wasAccepted: accepted,
                velocity: Velocity.zero,
                offset: location,
              ),
            );
            if (accepted) {
              config.onDragCompleted?.call();
            } else {
              config.onDraggableCanceled?.call(Velocity.zero, location);
            }
          },
        );
        return createNativeTabDragItem(registration, tab.text);
      },
      liftBuilder: (_, _) => Material(child: feedback),
      dragBuilder: (_, _) => Material(child: feedback),
      child: DraggableWidget(
        hitTestBehavior: HitTestBehavior.opaque,
        child: child,
      ),
    );
  }
}

class NativeTabsAreaCorner extends StatelessWidget {
  const NativeTabsAreaCorner({
    super.key,
    required this.provider,
    required this.hiddenTabs,
  });

  final TabbedViewProvider provider;
  final HiddenTabs hiddenTabs;

  @override
  Widget build(BuildContext context) {
    final theme = TabbedViewTheme.of(context);
    final tabsAreaTheme = theme.tabsArea;
    final children = <Widget>[
      TabsAreaButtonsWidget(provider: provider, hiddenTabs: hiddenTabs),
    ];

    if (provider.trailing != null) {
      Widget trailing = provider.trailing!;
      if (tabsAreaTheme.position.isVertical &&
          tabsAreaTheme.sideTabsLayout == SideTabsLayout.rotated) {
        trailing = RotatedBox(
          quarterTurns: tabsAreaTheme.position == TabBarPosition.left ? -1 : 1,
          child: trailing,
        );
      }
      children.add(trailing);
    }

    final Widget cornerContent;
    if (tabsAreaTheme.position.isHorizontal) {
      if (tabsAreaTheme.crossAxisFit == TabsAreaCrossAxisFit.all) {
        cornerContent = IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );
      } else {
        cornerContent = Row(mainAxisSize: MainAxisSize.min, children: children);
      }
    } else {
      cornerContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }

    return Container(
      padding: tabsAreaTheme.position.isHorizontal
          ? const EdgeInsets.only(left: _dropIndicatorExtent)
          : const EdgeInsets.only(top: _dropIndicatorExtent),
      child: cornerContent,
    );
  }
}

class NativeTabDropRegion extends StatefulWidget {
  const NativeTabDropRegion({
    super.key,
    required this.provider,
    required this.position,
    required this.child,
    this.targetTab,
    this.targetIndex,
    this.splitTarget = true,
  }) : assert(targetTab != null || targetIndex != null);

  final TabbedViewProvider provider;
  final TabBarPosition position;
  final TabData? targetTab;
  final int? targetIndex;
  final bool splitTarget;
  final Widget child;

  @override
  State<NativeTabDropRegion> createState() => _NativeTabDropRegionState();
}

class _NativeTabDropRegionState extends State<NativeTabDropRegion> {
  bool _showIndicator = false;
  bool _dropAfter = false;

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      formats: const [],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: _onDropOver,
      onDropLeave: (_) => _clearIndicator(),
      onDropEnded: (_) => _clearIndicator(),
      onPerformDrop: _onPerformDrop,
      child: _showIndicator
          ? CustomPaint(
              foregroundPainter: _NativeTabDropIndicatorPainter(
                position: widget.position,
                dropAfter: _dropAfter,
                color: TabbedViewTheme.of(context).tabsArea.dropColor,
              ),
              child: widget.child,
            )
          : widget.child,
    );
  }

  DropOperation _onDropOver(DropOverEvent event) {
    final source = NativeTabDragRegistry.sourceForSession(event.session);
    final targetIndex = _targetIndex();
    if (source == null ||
        targetIndex == null ||
        !_canAccept(source) ||
        identical(source.tab, widget.targetTab)) {
      _clearIndicator();
      return DropOperation.none;
    }

    final operation = _acceptedOperation(event.session);
    if (operation == DropOperation.none) {
      _clearIndicator();
      return DropOperation.none;
    }
    final dropAfter = _resolveDropAfter(
      source: source,
      targetIndex: targetIndex,
      localPosition: event.position.local,
    );
    _setIndicator(dropAfter);
    return operation;
  }

  Future<void> _onPerformDrop(PerformDropEvent event) async {
    final registration = NativeTabDragRegistry.registrationForSession(
      event.session,
    );
    final source = registration?.source;
    final targetIndex = _targetIndex();
    if (source == null ||
        targetIndex == null ||
        !_canAccept(source) ||
        identical(source.tab, widget.targetTab)) {
      _clearIndicator();
      return;
    }

    registration!.dropHandled = true;
    _performNativeTabDrop(
      provider: widget.provider,
      source: source,
      insertionIndex: targetIndex + (_dropAfter ? 1 : 0),
    );
    _clearIndicator();
  }

  bool _canAccept(NativeTabDragSource source) {
    return _nativeTabCanDrop(widget.provider, source);
  }

  int? _targetIndex() {
    final targetTab = widget.targetTab;
    if (targetTab != null) {
      final index = widget.provider.controller.tabs.indexOf(targetTab);
      return index < 0 ? null : index;
    }
    return widget.targetIndex?.clamp(0, widget.provider.controller.length);
  }

  bool _resolveDropAfter({
    required NativeTabDragSource source,
    required int targetIndex,
    required Offset localPosition,
  }) {
    if (!widget.splitTarget) return false;

    double ratio = 0.5;
    if (identical(source.controller, widget.provider.controller)) {
      final sourceIndex = source.controller.tabs.indexOf(source.tab);
      if (sourceIndex > targetIndex) {
        ratio = 0.75;
      } else if (sourceIndex < targetIndex) {
        ratio = 0.25;
      }
    }

    final size = context.size;
    if (size == null) return false;
    return widget.position.isHorizontal
        ? localPosition.dx >= size.width * ratio
        : localPosition.dy >= size.height * ratio;
  }

  DropOperation _acceptedOperation(DropSession session) {
    if (session.allowedOperations.contains(DropOperation.move)) {
      return DropOperation.move;
    }
    if (session.allowedOperations.contains(DropOperation.copy)) {
      return DropOperation.copy;
    }
    return DropOperation.none;
  }

  void _setIndicator(bool dropAfter) {
    if (_showIndicator && _dropAfter == dropAfter) return;
    if (!mounted) return;
    setState(() {
      _showIndicator = true;
      _dropAfter = dropAfter;
    });
  }

  void _clearIndicator() {
    if (!_showIndicator || !mounted) return;
    setState(() {
      _showIndicator = false;
    });
  }
}

class NativeTabStripDropRegion extends StatefulWidget {
  const NativeTabStripDropRegion({
    super.key,
    required this.provider,
    required this.position,
    required this.resolveTarget,
    required this.child,
  });

  final TabbedViewProvider provider;
  final TabBarPosition position;
  final NativeTabStripDropTargetResolver resolveTarget;
  final Widget child;

  @override
  State<NativeTabStripDropRegion> createState() =>
      _NativeTabStripDropRegionState();
}

class _NativeTabStripDropRegionState extends State<NativeTabStripDropRegion> {
  NativeTabStripDropTarget? _target;
  double? _indicatorMainAxisOffset;

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      formats: const [],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: _onDropOver,
      onDropLeave: (_) => _clearTarget(),
      onDropEnded: (_) => _finishDrag(),
      onPerformDrop: _onPerformDrop,
      child: _target == null || _indicatorMainAxisOffset == null
          ? widget.child
          : CustomPaint(
              foregroundPainter: _NativeTabStripDropIndicatorPainter(
                position: widget.position,
                mainAxisOffset: _indicatorMainAxisOffset!,
                color: TabbedViewTheme.of(context).tabsArea.dropColor,
              ),
              child: widget.child,
            ),
    );
  }

  DropOperation _onDropOver(DropOverEvent event) {
    final registration = NativeTabDragRegistry.registrationForSession(
      event.session,
    );
    final source = registration?.source;
    final target = registration == null
        ? null
        : _resolveTarget(registration, event.position.global);
    if (source == null ||
        target == null ||
        !_nativeTabCanDrop(widget.provider, source)) {
      _clearTarget();
      return DropOperation.none;
    }

    final operation = _acceptedOperation(event.session);
    if (operation == DropOperation.none) {
      _clearTarget();
      return operation;
    }

    _setTarget(target);
    return operation;
  }

  Future<void> _onPerformDrop(PerformDropEvent event) async {
    final registration = NativeTabDragRegistry.registrationForSession(
      event.session,
    );
    final source = registration?.source;
    final target = registration == null
        ? null
        : _resolveTarget(registration, event.position.global);
    if (source != null &&
        target != null &&
        _nativeTabCanDrop(widget.provider, source)) {
      registration!.dropHandled = true;
      _performNativeTabDrop(
        provider: widget.provider,
        source: source,
        insertionIndex: target.insertionIndex,
      );
    }
    _finishDrag();
  }

  NativeTabStripDropTarget? _resolveTarget(
    NativeTabDragRegistration registration,
    Offset globalPosition,
  ) {
    final axis = widget.position.isHorizontal ? Axis.horizontal : Axis.vertical;
    registration.updateTrend(globalPosition, axis);
    final target = widget.resolveTarget(
      globalPosition,
      registration.source,
      registration.trendDirection,
    );
    registration.intendedInsertionIndex = target?.insertionIndex;
    return target;
  }

  void _finishDrag() {
    _clearTarget();
  }

  DropOperation _acceptedOperation(DropSession session) {
    if (session.allowedOperations.contains(DropOperation.move)) {
      return DropOperation.move;
    }
    if (session.allowedOperations.contains(DropOperation.copy)) {
      return DropOperation.copy;
    }
    return DropOperation.none;
  }

  void _setTarget(NativeTabStripDropTarget target) {
    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return;
    final local = renderBox.globalToLocal(target.indicatorGlobalPosition);
    final mainAxisOffset = widget.position.isHorizontal ? local.dx : local.dy;
    if (_target?.insertionIndex == target.insertionIndex &&
        _indicatorMainAxisOffset == mainAxisOffset) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _target = target;
      _indicatorMainAxisOffset = mainAxisOffset;
    });
  }

  void _clearTarget() {
    if (_target == null || !mounted) return;
    setState(() {
      _target = null;
      _indicatorMainAxisOffset = null;
    });
  }
}

class _NativeTabDropIndicatorPainter extends CustomPainter {
  const _NativeTabDropIndicatorPainter({
    required this.position,
    required this.dropAfter,
    required this.color,
  });

  final TabBarPosition position;
  final bool dropAfter;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    if (position.isHorizontal) {
      final x = dropAfter ? size.width - _dropIndicatorExtent : 0.0;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, _dropIndicatorExtent, size.height),
        paint,
      );
    } else {
      final y = dropAfter ? size.height - _dropIndicatorExtent : 0.0;
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, _dropIndicatorExtent),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NativeTabDropIndicatorPainter oldDelegate) {
    return position != oldDelegate.position ||
        dropAfter != oldDelegate.dropAfter ||
        color != oldDelegate.color;
  }
}

class _NativeTabStripDropIndicatorPainter extends CustomPainter {
  const _NativeTabStripDropIndicatorPainter({
    required this.position,
    required this.mainAxisOffset,
    required this.color,
  });

  final TabBarPosition position;
  final double mainAxisOffset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    if (position.isHorizontal) {
      final x = (mainAxisOffset - _dropIndicatorExtent / 2).clamp(
        0.0,
        (size.width - _dropIndicatorExtent).clamp(0.0, size.width),
      );
      canvas.drawRect(
        Rect.fromLTWH(x, 0, _dropIndicatorExtent, size.height),
        paint,
      );
    } else {
      final y = (mainAxisOffset - _dropIndicatorExtent / 2).clamp(
        0.0,
        (size.height - _dropIndicatorExtent).clamp(0.0, size.height),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, _dropIndicatorExtent),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _NativeTabStripDropIndicatorPainter oldDelegate,
  ) {
    return position != oldDelegate.position ||
        mainAxisOffset != oldDelegate.mainAxisOffset ||
        color != oldDelegate.color;
  }
}
