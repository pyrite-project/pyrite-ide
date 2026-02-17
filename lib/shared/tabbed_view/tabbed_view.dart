// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tabbed_view/src/internal/content_area.dart';
import 'package:tabbed_view/src/internal/tabbed_view_provider.dart';
import 'package:pyrite_ide/shared/tabbed_view/tabs_area.dart';
import 'package:tabbed_view/src/tab_bar_position.dart';
import 'package:tabbed_view/src/tabbed_view_controller.dart';
import 'package:tabbed_view/src/theme/tabbed_view_theme_data.dart';
import 'package:tabbed_view/src/theme/theme_widget.dart';
import 'package:tabbed_view/src/typedefs/can_drop.dart';
import 'package:tabbed_view/src/typedefs/on_before_drop_accept.dart';
import 'package:tabbed_view/src/typedefs/on_draggable_build.dart';
import 'package:tabbed_view/src/typedefs/on_tab_secondary_tap.dart';
import 'package:tabbed_view/src/typedefs/tab_remove_interceptor.dart';
import 'package:tabbed_view/src/typedefs/tabs_area_buttons_builder.dart';
import 'package:tabbed_view/src/unselected_tab_buttons_behavior.dart';

/// Widget inspired by the classic Desktop-style tab component.
///
/// Supports customizable themes.
///
/// Parameters:
/// * [closeButtonTooltip]: optional tooltip for the close button.
class TabbedView extends StatefulWidget {
  const TabbedView({
    super.key,
    required this.controller,
    this.contentBuilder,
    this.tabReorderEnabled = true,
    this.onTabSecondaryTap,
    this.unselectedTabButtonsBehavior =
        UnselectedTabButtonsBehavior.allDisabled,
    this.contentClip = true,
    this.closeButtonTooltip,
    this.tabsAreaButtonsBuilder,
    this.tabsAreaVisible,
    this.onDraggableBuild,
    this.canDrop,
    this.onBeforeDropAccept,
    this.dragScope,
    this.tabRemoveInterceptor,
    this.trailing,
  });

  final TabbedViewController controller;
  final bool contentClip;
  final IndexedWidgetBuilder? contentBuilder;

  /// Whether tab reordering via drag-and-drop is enabled in the UI.
  ///
  /// This flag controls **user interactions only**. It does **not** affect
  /// programmatic reordering through [TabbedViewController.reorderTab].
  final bool tabReorderEnabled;

  final TabRemoveInterceptor? tabRemoveInterceptor;
  final OnTabSecondaryTap? onTabSecondaryTap;
  final UnselectedTabButtonsBehavior unselectedTabButtonsBehavior;
  final String? closeButtonTooltip;
  final TabsAreaButtonsBuilder? tabsAreaButtonsBuilder;
  final bool? tabsAreaVisible;
  final OnDraggableBuild? onDraggableBuild;
  final CanDrop? canDrop;
  final OnBeforeDropAccept? onBeforeDropAccept;
  final String? dragScope;
  final Widget? trailing;

  @override
  State<StatefulWidget> createState() => _TabbedViewState();
}

/// The [TabbedView] state.
class _TabbedViewState extends State<TabbedView> {
  int? _draggingTabIndex;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuildByTabOrSelection);
  }

  @override
  void didUpdateWidget(covariant TabbedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_rebuildByTabOrSelection);
      widget.controller.addListener(_rebuildByTabOrSelection);
    }
  }

  @override
  Widget build(BuildContext context) {
    TabbedViewThemeData theme = TabbedViewTheme.of(context);

    TabbedViewProvider provider = TabbedViewProvider(
      controller: widget.controller,
      contentBuilder: widget.contentBuilder,
      tabReorderEnabled: widget.tabReorderEnabled,
      tabRemoveInterceptor: widget.tabRemoveInterceptor,
      contentClip: widget.contentClip,
      onTabSecondaryTap: widget.onTabSecondaryTap,
      unselectedTabButtonsBehavior: widget.unselectedTabButtonsBehavior,
      closeButtonTooltip: widget.closeButtonTooltip,
      tabsAreaButtonsBuilder: widget.tabsAreaButtonsBuilder,
      onDraggableBuild: widget.onDraggableBuild,
      onTabDrag: _onTabDrag,
      draggingTabIndex: _draggingTabIndex,
      canDrop: widget.canDrop,
      onBeforeDropAccept: widget.onBeforeDropAccept,
      dragScope: widget.dragScope,
      trailing: widget.trailing,
    );
    final bool tabsAreaVisible =
        widget.tabsAreaVisible ?? theme.tabsArea.visible;
    List<LayoutId> children = [];
    if (tabsAreaVisible) {
      Widget tabArea = TabsArea(provider: provider);
      children.add(LayoutId(id: 1, child: tabArea));
    }
    Widget contentArea = ContentArea(
      provider: provider,
      tabsAreaVisible: tabsAreaVisible,
    );
    children.add(LayoutId(id: 2, child: contentArea));
    return CustomMultiChildLayout(
      delegate: _TabbedViewLayout(tabBarPosition: theme.tabsArea.position),
      children: children,
    );
  }

  void _onTabDrag(int? tabIndex) {
    if (mounted) {
      setState(() {
        _draggingTabIndex = tabIndex;
      });
    }
  }

  /// Rebuilds after any change in tabs or selection.
  void _rebuildByTabOrSelection() {
    // rebuild
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuildByTabOrSelection);
    super.dispose();
  }
}

// Layout delegate for [TabbedView]
class _TabbedViewLayout extends MultiChildLayoutDelegate {
  _TabbedViewLayout({required this.tabBarPosition});

  final TabBarPosition tabBarPosition;

  @override
  void performLayout(Size size) {
    if (tabBarPosition == TabBarPosition.top ||
        tabBarPosition == TabBarPosition.bottom) {
      _performHorizontalLayout(size);
    } else {
      _performVerticalLayout(size);
    }
  }

  void _performHorizontalLayout(Size size) {
    double tabsAreaHeight = 0;
    if (hasChild(1)) {
      final tabsAreaSize = layoutChild(
        1,
        BoxConstraints(maxWidth: size.width, maxHeight: size.height),
      );
      tabsAreaHeight = tabsAreaSize.height;
    }

    final double contentAreaHeight = math.max(0, size.height - tabsAreaHeight);
    final contentAreaSize = Size(size.width, contentAreaHeight);
    layoutChild(2, BoxConstraints.tight(contentAreaSize));

    if (tabBarPosition == TabBarPosition.bottom) {
      positionChild(2, Offset.zero);
      if (hasChild(1)) {
        positionChild(1, Offset(0, contentAreaHeight));
      }
    } else {
      // top
      if (hasChild(1)) {
        positionChild(1, Offset.zero);
      }
      positionChild(2, Offset(0, tabsAreaHeight));
    }
  }

  void _performVerticalLayout(Size size) {
    double tabsAreaWidth = 0;
    if (hasChild(1)) {
      final tabsAreaSize = layoutChild(
        1,
        BoxConstraints(maxWidth: size.width, maxHeight: size.height),
      );
      tabsAreaWidth = tabsAreaSize.width;
    }

    final double contentAreaWidth = math.max(0, size.width - tabsAreaWidth);
    final contentAreaSize = Size(contentAreaWidth, size.height);
    layoutChild(2, BoxConstraints.tight(contentAreaSize));

    if (tabBarPosition == TabBarPosition.right) {
      positionChild(2, Offset.zero);
      if (hasChild(1)) {
        positionChild(1, Offset(contentAreaWidth, 0));
      }
    } else {
      // left
      if (hasChild(1)) {
        positionChild(1, Offset.zero);
      }
      positionChild(2, Offset(tabsAreaWidth, 0));
    }
  }

  @override
  bool shouldRelayout(covariant _TabbedViewLayout oldDelegate) {
    return true;
  }
}
