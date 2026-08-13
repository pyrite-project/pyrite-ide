// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:tabbed_view/src/tab_bar_position.dart';
import 'package:tabbed_view/src/tab_status.dart';
import 'package:tabbed_view/src/tabbed_view_controller.dart';
import 'package:tabbed_view/src/theme/tabbed_view_theme_data.dart';
import 'package:tabbed_view/src/theme/tabs_area_theme_data.dart';
import 'package:tabbed_view/src/theme/theme_widget.dart';
import 'package:tabbed_view/src/internal/size_holder.dart';
import 'package:pyrite_ide/shared/tabbed_view/tab_widget.dart';
import 'package:tabbed_view/src/internal/tabbed_view_provider.dart';
import 'package:tabbed_view/src/internal/tabs_area/hidden_tabs.dart';
import 'package:pyrite_ide/shared/tabbed_view/native_tab_drag.dart';

/// Widget for the tabs and buttons.
class TabsArea extends StatefulWidget {
  const TabsArea({super.key, required this.provider});

  final TabbedViewProvider provider;

  @override
  State<StatefulWidget> createState() => _TabsAreaState();
}

/// The [TabsArea] state.
class _TabsAreaState extends State<TabsArea> {
  int? _hoveredIndex;
  int? _lastSelectedTabIndex;

  final ScrollController _scrollController = ScrollController();
  final Map<Key, BuildContext> _tabContexts = {};
  Timer? _autoScrollTimer;
  int _autoScrollDirection = 0;

  final HiddenTabs _hiddenTabs = HiddenTabs();

  @override
  void dispose() {
    _stopAutoScroll();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: _hiddenTabs, builder: _builder);
  }

  Widget _builder(BuildContext context, Widget? child) {
    TabbedViewController controller = widget.provider.controller;
    TabbedViewThemeData theme = TabbedViewTheme.of(context);
    TabsAreaThemeData tabsAreaTheme = theme.tabsArea;
    List<Widget> children = [];
    for (int index = 0; index < controller.tabs.length; index++) {
      TabStatus status = _getStatusFor(index);
      SizeHolder sizeHolder = SizeHolder();
      final Key tabIdentity = controller.tabs[index].uniqueKey;
      Widget tab = KeyedSubtree(
        key: tabIdentity,
        child: Builder(
          builder: (context) {
            _tabContexts[tabIdentity] = context;
            return TabWidget(
              key: ValueKey(tabIdentity),
              index: index,
              status: status,
              provider: widget.provider,
              sizeHolder: sizeHolder,
              updateHoveredIndex: _updateHoveredIndex,
              onClose: _onTabClose,
            );
          },
        ),
      );
      children.add(tab);
    }
    _tabContexts.removeWhere(
      (key, value) => !controller.tabs.any((tab) => tab.uniqueKey == key),
    );

    _hiddenTabs.update(const []);
    _scheduleSelectedTabReveal(controller, tabsAreaTheme.position);

    final Widget tabs = _buildScrollableTabs(theme: theme, children: children);
    Widget corner = NativeTabsAreaCorner(
      provider: widget.provider,
      hiddenTabs: _hiddenTabs,
    );
    if (widget.provider.tabReorderEnabled) {
      corner = NativeTabDropRegion(
        provider: widget.provider,
        position: tabsAreaTheme.position,
        targetIndex: controller.length,
        splitTarget: false,
        child: corner,
      );
    }

    Widget content;
    if (theme.tabsArea.position.isHorizontal) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: tabs),
          corner,
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: tabs),
          corner,
        ],
      );
    }

    content = _TabsAreaAxisConstraint(
      position: tabsAreaTheme.position,
      child: content,
    );
    content = ClipRect(child: content);

    final BorderSide? divider = theme.isDividerWithinTabArea
        ? theme.divider
        : null;
    if (divider != null && divider.width > 0) {
      content = CustomPaint(
        painter: _TabsAreaDividerPainter(
          borderSide: divider,
          position: tabsAreaTheme.position,
        ),
        child: content,
      );
    }

    // Apply the theme's color and border directly.
    return Container(
      decoration: BoxDecoration(
        color: tabsAreaTheme.color,
        borderRadius: _buildBorderRadius(theme: tabsAreaTheme),
        border: _buildBorder(theme: tabsAreaTheme),
      ),
      child: content,
    );
  }

  Widget _buildScrollableTabs({
    required TabbedViewThemeData theme,
    required List<Widget> children,
  }) {
    final TabsAreaThemeData tabsAreaTheme = theme.tabsArea;
    final Axis scrollDirection = tabsAreaTheme.position.isHorizontal
        ? Axis.horizontal
        : Axis.vertical;
    final EdgeInsets padding = tabsAreaTheme.position.isHorizontal
        ? EdgeInsets.only(
            left: _nonNegative(tabsAreaTheme.initialGap),
            right: _nonNegative(tabsAreaTheme.minimalFinalGap),
          )
        : EdgeInsets.only(
            top: _nonNegative(tabsAreaTheme.initialGap),
            bottom: _nonNegative(tabsAreaTheme.minimalFinalGap),
          );

    Widget tabList = tabsAreaTheme.position.isHorizontal
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: _withGaps(
              children,
              _nonNegative(tabsAreaTheme.middleGap),
              Axis.horizontal,
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: _withGaps(
              children,
              _nonNegative(tabsAreaTheme.middleGap),
              Axis.vertical,
            ),
          );

    tabList = Padding(padding: padding, child: tabList);
    if (tabsAreaTheme.position.isHorizontal) {
      tabList = Listener(
        onPointerSignal: _resolveHorizontalPointerSignal,
        child: tabList,
      );
    }

    final scrollView = SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: scrollDirection,
      child: tabList,
    );
    return DropMonitor(
      formats: const [],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) => _updateAutoScroll(event, scrollDirection),
      onDropLeave: (_) => _stopAutoScroll(),
      onDropEnded: (_) => _stopAutoScroll(),
      child: scrollView,
    );
  }

  List<Widget> _withGaps(List<Widget> children, double gap, Axis axis) {
    if (children.length < 2 || gap == 0) {
      return children;
    }
    final List<Widget> spacedChildren = [];
    for (int index = 0; index < children.length; index++) {
      if (index > 0) {
        spacedChildren.add(
          SizedBox(
            width: axis == Axis.horizontal ? gap : 0,
            height: axis == Axis.vertical ? gap : 0,
          ),
        );
      }
      spacedChildren.add(children[index]);
    }
    return spacedChildren;
  }

  double _nonNegative(double value) {
    return value < 0 ? 0 : value;
  }

  void _resolveHorizontalPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      _handleHorizontalPointerSignal,
    );
  }

  void _handleHorizontalPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) {
      return;
    }

    final double delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) {
      return;
    }

    final ScrollPosition position = _scrollController.position;
    final double target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) {
      return;
    }

    _scrollController.jumpTo(target);
  }

  void _updateAutoScroll(MonitorDropOverEvent event, Axis axis) {
    if (!event.isInside ||
        NativeTabDragRegistry.sourceForSession(event.session) == null ||
        !_scrollController.hasClients) {
      _stopAutoScroll();
      return;
    }

    final double viewportExtent = _scrollController.position.viewportDimension;
    final double coordinate = axis == Axis.horizontal
        ? event.position.local.dx
        : event.position.local.dy;
    final double edgeExtent = viewportExtent < 108 ? viewportExtent / 3 : 36;

    int direction = 0;
    if (coordinate < edgeExtent) {
      direction = -1;
    } else if (coordinate > viewportExtent - edgeExtent) {
      direction = 1;
    }
    _setAutoScrollDirection(direction);
  }

  void _setAutoScrollDirection(int direction) {
    if (_autoScrollDirection == direction) return;
    _stopAutoScroll();
    if (direction == 0) return;
    _autoScrollDirection = direction;
    _scrollByAutoScrollStep();
    _autoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _scrollByAutoScrollStep(),
    );
  }

  void _scrollByAutoScrollStep() {
    if (!mounted || !_scrollController.hasClients) {
      _stopAutoScroll();
      return;
    }
    final position = _scrollController.position;
    final target = (position.pixels + _autoScrollDirection * 8).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    _scrollController.jumpTo(target);
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDirection = 0;
  }

  void _scheduleSelectedTabReveal(
    TabbedViewController controller,
    TabBarPosition tabBarPosition,
  ) {
    final int? selectedIndex = controller.selectedIndex;
    if (selectedIndex == null ||
        selectedIndex < 0 ||
        selectedIndex >= controller.tabs.length ||
        selectedIndex == _lastSelectedTabIndex) {
      return;
    }

    _lastSelectedTabIndex = selectedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final tabContext = _tabContexts[controller.tabs[selectedIndex].uniqueKey];
      if (tabContext == null || !_scrollController.hasClients) {
        return;
      }

      final RenderObject? renderObject = tabContext.findRenderObject();
      final ScrollableState? scrollable = Scrollable.maybeOf(tabContext);
      final BuildContext? scrollContext = scrollable?.context;
      final RenderObject? scrollRenderObject = scrollContext
          ?.findRenderObject();
      if (renderObject is! RenderBox || scrollRenderObject is! RenderBox) {
        return;
      }
      if (!renderObject.attached || !scrollRenderObject.attached) {
        return;
      }

      final Offset tabOffset = renderObject.localToGlobal(
        Offset.zero,
        ancestor: scrollRenderObject,
      );
      final double tabStart = tabBarPosition.isHorizontal
          ? tabOffset.dx
          : tabOffset.dy;
      final double tabEnd =
          tabStart +
          (tabBarPosition.isHorizontal
              ? renderObject.size.width
              : renderObject.size.height);
      final double viewportExtent = tabBarPosition.isHorizontal
          ? scrollRenderObject.size.width
          : scrollRenderObject.size.height;

      double target = _scrollController.offset;
      if (tabStart < 0) {
        target += tabStart;
      } else if (tabEnd > viewportExtent) {
        target += tabEnd - viewportExtent;
      } else {
        return;
      }

      final ScrollPosition position = _scrollController.position;
      target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    });
  }

  BorderRadius _buildBorderRadius({required TabsAreaThemeData theme}) {
    final Radius radius = Radius.circular(theme.borderRadius);
    final TabBarPosition position = theme.position;

    bool top = position != TabBarPosition.bottom;
    bool bottom = position != TabBarPosition.top;
    bool left = position != TabBarPosition.right;
    bool right = position != TabBarPosition.left;

    return BorderRadius.only(
      topLeft: (left && top) ? radius : Radius.zero,
      topRight: (right && top) ? radius : Radius.zero,
      bottomLeft: (left && bottom) ? radius : Radius.zero,
      bottomRight: (right && bottom) ? radius : Radius.zero,
    );
  }

  Border _buildBorder({required TabsAreaThemeData theme}) {
    final BorderSide borderSide = theme.border ?? BorderSide.none;
    final TabBarPosition position = theme.position;

    bool top = position != TabBarPosition.bottom;
    bool bottom = position != TabBarPosition.top;
    bool left = position != TabBarPosition.right;
    bool right = position != TabBarPosition.left;

    return Border(
      top: top ? borderSide : BorderSide.none,
      bottom: bottom ? borderSide : BorderSide.none,
      left: left ? borderSide : BorderSide.none,
      right: right ? borderSide : BorderSide.none,
    );
  }

  /// Gets the status of the tab for a given index.
  TabStatus _getStatusFor(int tabIndex) {
    TabbedViewController controller = widget.provider.controller;
    if (controller.tabs.isEmpty || tabIndex >= controller.tabs.length) {
      throw Exception('Invalid tab index: $tabIndex');
    }

    if (controller.selectedIndex != null &&
        controller.selectedIndex == tabIndex) {
      return TabStatus.selected;
    } else if (_hoveredIndex != null && _hoveredIndex == tabIndex) {
      return TabStatus.hovered;
    }
    return TabStatus.normal;
  }

  void _updateHoveredIndex(int? tabIndex) {
    if (_hoveredIndex != tabIndex) {
      setState(() {
        _hoveredIndex = tabIndex;
      });
    }
  }

  void _onTabClose() {
    setState(() {
      _hoveredIndex = null;
    });
  }
}

class _TabsAreaDividerPainter extends CustomPainter {
  const _TabsAreaDividerPainter({
    required this.borderSide,
    required this.position,
  });

  final BorderSide borderSide;
  final TabBarPosition position;

  @override
  void paint(Canvas canvas, Size size) {
    final double width = borderSide.width;
    if (width <= 0) {
      return;
    }

    final Paint paint = Paint()
      ..color = borderSide.color
      ..style = PaintingStyle.fill;

    final Rect rect = switch (position) {
      TabBarPosition.top => Rect.fromLTWH(
        0,
        size.height - width,
        size.width,
        width,
      ),
      TabBarPosition.bottom => Rect.fromLTWH(0, 0, size.width, width),
      TabBarPosition.left => Rect.fromLTWH(
        size.width - width,
        0,
        width,
        size.height,
      ),
      TabBarPosition.right => Rect.fromLTWH(0, 0, width, size.height),
    };

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _TabsAreaDividerPainter oldDelegate) {
    return borderSide != oldDelegate.borderSide ||
        position != oldDelegate.position;
  }
}

class _TabsAreaAxisConstraint extends SingleChildRenderObjectWidget {
  const _TabsAreaAxisConstraint({
    required this.position,
    required Widget super.child,
  });

  final TabBarPosition position;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderTabsAreaAxisConstraint(position: position);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTabsAreaAxisConstraint renderObject,
  ) {
    renderObject.position = position;
  }
}

class _RenderTabsAreaAxisConstraint extends RenderProxyBox {
  _RenderTabsAreaAxisConstraint({required TabBarPosition position})
    : _position = position;

  TabBarPosition _position;

  set position(TabBarPosition value) {
    if (_position != value) {
      _position = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    if (child == null) {
      size = constraints.constrain(Size.zero);
      return;
    }

    if (_position.isHorizontal) {
      final double width = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : constraints.minWidth;
      child!.layout(
        BoxConstraints(
          minWidth: width,
          maxWidth: width,
          minHeight: 0,
          maxHeight: double.infinity,
        ),
        parentUsesSize: true,
      );
      size = constraints.constrain(Size(width, child!.size.height));
    } else {
      final double height = constraints.hasBoundedHeight
          ? constraints.maxHeight
          : constraints.minHeight;
      child!.layout(
        BoxConstraints(
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: height,
          maxHeight: height,
        ),
        parentUsesSize: true,
      );
      size = constraints.constrain(Size(child!.size.width, height));
    }
  }
}
