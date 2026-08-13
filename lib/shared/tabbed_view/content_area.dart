// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/material.dart';
import 'package:tabbed_view/src/internal/tabbed_view_provider.dart';
import 'package:tabbed_view/src/tab_bar_position.dart';
import 'package:tabbed_view/src/theme/tabbed_view_theme_data.dart';
import 'package:tabbed_view/src/theme/theme_widget.dart';

/// Displays tab content without using a [GlobalKey] for kept-alive tabs.
class ContentArea extends StatelessWidget {
  const ContentArea({
    super.key,
    required this.tabsAreaVisible,
    required this.provider,
  });

  final bool tabsAreaVisible;
  final TabbedViewProvider provider;

  @override
  Widget build(BuildContext context) {
    final controller = provider.controller;
    final theme = TabbedViewTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final children = <Widget>[];

        for (var index = 0; index < controller.tabs.length; index++) {
          final tab = controller.tabs[index];
          final selected = controller.selectedIndex == index;
          if (!tab.keepAlive && !selected) continue;

          Widget? child = provider.contentBuilder != null
              ? provider.contentBuilder!(context, index)
              : tab.content;
          if (child != null) {
            child = ExcludeFocus(excluding: !selected, child: child);
          }
          if (tab.keepAlive) {
            child = Offstage(offstage: !selected, child: child);
          }

          children.add(
            Positioned.fill(
              // This key only needs to preserve content within this Stack.
              // A GlobalKey cannot be shared while a tab is moved between views.
              key: tab.uniqueKey,
              child: Container(child: child),
            ),
          );
        }

        final content = NotificationListener<SizeChangedLayoutNotification>(
          child: SizeChangedLayoutNotifier(child: Stack(children: children)),
        );
        return Container(
          decoration: BoxDecoration(
            color: theme.contentArea.color,
            borderRadius: _buildBorderRadius(theme),
            border: _buildBorder(theme),
          ),
          padding: theme.contentArea.padding,
          child: content,
        );
      },
    );
  }

  BorderRadius _buildBorderRadius(TabbedViewThemeData theme) {
    final radius = Radius.circular(theme.contentArea.borderRadius);
    final position = theme.tabsArea.position;
    return BorderRadius.only(
      topLeft:
          position == TabBarPosition.bottom || position == TabBarPosition.right
          ? Radius.zero
          : radius,
      topRight:
          position == TabBarPosition.bottom || position == TabBarPosition.left
          ? Radius.zero
          : radius,
      bottomLeft:
          position == TabBarPosition.top || position == TabBarPosition.right
          ? Radius.zero
          : radius,
      bottomRight:
          position == TabBarPosition.top || position == TabBarPosition.left
          ? Radius.zero
          : radius,
    );
  }

  Border _buildBorder(TabbedViewThemeData theme) {
    final needsDivider =
        !theme.isDividerWithinTabArea &&
        ((provider.controller.length == 0 && theme.alwaysShowDivider) ||
            provider.controller.length > 0);
    final divider = needsDivider
        ? theme.divider ?? BorderSide.none
        : BorderSide.none;
    final borderSide = theme.contentArea.border ?? BorderSide.none;
    final position = theme.tabsArea.position;

    return Border(
      top: position == TabBarPosition.bottom ? divider : borderSide,
      bottom: position == TabBarPosition.top ? divider : borderSide,
      left: position == TabBarPosition.right ? divider : borderSide,
      right: position == TabBarPosition.left ? divider : borderSide,
    );
  }
}
