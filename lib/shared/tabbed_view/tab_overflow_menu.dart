// The tab strip is driven through tabbed_view's internal button and menu-item
// types; its public barrel does not re-export them.
// ignore_for_file: implementation_imports

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';

import 'package:tabbed_view/src/tab_button.dart';
import 'package:tabbed_view/src/tabbed_view_menu_item.dart';

/// Buttons for the trailing edge of the editor tab strip: a menu of every
/// open tab.
///
/// The upstream package renders this button only when its own layout runs out of
/// room and moves the leftover tabs into `hiddenTabs`. Pyrite's strip is a
/// `SingleChildScrollView` instead, so `hiddenTabs` is always empty and that
/// button can never appear — yet the strip still scrolls tabs out of sight,
/// which is precisely the situation an overflow menu exists for. So it lists
/// every open tab instead of only the hidden ones.
///
/// Nothing is shown for a single tab: there is nothing to pick from, and a
/// button that opens a one-line menu is pure noise on a small window.
List<TabButton> buildTabOverflowButtons(BuildContext context, int tabsCount) {
  final container = ProviderScope.containerOf(context);
  if (tabsCount < 2) return const [];

  return [
    TabButton.menu((_) {
      // Read on open, not on build: the menu outlives the tab list it was
      // built from, and the user may have closed tabs since.
      final controller = container.read(tabbedViewControllerProvider);
      return [
        for (var i = 0; i < controller.tabs.length; i++)
          TabbedViewMenuItem(
            text: controller.tabs[i].text,
            onSelection: () => container
                .read(tabbedViewControllerProvider.notifier)
                .onTabTap(controller.tabs[i], i),
          ),
      ];
    }),
  ];
}
