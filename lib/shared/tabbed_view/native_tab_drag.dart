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

@immutable
class NativeTabDragSource {
  const NativeTabDragSource({
    required this.controller,
    required this.tab,
    required this.dragScope,
  });

  final TabbedViewController controller;
  final TabData tab;
  final String? dragScope;

  DraggableData get draggableData => DraggableData(controller, tab, dragScope);
}

class NativeTabDragRegistration {
  NativeTabDragRegistration._({required this.token, required this.source});

  final String token;
  final NativeTabDragSource source;
  bool _disposed = false;

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
  }) {
    final registration = NativeTabDragRegistration._(
      token: '${_nextToken++}',
      source: NativeTabDragSource(
        controller: controller,
        tab: tab,
        dragScope: dragScope,
      ),
    );
    _registrations[registration.token] = registration;
    return registration;
  }

  static NativeTabDragSource? sourceForSession(DropSession session) {
    for (final item in session.items) {
      final source = sourceForLocalData(item.localData);
      if (source != null) return source;
    }
    return null;
  }

  @visibleForTesting
  static NativeTabDragSource? sourceForLocalData(Object? localData) {
    if (localData is! Map ||
        localData[_nativeTabDragKindKey] != _nativeTabDragKind) {
      return null;
    }
    final token = localData[_nativeTabDragTokenKey];
    if (token is! String) return null;
    return _registrations[token]?.source;
  }

  static void _unregister(NativeTabDragRegistration registration) {
    if (identical(_registrations[registration.token], registration)) {
      _registrations.remove(registration.token);
    }
  }
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
  }) {
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
  Offset _lastLocation = Offset.zero;

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
    return DragItemWidget(
      allowedOperations: () => const [DropOperation.move, DropOperation.copy],
      dragItemProvider: (request) {
        final registration = NativeTabDragRegistry.register(
          controller: provider.controller,
          tab: tab,
          dragScope: provider.dragScope,
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
            final accepted = nativeTabDragWasAccepted(operation);
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
        return DragItem(localData: registration.localData);
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
    final source = NativeTabDragRegistry.sourceForSession(event.session);
    final targetIndex = _targetIndex();
    if (source == null ||
        targetIndex == null ||
        !_canAccept(source) ||
        identical(source.tab, widget.targetTab)) {
      _clearIndicator();
      return;
    }

    final newIndex = targetIndex + (_dropAfter ? 1 : 0);
    final draggableData = source.draggableData;
    if (widget.provider.onBeforeDropAccept?.call(
          draggableData,
          widget.provider.controller,
          newIndex,
        ) ==
        false) {
      _clearIndicator();
      return;
    }

    final oldIndex = source.controller.tabs.indexOf(source.tab);
    if (oldIndex < 0) {
      _clearIndicator();
      return;
    }

    if (identical(source.controller, widget.provider.controller)) {
      source.controller.reorderTab(oldIndex, newIndex);
    } else {
      source.controller.removeTab(oldIndex);
      final insertionIndex = newIndex.clamp(
        0,
        widget.provider.controller.length,
      );
      widget.provider.controller.insertTab(insertionIndex, source.tab);
    }
    _clearIndicator();
  }

  bool _canAccept(NativeTabDragSource source) {
    final targetScope = widget.provider.dragScope;
    if (targetScope != null &&
        source.dragScope != null &&
        targetScope != source.dragScope) {
      return false;
    }
    return widget.provider.canDrop?.call(
          source.draggableData,
          widget.provider.controller,
        ) ??
        true;
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
