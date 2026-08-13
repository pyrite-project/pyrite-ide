// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/shared/tabbed_view/native_tab_drag.dart';

import 'package:tabbed_view/src/draggable_config.dart';
import 'package:tabbed_view/src/tab_data.dart';
import 'package:tabbed_view/src/tab_status.dart';
import 'package:tabbed_view/src/theme/side_tabs_layout.dart';
import 'package:tabbed_view/src/theme/tab_decoration_builder.dart';
import 'package:tabbed_view/src/theme/tab_theme_data.dart';
import 'package:tabbed_view/src/theme/tabbed_view_theme_data.dart';
import 'package:tabbed_view/src/theme/theme_widget.dart';
import 'package:tabbed_view/src/theme/vertical_alignment.dart';
import 'package:tabbed_view/src/internal/size_holder.dart';
import 'package:tabbed_view/src/internal/tabbed_view_provider.dart';
import 'package:pyrite_ide/shared/tabbed_view/tab_header_widget.dart';

/// Listener for the tabs with the mouse over.
typedef UpdateHoveredIndex = void Function(int? tabIndex);

/// Default maximum size of the tab on its main axis when the theme does not
/// define one. Keeps long tab titles from growing without limit.
const double _defaultMaxTabMainSize = 240;

/// The tab widget. Displays the tab text and its buttons.
class TabWidget extends ConsumerWidget {
  const TabWidget({
    required Key key,
    required this.index,
    required this.status,
    required this.provider,
    required this.updateHoveredIndex,
    required this.onClose,
    required this.sizeHolder,
  }) : super(key: key);

  final int index;
  final TabStatus status;
  final TabbedViewProvider provider;
  final UpdateHoveredIndex updateHoveredIndex;
  final Function onClose;
  final SizeHolder sizeHolder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TabData tab = provider.controller.tabs[index];
    final TabbedViewThemeData theme = TabbedViewTheme.of(context);
    final TabThemeData tabTheme = theme.tab;

    Widget widget = TabHeaderWidget(
      provider: provider,
      index: index,
      onClose: onClose,
      status: status,
      sideTabsLayout: theme.tabsArea.sideTabsLayout,
    );
    widget = _TabHeaderProxy(sizeHolder: sizeHolder, child: widget);

    TabDecorationBuilder? decorationBuilder = tabTheme.decorationBuilder;
    while (decorationBuilder != null) {
      TabDecoration tabDecoration = decorationBuilder(
        status: status,
        tabBarPosition: theme.tabsArea.position,
      );
      if (tabDecoration.border != null || tabDecoration.color != null) {
        final BorderRadius? borderRadius = tabDecoration.borderRadius;
        if (borderRadius != null) {
          widget = Container(
            decoration: BoxDecoration(
              color: tabDecoration.color,
              border: tabDecoration.border,
              borderRadius: borderRadius,
            ),
            child: ClipRRect(borderRadius: borderRadius, child: widget),
          );
        } else {
          widget = Container(
            decoration: BoxDecoration(
              color: tabDecoration.color,
              border: tabDecoration.border,
            ),
            child: widget,
          );
        }
      }
      decorationBuilder = tabDecoration.wrapperBorderBuilder;
    }

    final maxMainSize = tabTheme.maxMainSize ?? _defaultMaxTabMainSize;
    BoxConstraints constraints;
    if (theme.tabsArea.position.isHorizontal) {
      constraints = BoxConstraints(maxWidth: maxMainSize);
    } else {
      // For vertical tab bars, the constraint depends on the layout.
      if (theme.tabsArea.sideTabsLayout == SideTabsLayout.stacked) {
        // Stacked tabs are not rotated, so their main axis is width.
        constraints = BoxConstraints(maxWidth: maxMainSize);
      } else {
        // Rotated tabs have their logical width as physical height.
        constraints = BoxConstraints(maxHeight: maxMainSize);
      }
    }
    widget = ConstrainedBox(constraints: constraints, child: widget);

    MouseCursor cursor = MouseCursor.defer;
    if (provider.draggingTabIndex == null && status == TabStatus.selected) {
      cursor = SystemMouseCursors.click;
    }

    final Widget interactiveTab = widget;

    widget = MouseRegion(
      cursor: cursor,
      onEnter: (event) => updateHoveredIndex(index),
      onExit: (event) => updateHoveredIndex(null),
      child: provider.draggingTabIndex == null
          ? GestureDetector(
              onTap: () {
                final editorController = ref.read(tabbedViewControllerProvider);
                if (identical(provider.controller, editorController)) {
                  ref
                      .read(tabbedViewControllerProvider.notifier)
                      .onTabTap(tab, index);
                } else {
                  provider.controller.selectedIndex = index;
                }
              },
              onSecondaryTapDown: (details) {
                if (provider.onTabSecondaryTap != null) {
                  TabData tab = provider.controller.tabs[index];
                  provider.onTabSecondaryTap!(index, tab, details);
                }
              },
              child: interactiveTab,
            )
          : interactiveTab,
    );

    if (tab.draggable) {
      DraggableConfig draggableConfig = DraggableConfig.defaultConfig;
      if (provider.onDraggableBuild != null) {
        draggableConfig = provider.onDraggableBuild!(
          provider.controller,
          index,
          tab,
        );
      }

      if (draggableConfig.canDrag) {
        Widget feedback = draggableConfig.feedback != null
            ? draggableConfig.feedback!
            : _TabDragFeedback(tab: tab, tabTheme: tabTheme);

        widget = NativeTabDraggable(
          provider: provider,
          tab: tab,
          index: index,
          config: draggableConfig,
          feedback: feedback,
          child: widget,
        );

        widget = Opacity(
          opacity: provider.draggingTabIndex != index
              ? 1
              : tabTheme.draggingOpacity,
          child: widget,
        );
      }
    }

    if (provider.tabReorderEnabled &&
        provider.draggingTabIndex != TabDataHelper.indexFrom(tab)) {
      return NativeTabDropRegion(
        provider: provider,
        position: theme.tabsArea.position,
        targetTab: tab,
        child: widget,
      );
    }
    return widget;
  }
}

class _TabHeaderProxy extends SingleChildRenderObjectWidget {
  const _TabHeaderProxy({
    required Widget super.child,
    required this.sizeHolder,
  });

  final SizeHolder sizeHolder;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderTabContentProxy(sizeHolder: sizeHolder);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTabContentProxy renderObject,
  ) {
    renderObject.sizeHolder = sizeHolder;
  }
}

class _TabDragFeedback extends StatelessWidget {
  const _TabDragFeedback({required this.tab, required this.tabTheme});

  final TabData tab;
  final TabThemeData tabTheme;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = [];
    final Widget? leading = tab.leading?.call(context, TabStatus.normal);
    if (leading != null) {
      children.add(leading);
    }

    Widget text = Text(
      tab.text,
      style: tabTheme.textStyle,
      overflow: TextOverflow.ellipsis,
    );
    if (tab.textSize != null && tab.textSize! > 0) {
      text = SizedBox(width: tab.textSize, child: text);
    }
    children.add(text);

    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center;
    if (tabTheme.verticalAlignment == VerticalAlignment.top) {
      crossAxisAlignment = CrossAxisAlignment.start;
    } else if (tabTheme.verticalAlignment == VerticalAlignment.bottom) {
      crossAxisAlignment = CrossAxisAlignment.end;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: tabTheme.draggingDecoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxisAlignment,
        children: children,
      ),
    );
  }
}

class _RenderTabContentProxy extends RenderProxyBox {
  _RenderTabContentProxy({required SizeHolder sizeHolder})
    : _sizeHolder = sizeHolder;

  SizeHolder _sizeHolder;

  SizeHolder get sizeHolder => _sizeHolder;
  set sizeHolder(SizeHolder value) {
    if (_sizeHolder != value) {
      _sizeHolder = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    if (child != null) {
      child!.layout(constraints, parentUsesSize: true);
      size = child!.size;
    } else {
      size = constraints.biggest;
    }
    sizeHolder.size = size;
  }
}
