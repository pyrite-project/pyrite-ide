// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/shared/tabbed_view/unsaved_tab_guard.dart';

import 'package:tabbed_view/src/internal/tabbed_view_provider.dart';
import 'package:tabbed_view/src/tab_data.dart';
import 'package:tabbed_view/src/tabbed_view_controller.dart';

/// The tabs a "close others" should take: everything but [keep].
List<TabData> otherTabs(List<TabData> tabs, TabData keep) => [
  for (final tab in tabs)
    if (!identical(tab, keep)) tab,
];

/// The tabs a "close to the right" should take: those that come after [index].
List<TabData> tabsToTheRightOf(List<TabData> tabs, int index) =>
    index + 1 >= tabs.length ? const [] : tabs.sublist(index + 1);

/// Closes [targets] out of [controller], prompting for each unsaved tab.
///
/// This is the strip-independent half of a close: a group's own controller is
/// enough, which is what closing an editor group has. Tabs are matched by
/// identity because every removal shifts the ones after it, so an index
/// captured before the first close points at the wrong tab afterwards.
///
/// A cancel from the unsaved prompt stops the batch: the user asked to keep
/// that file, and the rest of the tabs were only collateral to the request.
///
/// [canRemove] is the caller's veto -- the tab strip's remove interceptor --
/// consulted after the unsaved prompt and before the removal. [onClosed] runs
/// once per removed tab, the way the strip's own close callback does.
Future<void> closeTabsInController(
  BuildContext context,
  TabbedViewController controller,
  Iterable<TabData> targets, {
  VoidCallback? onClosed,
  FutureOr<bool> Function(int index, TabData tab)? canRemove,
}) async {
  final container = ProviderScope.containerOf(context);

  for (final tab in targets.toList()) {
    // A pinned tab -- the welcome page -- is the editor's floor and must
    // survive every bulk close, so "close others" and "close all" skip it
    // rather than removing it.
    if (!tab.closable) continue;
    if (!context.mounted) return;
    if (!controller.tabs.contains(tab)) continue;
    if (!await confirmCloseUnsavedTab(context, tab)) return;
    if (!context.mounted) return;

    final current = controller.tabs.indexOf(tab);
    if (current == -1) continue;
    if (canRemove != null && !await canRemove(current, tab)) return;
    if (!context.mounted) return;

    controller.removeTab(current);
    onClosed?.call();
    await container
        .read(tabbedViewControllerProvider.notifier)
        .afterTabClose(tab);
  }
}

/// Closes [targets] one at a time through [provider]'s strip.
///
/// Tabs are matched by identity rather than by index: every removal shifts the
/// tabs after it, so an index captured before the first one points at the
/// wrong tab afterwards. Each closed tab is handed to the editor notifier,
/// whichever group it was in, so the document's resources are released.
///
/// A cancel from the unsaved prompt stops the batch. The user asked to keep that
/// file, and the rest of the tabs were only collateral to the request.
Future<void> closeTabs(
  BuildContext context,
  TabbedViewProvider provider,
  Iterable<TabData> targets, {
  VoidCallback? onClosed,
}) {
  return closeTabsInController(
    context,
    provider.controller,
    targets,
    onClosed: onClosed,
    canRemove: provider.tabRemoveInterceptor == null
        ? null
        : (index, tab) => provider.tabRemoveInterceptor!(context, index, tab),
  );
}
