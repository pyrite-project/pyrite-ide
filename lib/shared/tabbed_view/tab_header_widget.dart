// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/editor/problems_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/shared/tabbed_view/unsaved_tab_guard.dart';

import 'package:tabbed_view/src/tab_bar_position.dart';
import 'package:tabbed_view/src/tab_button.dart';
import 'package:tabbed_view/src/tab_data.dart';
import 'package:tabbed_view/src/tab_status.dart';
import 'package:tabbed_view/src/theme/side_tabs_layout.dart';
import 'package:tabbed_view/src/theme/tab_status_theme_data.dart';
import 'package:tabbed_view/src/theme/tab_theme_data.dart';
import 'package:tabbed_view/src/theme/tabbed_view_theme_data.dart';
import 'package:tabbed_view/src/theme/theme_widget.dart';
import 'package:tabbed_view/src/theme/vertical_alignment.dart';
import 'package:tabbed_view/src/unselected_tab_buttons_behavior.dart';
import 'package:tabbed_view/src/internal/tab/tab_button_widget.dart';
import 'package:tabbed_view/src/internal/tabbed_view_provider.dart';

/// The count VSCode prints beside a tab name whose file has problems.
///
/// Errors win over warnings: showing "3" in orange next to three red ones would
/// read as "three problems, mild", which is the opposite of what the file needs.
/// The digits stay small and low-contrast so the label still reads first, and
/// drop further on an unselected tab; the tooltip carries the full breakdown.
class _ProblemsBadge extends StatelessWidget {
  const _ProblemsBadge(this.problems, {required this.dimmed});

  final TabProblemCounts problems;

  /// Whether the tab is not the active one, which VSCode reflects as a fainter
  /// decoration.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final hasErrors = problems.errors > 0;
    final count = hasErrors ? problems.errors : problems.warnings;
    final color = hasErrors
        ? Theme.of(context).colorScheme.error
        : const Color(0xFFF2A33C);

    final container = ProviderScope.containerOf(context);
    final message = translateWithReplacementsFromRegistry(
      container.read(dataRegistryProvider),
      container.read(activeLocaleProvider),
      I18nKey.tabProblemBadgeTooltip,
      {'errors': '${problems.errors}', 'warnings': '${problems.warnings}'},
    );

    final textStyle = DefaultTextStyle.of(context).style;

    return Tooltip(
      message: message,
      child: Text(
        '$count',
        style: textStyle.copyWith(
          fontSize: (textStyle.fontSize ?? 13) * 0.8,
          height: 1.1,
          fontWeight: FontWeight.w500,
          color: color.withValues(alpha: dimmed ? 0.45 : 0.85),
        ),
      ),
    );
  }
}

class TabHeaderWidget extends StatelessWidget {
  const TabHeaderWidget({
    super.key,
    required this.index,
    required this.status,
    required this.provider,
    required this.onClose,
    required this.sideTabsLayout,
    this.problems,
  });

  final int index;
  final TabStatus status;
  final TabbedViewProvider provider;
  final Function onClose;
  final SideTabsLayout sideTabsLayout;

  /// Diagnostics for the file behind this tab, when it shows one.
  final TabProblemCounts? problems;

  @override
  Widget build(BuildContext context) {
    final TabbedViewThemeData theme = TabbedViewTheme.of(context);
    final TabThemeData tabTheme = theme.tab;
    List<Widget> textAndButtons = _textAndButtons(context);

    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center;
    if (tabTheme.verticalAlignment == VerticalAlignment.top) {
      crossAxisAlignment = CrossAxisAlignment.start;
    } else if (tabTheme.verticalAlignment == VerticalAlignment.bottom) {
      crossAxisAlignment = CrossAxisAlignment.end;
    }
    Widget textAndButtonsContainer = ClipRect(
      child: IntrinsicWidth(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: crossAxisAlignment,
          children: textAndButtons,
        ),
      ),
    );

    final TabStatusThemeData? statusTheme = tabTheme.getTabThemeFor(status);

    EdgeInsetsGeometry? padding;
    if (textAndButtons.length == 1) {
      padding =
          statusTheme?.paddingWithoutButton ?? tabTheme.paddingWithoutButton;
    }
    padding ??= statusTheme?.padding ?? tabTheme.padding;

    Widget widget = Container(padding: padding, child: textAndButtonsContainer);

    if (theme.tabsArea.position.isVertical &&
        sideTabsLayout == SideTabsLayout.rotated) {
      // Rotate the tab content
      if (theme.tabsArea.position == TabBarPosition.left) {
        widget = RotatedBox(quarterTurns: -1, child: widget);
      } else if (theme.tabsArea.position == TabBarPosition.right) {
        widget = RotatedBox(quarterTurns: 1, child: widget);
      }
    }

    return widget;
  }

  /// Builds a list with title text and buttons.
  List<Widget> _textAndButtons(BuildContext context) {
    final TabbedViewThemeData theme = TabbedViewTheme.of(context);
    final TabThemeData tabTheme = theme.tab;
    List<Widget> textAndButtons = [];

    TabData tab = provider.controller.tabs[index];
    TabStatusThemeData? statusTheme = tabTheme.getTabThemeFor(status);

    Color color = statusTheme?.buttonColor ?? tabTheme.buttonColor;
    Color hoverColor =
        statusTheme?.hoveredButtonColor ?? tabTheme.hoveredButtonColor ?? color;
    Color disabledColor =
        statusTheme?.disabledButtonColor ?? tabTheme.disabledButtonColor;

    BoxDecoration? normalBackground =
        statusTheme?.buttonBackground ?? tabTheme.buttonBackground;
    BoxDecoration? hoverBackground =
        statusTheme?.hoveredButtonBackground ??
        tabTheme.hoveredButtonBackground;
    BoxDecoration? disabledBackground =
        statusTheme?.disabledButtonBackground ??
        tabTheme.disabledButtonBackground;

    TextStyle? textStyle = tabTheme.textStyle;
    if (statusTheme?.fontColor != null) {
      if (textStyle != null) {
        textStyle = textStyle.copyWith(color: statusTheme?.fontColor);
      } else {
        textStyle = TextStyle(color: statusTheme?.fontColor);
      }
    }

    final List<TabButton>? buttons = tab.buttonsBuilder?.call(context);

    EdgeInsets? padding;
    if (tab.closable ||
        buttons != null && buttons.isNotEmpty && tabTheme.buttonsOffset > 0) {
      padding = EdgeInsets.only(
        right: tabTheme.buttonsOffset,
      ); // Use final buttonsOffset
    }

    Widget? leading = tab.leading?.call(context, status);
    if (leading != null) {
      textAndButtons.add(leading);
    }
    Widget tabText = Text(
      tab.text,
      style: textStyle,
      overflow: TextOverflow.ellipsis,
    );
    if (tab.tooltip != null) {
      // `container: true` prevents this anchor from being merged into a
      // neighbouring tab's semantics node. A Tooltip links its overlay content
      // to the anchor with a traversal-parent identifier, and a merge drops
      // that identifier instead of combining it, which orphans the tooltip
      // node and makes Windows reject the entire accessibility tree update
      // ("will not be in the tree and is not the new root"). The tab strip is
      // the worst place for this: tabs sit side by side and a partially
      // visible one is common. See flutter/flutter#182444.
      tabText = Tooltip(
        message: tab.tooltip!,
        child: Semantics(container: true, child: tabText),
      );
    }
    textAndButtons.add(
      Expanded(
        child: Container(
          alignment: Alignment.centerLeft,
          padding: padding,
          child: tab.textSize == null || tab.textSize! <= 0
              ? tabText
              : SizedBox(width: tab.textSize, child: tabText),
        ),
      ),
    );

    if (buttons != null) {
      final bool enabled =
          provider.draggingTabIndex == null &&
          (status == TabStatus.selected ||
              provider.unselectedTabButtonsBehavior ==
                  UnselectedTabButtonsBehavior.allEnabled);

      for (int i = 0; i < buttons.length; i++) {
        EdgeInsets? padding;
        if (i > 0 && i < buttons.length && tabTheme.buttonsGap > 0) {
          // Use final buttonsGap
          padding = EdgeInsets.only(left: tabTheme.buttonsGap);
        }
        TabButton button = buttons[i];
        textAndButtons.add(
          Container(
            padding: padding,
            child: TabButtonWidget(
              button: button,
              enabled: enabled,
              normalColor: color,
              hoverColor: hoverColor,
              disabledColor: disabledColor,
              normalBackground: normalBackground,
              hoverBackground: hoverBackground,
              disabledBackground: disabledBackground,
              iconSize: button.iconSize != null
                  ? button.iconSize!
                  : tabTheme.buttonIconSize,
              themePadding: tabTheme.buttonPadding,
            ),
          ),
        );
      }
    }
    if (problems != null && (problems!.errors > 0 || problems!.warnings > 0)) {
      EdgeInsets? badgePadding;
      if (tabTheme.buttonsGap > 0) {
        badgePadding = EdgeInsets.only(left: tabTheme.buttonsGap);
      }
      textAndButtons.add(
        Container(
          padding: badgePadding,
          child: _ProblemsBadge(
            problems!,
            dimmed: status != TabStatus.selected,
          ),
        ),
      );
    }
    if (tab.closable) {
      final bool enabled =
          provider.draggingTabIndex == null &&
          (status == TabStatus.selected ||
              provider.unselectedTabButtonsBehavior !=
                  UnselectedTabButtonsBehavior.allDisabled);

      EdgeInsets? padding;
      if (buttons != null && buttons.isNotEmpty && tabTheme.buttonsGap > 0) {
        padding = EdgeInsets.only(left: tabTheme.buttonsGap);
      }
      TabButton closeButton = TabButton.icon(
        tabTheme.closeIcon,
        onPressed: () async {
          final TabData tabData = provider.controller.tabs[index];
          if (!await confirmCloseUnsavedTab(context, tabData)) return;
          await _onClose(context, index);
        },
        toolTip: provider.closeButtonTooltip,
      );
      textAndButtons.add(
        Container(
          padding: padding,
          child: TabButtonWidget(
            button: closeButton,
            enabled: enabled,
            normalColor: color,
            hoverColor: hoverColor,
            disabledColor: disabledColor,
            normalBackground: normalBackground,
            hoverBackground: hoverBackground,
            disabledBackground: disabledBackground,
            iconSize: tabTheme.buttonIconSize,
            themePadding: tabTheme.buttonPadding,
          ),
        ),
      );
    }

    return textAndButtons;
  }

  Future<void> _onClose(BuildContext context, int index) async {
    TabData tabData = provider.controller.getTabByIndex(index);
    if (provider.tabRemoveInterceptor == null ||
        (await provider.tabRemoveInterceptor!(context, index, tabData))) {
      onClose();
      if (!context.mounted) return;
      // Check if the tab still exists and/or update with new index
      // if another tab has been removed
      index = provider.controller.tabs.indexOf(tabData);
      if (index != -1) {
        provider.controller.removeTab(index);
        final container = ProviderScope.containerOf(context);
        if (identical(
          provider.controller,
          container.read(tabbedViewControllerProvider),
        )) {
          container
              .read(tabbedViewControllerProvider.notifier)
              .afterTabClose(index, tabData);
        }
      }
    }
  }
}
