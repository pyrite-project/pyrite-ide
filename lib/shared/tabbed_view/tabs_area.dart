// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/material.dart';
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
import 'package:tabbed_view/src/internal/tabs_area/tabs_area_corner.dart';
import 'package:tabbed_view/src/internal/tabs_area/tabs_area_layout.dart';
import 'package:tabbed_view/src/internal/tabs_area/tabs_area_layout_child.dart';

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

  final HiddenTabs _hiddenTabs = HiddenTabs();

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
      children.add(
        TabsAreaLayoutChild(
          sizeHolder: sizeHolder,
          child: TabWidget(
            key: controller.tabs[index].uniqueKey,
            index: index,
            status: status,
            provider: widget.provider,
            sizeHolder: sizeHolder,
            updateHoveredIndex: _updateHoveredIndex,
            onClose: _onTabClose,
          ),
        ),
      );
    }

    children.add(
      TabsAreaCorner(provider: widget.provider, hiddenTabs: _hiddenTabs),
    );

    Widget tabsAreaLayout = TabsAreaLayout(
      theme: theme,
      hiddenTabs: _hiddenTabs,
      selectedTabIndex: controller.selectedIndex,
      children: children,
    );
    tabsAreaLayout = ClipRect(child: tabsAreaLayout);

    Widget content = tabsAreaLayout;

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
