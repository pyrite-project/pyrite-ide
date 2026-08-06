import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/constants/navigation_bar.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/desktop_terminal_provider.dart';
import 'package:pyrite_ide/core/services/editor/repl_input_controller.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/editor/lsp_state.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/git/git_status_summary_provider.dart';
import 'package:pyrite_ide/core/services/status_bar/running_operation_provider.dart';
import 'package:pyrite_ide/core/services/status_bar/status_bar_registry.dart';
import 'package:pyrite_ide/core/sdk/command_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/menu_resolver.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/sdk/plugin_resources.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_icons.dart';
import 'package:pyrite_ide/features/window.dart';
import 'package:pyrite_ide/features/function_page/repl_surface.dart';
import 'package:pyrite_ide/pages/editor/main.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:xterm/xterm.dart';

final StateProvider<int> bottomPanelTabProvider = StateProvider<int>(
  (ref) => 0,
);

Widget consolePage() {
  return const ConsolePage();
}

class ConsolePage extends ConsumerWidget {
  const ConsolePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(serialProvider).isConnected;
    final webReplState = ref.watch(webReplProvider);
    final webReplConnected = webReplState.state == WebReplState.connected;
    final useWebRepl =
        webReplConnected || webReplState.state == WebReplState.waitingPassword;
    final selectedTab = ref.watch(bottomPanelTabProvider);
    final actions = _buildConsoleActions(
      ref,
      selectedTab,
      isConnected,
      webReplConnected,
      useWebRepl,
    );

    return Column(
      children: [
        _BottomPanelTabs(selectedIndex: selectedTab, actions: actions),
        Expanded(
          child: IndexedStack(
            index: selectedTab,
            children: const [
              ReplView(),
              OutputLogView(),
              DesktopTerminalView(),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildConsoleActions(
    WidgetRef ref,
    int selectedTab,
    bool isConnected,
    bool webReplConnected,
    bool useWebRepl,
  ) {
    switch (selectedTab) {
      case 1:
        return [
          IconButton(
            tooltip: translateForWidget(ref, I18nKey.bottomPanelClearOutput),
            onPressed: () => ref.read(ideOutputLogProvider.notifier).clear(),
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ];
      case 2:
        return const [];
      default:
        return [
          if (!isConnected && !webReplConnected)
            IconButton(
              tooltip: translateForWidget(
                ref,
                I18nKey.bottomPanelConnectWebRepl,
              ),
              onPressed: () {
                ref.read(webReplProvider.notifier).connect();
              },
              icon: const Icon(Icons.wifi),
            ),
          IconButton(
            tooltip: translateForWidget(ref, I18nKey.bottomPanelClearTerminal),
            onPressed: () {
              replController.clearSelection();
              repl.clear();
              replClearSink?.call();
              final input = ref.read(replInputControllerProvider);
              if (replClearSink == null) {
                if (input.mode == ReplInteractionMode.prompt) {
                  repl.write('>>> ');
                } else if (input.mode == ReplInteractionMode.continuation) {
                  repl.write('... ');
                }
              }
            },
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
          IconButton(
            tooltip: useWebRepl
                ? translateForWidget(ref, I18nKey.editorToolbarInterruptDevice)
                : translateForWidget(
                    ref,
                    isConnected
                        ? I18nKey.editorToolbarInterruptDevice
                        : I18nKey.editorToolbarInterruptNeedsDevice,
                  ),
            onPressed: (useWebRepl || isConnected)
                ? () {
                    if (useWebRepl) {
                      ref.read(webReplProvider.notifier).sendCommand("\x03");
                    } else {
                      ref.read(serialProvider.notifier).sendCommand("\x03");
                    }
                  }
                : null,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
          IconButton(
            tooltip: useWebRepl
                ? translateForWidget(ref, I18nKey.editorToolbarSoftReboot)
                : translateForWidget(
                    ref,
                    isConnected
                        ? I18nKey.editorToolbarSoftReboot
                        : I18nKey.editorToolbarSoftRebootNeedsDevice,
                  ),
            onPressed: (useWebRepl || isConnected)
                ? () {
                    if (useWebRepl) {
                      ref.read(webReplProvider.notifier).sendCommand("\x04");
                    } else {
                      ref.read(serialProvider.notifier).sendCommand("\x04");
                    }
                  }
                : null,
            icon: const Icon(Icons.restart_alt),
          ),
        ];
    }
  }
}

class _BottomPanelTabs extends ConsumerWidget {
  const _BottomPanelTabs({required this.selectedIndex, required this.actions});

  final int selectedIndex;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      decoration: BoxDecoration(color: scheme.surface),
      child: Row(
        children: [
          _BottomPanelTab(
            label: 'REPL',
            icon: Icons.terminal,
            index: 0,
            selectedIndex: selectedIndex,
          ),
          _BottomPanelTab(
            label: I18nKey.bottomPanelLogTab,
            icon: Icons.article_outlined,
            index: 1,
            selectedIndex: selectedIndex,
          ),
          _BottomPanelTab(
            label: I18nKey.bottomPanelTerminalTab,
            icon: Icons.terminal_outlined,
            index: 2,
            selectedIndex: selectedIndex,
          ),
          const Spacer(),
          if (actions.isNotEmpty) ...[
            SizedBox(
              height: 18,
              child: VerticalDivider(width: 1, color: scheme.outlineVariant),
            ),
            const SizedBox(width: 4),
            for (final action in actions)
              SizedBox.square(
                dimension: 30,
                child: IconButtonTheme(
                  data: const IconButtonThemeData(
                    style: ButtonStyle(
                      iconSize: WidgetStatePropertyAll(17),
                      padding: WidgetStatePropertyAll(EdgeInsets.zero),
                      minimumSize: WidgetStatePropertyAll(Size.square(30)),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  child: action,
                ),
              ),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _BottomPanelTab extends ConsumerWidget {
  const _BottomPanelTab({
    required this.label,
    required this.icon,
    required this.index,
    required this.selectedIndex,
  });

  final Object label;
  final IconData icon;
  final int index;
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = index == selectedIndex;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => ref.read(bottomPanelTabProvider.notifier).state = index,
      child: Container(
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            UseText(
              label,
              style: TextStyle(
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<shadcn.ResizablePane> buildConsoleView(
  WidgetRef ref,
  Widget child, {
  bool allowConsole = true,
}) {
  final List<shadcn.ResizablePane> children = [];
  children.add(
    shadcn.ResizablePane.flex(initialFlex: 3, minSize: 240, child: child),
  );

  if (allowConsole && ref.watch(consolePageShow)) {
    children.add(
      shadcn.ResizablePane.flex(
        initialFlex: 1,
        minSize: 160,
        child: consolePage(),
      ),
    );
  }

  return children;
}

Widget buildShadcnLayer(BuildContext context, Widget child) {
  return shadcn.ShadcnLayer(
    theme: shadcn.ThemeData(
      colorScheme: Theme.of(context).brightness == Brightness.light
          ? shadcn.ColorSchemes.lightNeutral
          : shadcn.ColorSchemes.darkNeutral,
    ),
    child: child,
  );
}

Widget buildVerticalWorkspace(
  BuildContext context,
  WidgetRef ref,
  Widget child, {
  bool allowConsole = true,
}) {
  return buildShadcnLayer(
    context,
    shadcn.ResizablePanel.vertical(
      optionalDivider: false,
      draggerBuilder: (context) {
        return shadcn.HorizontalResizableDragger();
      },
      children: buildConsoleView(ref, child, allowConsole: allowConsole),
    ),
  );
}

void showMobileConsoleSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.55,
        child: consolePage(),
      );
    },
  );
}

class ConsoleToggle extends ConsumerWidget {
  const ConsoleToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final consoleVisible = ref.watch(consolePageShow);
    return IconButton(
      tooltip: translateForWidget(
        ref,
        isMobile
            ? I18nKey.statusOpenConsole
            : (consoleVisible
                  ? I18nKey.statusHideConsole
                  : I18nKey.statusShowRepl),
      ),
      onPressed: () {
        if (isMobile) {
          showMobileConsoleSheet(context);
          return;
        }
        ref.read(consolePageShow.notifier).state = !consoleVisible;
      },
      icon: const Icon(Icons.terminal),
    );
  }
}

class FunctionPaneToggle extends ConsumerWidget {
  const FunctionPaneToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(functionPageShow);
    return IconButton(
      tooltip: translateForWidget(
        ref,
        visible
            ? I18nKey.bottomPanelHideFunctionPanel
            : I18nKey.bottomPanelShowFunctionPanel,
      ),
      onPressed: () {
        ref.read(functionPageShow.notifier).state = !visible;
      },
      icon: Icon(
        visible ? Icons.keyboard_arrow_left : Icons.keyboard_arrow_right,
      ),
    );
  }
}

class ExpansionPaneToggle extends ConsumerWidget {
  const ExpansionPaneToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(expansionPageShow);
    return IconButton(
      tooltip: translateForWidget(
        ref,
        visible
            ? I18nKey.bottomPanelHideExpansionPanel
            : I18nKey.bottomPanelShowExpansionPanel,
      ),
      onPressed: () {
        ref.read(expansionPageShow.notifier).state = !visible;
      },
      icon: Icon(
        visible ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_left,
      ),
    );
  }
}

class RailTrailingActions extends StatelessWidget {
  const RailTrailingActions({super.key});

  @override
  Widget build(BuildContext context) {
    return const Expanded(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FunctionPaneToggle(),
              ExpansionPaneToggle(),
              ConsoleToggle(),
            ],
          ),
        ),
      ),
    );
  }
}

const _pluginViewRoute = '/plugin-view';

class _PluginNavigationItem {
  const _PluginNavigationItem({
    required this.pluginId,
    required this.container,
    required this.viewId,
    this.pluginIcons,
  });

  final String pluginId;
  final PluginNavigationContainerContribution container;
  final String? viewId;
  final PluginIconSet? pluginIcons;

  String get route => Uri(
    path: _pluginViewRoute,
    queryParameters: {
      'plugin': pluginId,
      'container': container.id,
      if (viewId case final String value) 'view': value,
    },
  ).toString();
}

List<_PluginNavigationItem> _pluginNavigationItems(WidgetRef ref) {
  final registry = ref.watch(contributionRegistryProvider);
  final plugins = ref.watch(pluginManagerProvider);
  final containers = registry.navigation.visible.toList()
    ..sort((left, right) {
      final order = left.value.order.compareTo(right.value.order);
      if (order != 0) return order;
      final plugin = left.pluginId.compareTo(right.pluginId);
      if (plugin != 0) return plugin;
      return left.value.id.compareTo(right.value.id);
    });
  return [
    for (final entry in containers)
      _PluginNavigationItem(
        pluginId: entry.pluginId,
        container: entry.value,
        viewId: registry.views.visible
            .where(
              (view) =>
                  view.pluginId == entry.pluginId &&
                  view.value.container == entry.value.id,
            )
            .map((view) => view.value.id)
            .firstOrNull,
        pluginIcons: plugins[entry.pluginId]?.manifest?.icons,
      ),
  ];
}

Widget _pluginNavigationIcon(WidgetRef ref, _PluginNavigationItem item) {
  final icon = _pluginNavigationIconCore(item);
  final enabledPlugins = ref
      .watch(pluginManagerProvider)
      .values
      .where((plugin) => plugin.status == PluginStatus.usable)
      .map((plugin) => plugin.id)
      .toSet();
  final items = ref
      .watch(menuResolverProvider)
      .resolve(
        location: MenuResolver.navigationContext,
        enabledPluginIds: enabledPlugins,
      )
      .where((entry) => entry.pluginId == item.pluginId)
      .toList(growable: false);
  if (items.isEmpty) return icon;
  return Builder(
    builder: (context) => GestureDetector(
      onSecondaryTapDown: (details) => _showNavigationContextMenu(
        context,
        ref,
        items,
        details.globalPosition,
      ),
      onLongPress: () {
        final box = context.findRenderObject() as RenderBox?;
        final offset = box?.localToGlobal(Offset.zero) ?? Offset.zero;
        _showNavigationContextMenu(context, ref, items, offset);
      },
      child: icon,
    ),
  );
}

Widget _pluginNavigationIconCore(_PluginNavigationItem item) {
  final icon = item.container.icon;
  if (icon?.kind == PluginIconKind.material) {
    return Icon(pluginIcon('material:${icon!.value}'));
  }
  final asset = icon?.kind == PluginIconKind.asset
      ? icon!.value
      : item.pluginIcons?.monochrome;
  if (asset == null) return const Icon(Icons.extension_outlined);
  return PluginAssetImage(
    pluginId: item.pluginId,
    assetPath: asset,
    width: 24,
    height: 24,
    monochrome: true,
    fallback: const Icon(Icons.extension_outlined),
  );
}

Future<void> _showNavigationContextMenu(
  BuildContext context,
  WidgetRef ref,
  List<ResolvedMenuItem> items,
  Offset globalPosition,
) async {
  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx,
      globalPosition.dy,
    ),
    items: [
      for (final item in items)
        PopupMenuItem<String>(
          value: item.commandId,
          enabled: item.enabled,
          child: Text(item.title),
        ),
    ],
  );
  if (selected == null || !context.mounted) return;
  try {
    await ref.read(commandServiceProvider).execute(selected);
  } on CommandException catch (error) {
    debugPrint('Navigation command failed (${error.code}): ${error.message}');
  }
}

List<String> _navigationRoutes(
  List<_PluginNavigationItem> plugins, {
  required int builtInCount,
}) => [
  ...routesName.take(builtInCount),
  for (final item in plugins) item.route,
];

int _navigationIndex(
  GoRouterState state,
  List<_PluginNavigationItem> plugins, {
  required int builtInCount,
}) {
  final base = routesName
      .take(builtInCount)
      .toList()
      .indexWhere(
        (route) =>
            state.matchedLocation == route ||
            state.matchedLocation.startsWith('$route/'),
      );
  if (base >= 0) return base;
  if (state.matchedLocation == _pluginViewRoute) {
    final plugin = state.uri.queryParameters['plugin'];
    final container = state.uri.queryParameters['container'];
    final index = plugins.indexWhere(
      (item) => item.pluginId == plugin && item.container.id == container,
    );
    if (index >= 0) return builtInCount + index;
  }
  return -1;
}

NavigationRailDestination _pluginRailDestination(
  WidgetRef ref,
  _PluginNavigationItem item,
) => NavigationRailDestination(
  icon: _pluginNavigationIcon(ref, item),
  selectedIcon: _pluginNavigationIcon(ref, item),
  label: Text(item.container.title),
);

NavigationDrawerDestination _pluginDrawerDestination(
  WidgetRef ref,
  _PluginNavigationItem item,
) => NavigationDrawerDestination(
  icon: _pluginNavigationIcon(ref, item),
  selectedIcon: _pluginNavigationIcon(ref, item),
  label: Text(item.container.title),
);

List<NavigationRailDestination> pluginNavigationRailDestinations(
  WidgetRef ref,
) => [
  for (final item in _pluginNavigationItems(ref))
    _pluginRailDestination(ref, item),
];

List<NavigationDrawerDestination> pluginNavigationDrawerDestinations(
  WidgetRef ref,
) => [
  for (final item in _pluginNavigationItems(ref))
    _pluginDrawerDestination(ref, item),
];

class MobileView extends ConsumerWidget {
  const MobileView({super.key, required this.child, required this.state});

  final Widget child;
  final GoRouterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pluginItems = _pluginNavigationItems(ref);
    // 确保组件重绘后导航栏选择的值与实际显示内容同步
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final routeIndex = _navigationIndex(state, pluginItems, builtInCount: 6);
      if (routeIndex == -1 && state.matchedLocation == _pluginViewRoute) {
        selectedIndexValue = 0;
        ref.read(mobileSelectedIndex.notifier).state = 0;
        context.go(file);
        return;
      }
      // 这里对获取到的路径进行切片处理，并仅获取父页面的路径内容，确保 selectedIndexValue 的值符合预期
      // e.g. "/settings/about" => "/settings"
      if (routeIndex != -1 && routeIndex != ref.read(mobileSelectedIndex)) {
        selectedIndexValue = routeIndex;
        ref.read(mobileSelectedIndex.notifier).state = routeIndex;
      }
    });
    return SafeArea(
      child: Scaffold(
        drawer: mobileNavigationDrawer(context, ref),
        body: Column(
          children: [
            Expanded(child: child),
            EditorToolsBar(showNavigationDrawerButton: true),
          ],
        ),
      ),
    );
  }

  void selectDestination(
    BuildContext context,
    WidgetRef ref,
    int value,
    List<String> navigationRoutes,
  ) {
    selectedIndexValue = value;
    ref.read(tabletSelectedIndex.notifier).state = selectedIndexValue;
    ref.read(mobileSelectedIndex.notifier).state = selectedIndexValue;
    if (selectedIndexValue < desktopRailItems.length) {
      ref.read(desktopSelectedIndex.notifier).state = selectedIndexValue;
    } else {
      ref.read(desktopSelectedIndex.notifier).state = 0;
    }
    context.go(navigationRoutes[selectedIndexValue]);
  }

  Widget mobileNavigationDrawer(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(mobileSelectedIndex);
    final pluginItems = _pluginNavigationItems(ref);
    final destinations = [
      ...drawerItems,
      ...pluginNavigationDrawerDestinations(ref),
    ];
    final navigationRoutes = _navigationRoutes(pluginItems, builtInCount: 6);
    return Builder(
      builder: (drawerContext) {
        return NavigationDrawer(
          selectedIndex:
              selectedIndex >= 0 && selectedIndex < destinations.length
              ? selectedIndex
              : null,
          onDestinationSelected: (value) {
            Navigator.of(drawerContext).pop();
            selectDestination(context, ref, value, navigationRoutes);
          },
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 18, 24, 12),
                child: Row(
                  children: [
                    Image.asset(
                      "assets/icons/app_icon.webp",
                      width: 32,
                      height: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ...destinations,
          ],
        );
      },
    );
  }
}

class TabletView extends ConsumerWidget {
  const TabletView({super.key, required this.child, required this.state});

  final Widget child;
  final GoRouterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pluginItems = _pluginNavigationItems(ref);
    // 确保组件重绘后导航栏选择的值与实际显示内容同步
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final routeIndex = _navigationIndex(state, pluginItems, builtInCount: 6);
      if (routeIndex == -1 && state.matchedLocation == _pluginViewRoute) {
        selectedIndexValue = 0;
        ref.read(tabletSelectedIndex.notifier).state = 0;
        context.go(file);
        return;
      }
      // 这里对获取到的路径进行切片处理，并仅获取父页面的路径内容，确保 selectedIndexValue 的值符合预期
      // e.g. "/settings/about" => "/settings"
      if (routeIndex != -1 && routeIndex != ref.read(tabletSelectedIndex)) {
        selectedIndexValue = routeIndex;
        ref.read(tabletSelectedIndex.notifier).state = routeIndex;
      }
    });
    return SafeArea(
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  railNavigationBar(context, ref),
                  Expanded(child: buildVerticalWorkspace(context, ref, child)),
                ],
              ),
            ),
            const EditorToolsBar(),
          ],
        ),
      ),
    );
  }

  Widget railNavigationBar(BuildContext context, WidgetRef ref) {
    final pluginItems = _pluginNavigationItems(ref);
    final destinations = [
      ...tabletRailItems,
      ...pluginNavigationRailDestinations(ref),
    ];
    final navigationRoutes = _navigationRoutes(pluginItems, builtInCount: 6);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: NavigationRail(
              minWidth: 72,
              backgroundColor: Theme.of(context).colorScheme.surface,
              labelType: NavigationRailLabelType.selected,
              destinations: destinations,
              selectedIndex: ref.watch(tabletSelectedIndex),
              onDestinationSelected: (value) {
                selectedIndexValue = value;
                ref.read(desktopSelectedIndex.notifier).state =
                    selectedIndexValue;
                ref.read(mobileSelectedIndex.notifier).state =
                    selectedIndexValue;
                ref.read(tabletSelectedIndex.notifier).state =
                    selectedIndexValue;
                context.go(navigationRoutes[selectedIndexValue]);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopView extends ConsumerWidget {
  const DesktopView({super.key, required this.child, required this.state});

  final Widget child;
  final GoRouterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pluginItems = _pluginNavigationItems(ref);
    final navigationRoutes = _navigationRoutes(pluginItems, builtInCount: 5);
    // 确保组件重绘后导航栏选择的值与实际显示内容同步
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final routeIndex = _navigationIndex(state, pluginItems, builtInCount: 5);
      // 这里对获取到的路径进行切片处理，并仅获取父页面的路径内容，确保 selectedIndexValue 的值符合预期
      // e.g. "/settings/about" => "/settings"
      if (routeIndex == -1 || routeIndex >= navigationRoutes.length) {
        selectedIndexValue = 0;
        context.go(file);
        return;
      }
      if (routeIndex != -1) {
        selectedIndexValue = routeIndex;
      }
      ref.read(desktopSelectedIndex.notifier).state = selectedIndexValue;
    });
    return SafeArea(
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  railNavigationBar(context, ref),
                  Expanded(child: pageStructure(context, ref)),
                ],
              ),
            ),
            const EditorToolsBar(),
          ],
        ),
      ),
    );
  }

  Widget railNavigationBar(BuildContext context, WidgetRef ref) {
    final pluginItems = _pluginNavigationItems(ref);
    final destinations = [
      ...desktopRailItems,
      ...pluginNavigationRailDestinations(ref),
    ];
    final navigationRoutes = _navigationRoutes(pluginItems, builtInCount: 5);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: NavigationRail(
              backgroundColor: Theme.of(context).colorScheme.surface,
              minWidth: 72,
              labelType: NavigationRailLabelType.selected,
              destinations: destinations,
              selectedIndex: ref.watch(desktopSelectedIndex),
              trailing: const RailTrailingActions(),
              onDestinationSelected: (value) {
                selectedIndexValue = value;
                ref.read(desktopSelectedIndex.notifier).state =
                    selectedIndexValue;
                ref.read(mobileSelectedIndex.notifier).state =
                    selectedIndexValue;
                ref.read(tabletSelectedIndex.notifier).state =
                    selectedIndexValue;
                context.go(navigationRoutes[selectedIndexValue]);
              },
            ),
          ),
        ),
      ),
    );
  }

  List<shadcn.ResizablePane> _pageStructure(
    BuildContext context,
    WidgetRef ref,
  ) {
    final List<shadcn.ResizablePane> children = [];
    final width = MediaQuery.sizeOf(context).width;
    final isEditorRoute = state.matchedLocation.startsWith('/editor');
    final showFunctionPanel = ref.watch(functionPageShow) && !isEditorRoute;
    final showExpansionPanel = ref.watch(expansionPageShow) && width >= 1280;
    final isGitRoute = state.matchedLocation.startsWith('/git');

    // The desktop workspace already owns the central editor pane. Mounting the
    // /editor route child here would render the same tab controller twice.
    if (showFunctionPanel) {
      children.add(
        shadcn.ResizablePane.flex(
          initialFlex: isGitRoute ? 3 : 2,
          minSize: isGitRoute ? 340 : 220,
          child: child,
        ),
      );
    }
    children.add(
      shadcn.ResizablePane.flex(
        initialFlex: 4,
        minSize: 300,
        child: shadcn.ResizablePanel.vertical(
          optionalDivider: false,
          draggerBuilder: (context) {
            return shadcn.HorizontalResizableDragger();
          },
          children: buildConsoleView(ref, const Editor()),
        ),
      ),
    );
    if (showExpansionPanel) {
      children.add(
        shadcn.ResizablePane.flex(
          initialFlex: 2,
          minSize: 200,
          child: ExpansionPage(),
        ),
      );
    }
    return children;
  }

  Widget pageStructure(BuildContext context, WidgetRef ref) {
    return buildShadcnLayer(
      context,
      shadcn.ResizablePanel.horizontal(
        optionalDivider: false,
        draggerBuilder: (context) {
          return shadcn.HorizontalResizableDragger();
        },
        children: _pageStructure(context, ref),
      ),
    );
  }
}

class FunctionPagePadding extends StatelessWidget {
  const FunctionPagePadding({super.key, required this.sliver});
  final Widget sliver;
  @override
  Widget build(BuildContext context) {
    return SliverPadding(padding: const EdgeInsets.all(15), sliver: sliver);
  }
}

class FunctionPageAppBar extends StatelessWidget {
  const FunctionPageAppBar({super.key, this.title});
  final String? title;
  @override
  Widget build(BuildContext context) {
    return SliverAppBar.large(title: UseText(title ?? appName));
  }
}

class ReplView extends ConsumerWidget {
  const ReplView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terminalTheme = buildTerminalTheme(context);
    final terminalStyle = buildTerminalStyle(ref);
    return ReplSurface(
      backgroundColor: terminalTheme.background,
      textStyle: terminalStyle.toTextStyle(),
    );
  }
}

class OutputLogView extends ConsumerWidget {
  const OutputLogView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surface = Theme.of(context).colorScheme.surface;
    return TerminalView(
      ideOutputTerminal,
      controller: ideOutputController,
      theme: buildTerminalTheme(context),
      textStyle: buildTerminalStyle(ref),
      key: ValueKey('output_${surface.toARGB32()}'),
    );
  }
}

class DesktopTerminalView extends ConsumerStatefulWidget {
  const DesktopTerminalView({super.key});

  static bool get isSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  ConsumerState<DesktopTerminalView> createState() =>
      _DesktopTerminalViewState();
}

class _DesktopTerminalViewState extends ConsumerState<DesktopTerminalView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(desktopTerminalProvider);
      if (DesktopTerminalView.isSupported && state.sessions.isEmpty) {
        ref.read(desktopTerminalProvider.notifier).createSession();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(desktopTerminalProvider);
    final scheme = Theme.of(context).colorScheme;
    if (!DesktopTerminalView.isSupported) {
      return Center(
        child: FilledButton.tonalIcon(
          onPressed: null,
          icon: const Icon(Icons.terminal_outlined),
          label: const UseText(I18nKey.bottomPanelAndroidTerminalUnsupported),
        ),
      );
    }

    final session = state.selectedSession;
    return Row(
      children: [
        Expanded(
          child: session == null
              ? Center(
                  child: FilledButton.icon(
                    onPressed: () => ref
                        .read(desktopTerminalProvider.notifier)
                        .createSession(),
                    icon: const Icon(Icons.add),
                    label: const UseText(I18nKey.bottomPanelNewTerminal),
                  ),
                )
              : TerminalView(
                  session.terminal,
                  controller: session.controller,
                  theme: buildTerminalTheme(context),
                  textStyle: buildTerminalStyle(
                    ref,
                    enableUnderline: ref.watch(desktopTerminalEnableUnderline),
                  ),
                  hardwareKeyboardOnly: true,
                  key: ValueKey(
                    'terminal_${session.id}_${scheme.surface.toARGB32()}',
                  ),
                ),
        ),
        Container(
          width: 150,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border(left: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Expanded(
                      child: UseText(I18nKey.bottomPanelTerminalTab),
                    ),
                    IconButton(
                      tooltip: translateForWidget(
                        ref,
                        I18nKey.bottomPanelNewTerminal,
                      ),
                      onPressed: () => ref
                          .read(desktopTerminalProvider.notifier)
                          .createSession(),
                      icon: const Icon(Icons.add, size: 18),
                    ),
                  ],
                ),
              ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    state.error!,
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                ),
              Expanded(
                child: ListView(
                  children: [
                    for (final item in state.sessions)
                      _TerminalSessionTile(
                        session: item,
                        selected: item.id == state.selectedSession?.id,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TerminalSessionTile extends ConsumerWidget {
  const _TerminalSessionTile({required this.session, required this.selected});

  final DesktopTerminalSession session;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: () => ref
            .read(desktopTerminalProvider.notifier)
            .selectSession(session.id),
        child: SizedBox(
          height: 34,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(
                Icons.terminal,
                size: 16,
                color: selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ),
              IconButton(
                tooltip: translateForWidget(
                  ref,
                  I18nKey.bottomPanelCloseTerminal,
                ),
                onPressed: () => ref
                    .read(desktopTerminalProvider.notifier)
                    .closeSession(session.id),
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TerminalTheme buildTerminalTheme(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final defaultTheme = TerminalThemes.defaultTheme;
  return TerminalTheme(
    cursor: defaultTheme.cursor,
    selection: defaultTheme.selection,
    foreground: scheme.onSurface,
    background: scheme.surface,
    black: defaultTheme.black,
    white: defaultTheme.white,
    red: defaultTheme.red,
    green: defaultTheme.green,
    yellow: defaultTheme.yellow,
    blue: defaultTheme.blue,
    magenta: defaultTheme.magenta,
    cyan: defaultTheme.cyan,
    brightBlack: defaultTheme.brightBlack,
    brightRed: defaultTheme.brightRed,
    brightGreen: defaultTheme.brightGreen,
    brightYellow: defaultTheme.brightYellow,
    brightBlue: defaultTheme.brightBlue,
    brightMagenta: defaultTheme.brightMagenta,
    brightCyan: defaultTheme.brightCyan,
    brightWhite: defaultTheme.brightWhite,
    searchHitBackground: defaultTheme.searchHitBackground,
    searchHitBackgroundCurrent: defaultTheme.searchHitBackgroundCurrent,
    searchHitForeground: defaultTheme.searchHitForeground,
  );
}

TerminalStyle buildTerminalStyle(WidgetRef ref, {bool enableUnderline = true}) {
  return TerminalStyle(
    fontSize: ref.watch(terminalFontSize),
    height: 1.0,
    fontFamily: editorTextFonts[ref.watch(terminalFontFamily)] ?? 'monospace',
    enableUnderline: enableUnderline,
  );
}

Widget buildTitleBar(Widget child) {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return Column(
      children: [
        UseTitleBar(),
        Expanded(child: child),
      ],
    );
  } else {
    return child;
  }
}

class FunctionPage extends StatelessWidget {
  const FunctionPage({super.key, required this.child, required this.state});

  final Widget child;
  final GoRouterState state;

  @override
  Widget build(BuildContext context) {
    if (ResponsiveBreakpoints.of(context).isDesktop) {
      nowViewSelectedIndex = desktopSelectedIndex;
      return buildTitleBar(DesktopView(state: state, child: child));
    } else if (ResponsiveBreakpoints.of(context).isTablet) {
      nowViewSelectedIndex = tabletSelectedIndex;
      return buildTitleBar(TabletView(state: state, child: child));
    } else {
      nowViewSelectedIndex = mobileSelectedIndex;
      return buildTitleBar(MobileView(state: state, child: child));
    }
  }
}

class EditorToolsBar extends ConsumerWidget {
  const EditorToolsBar({super.key, this.showNavigationDrawerButton = false});

  final bool showNavigationDrawerButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final registryItems = ref.watch(statusBarRegistryProvider);
    final runningOps = ref.watch(runningOperationsProvider);
    final scrollController = ScrollController();

    return Container(
      width: double.infinity,
      height: 40,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent && scrollController.hasClients) {
            final delta = event.scrollDelta.dy;
            final newOffset = (scrollController.offset + delta).clamp(
              0.0,
              scrollController.position.maxScrollExtent,
            );
            scrollController.jumpTo(newOffset);
          }
        },
        child: SingleChildScrollView(
          controller: scrollController,
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showNavigationDrawerButton) ...[
                const MobileNavigationDrawerButton(),
                const SizedBox(width: 4),
              ],
              buildLspState(context, ref),
              const SizedBox(width: 4),
              buildFileState(context, ref),
              const SizedBox(width: 4),
              if (!isMobile) ...[
                buildBoardConnectState(context, ref),
                const SizedBox(width: 4),
              ],
              buildGitState(context, ref),
              const SizedBox(width: 4),
              buildConsoleState(context, ref),
              const SizedBox(width: 4),
              if (ref.watch(fileTransferProgressProvider).isActive) ...[
                buildTransferState(context, ref),
                const SizedBox(width: 4),
              ],
              // Running operations from the registry
              for (final op in runningOps) ...[
                _buildRunningOperation(context, ref, op),
                const SizedBox(width: 4),
              ],
              // Externally registered items
              for (final entry in registryItems) ...[
                entry.builder(context),
                const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget buildFileState(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final value = ref.watch(tabbedViewControllerProvider).selectedTab?.value;
    if (value is! TabDataValue || value.type != "file") {
      return StatusBarButton(
        label: I18nKey.statusWelcomePage,
        icon: Icons.home_outlined,
        compact: isMobile,
        tooltip: translateForWidget(ref, I18nKey.statusNoCodeFile),
        onPressed: () {},
      );
    }

    final fileName = path.basename(value.filePath);
    final source = translateForWidget(
      ref,
      value.isBoardFile == true ? I18nKey.statusBoard : I18nKey.statusLocal,
    );
    final saved = value.isSaved;
    final savedLabel = translateForWidget(
      ref,
      saved ? I18nKey.statusSaved : I18nKey.statusUnsaved,
    );
    return StatusBarButton(
      label: isMobile ? savedLabel : "$source · $savedLabel · $fileName",
      icon: value.isBoardFile == true
          ? Icons.developer_board_outlined
          : Icons.description_outlined,
      statusColor: saved ? scheme.primary : scheme.tertiary,
      compact: isMobile,
      tooltip: translateForWidget(
        ref,
        saved ? I18nKey.statusSaveAgain : I18nKey.statusSaveCurrent,
      ),
      onPressed: () async {
        await ref.read(fileProvider.notifier).saveCurrentFile();
        if (!context.mounted) return;

        showIdeSuccess(
          context,
          translateForWidget(ref, I18nKey.statusSavedCurrentFile),
        );
      },
    );
  }

  Widget buildTransferState(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final transfer = ref.watch(fileTransferProgressProvider);
    final file = transfer.currentFile == null
        ? ''
        : path.basename(transfer.currentFile!);
    final index = transfer.totalFiles > 1
        ? ' ${transfer.currentIndex}/${transfer.totalFiles}'
        : '';
    final percent = transfer.progress == null
        ? ''
        : ' ${(transfer.progress! * 100).round()}%';
    final speed =
        transfer.bytesPerSecond != null && transfer.bytesPerSecond! > 0
        ? ' ${transfer.bytesPerSecond! >= 1024 ? '${(transfer.bytesPerSecond! / 1024).toStringAsFixed(1)}KB/s' : '${transfer.bytesPerSecond!.round()}B/s'}'
        : '';
    final dirKey = switch (transfer.direction) {
      FileTransferDirection.upload => I18nKey.editorToolbarUpload,
      FileTransferDirection.download => I18nKey.editorToolbarDownload,
      FileTransferDirection.move => I18nKey.commonMove,
      null => I18nKey.editorToolbarUpload,
    };
    final label =
        transfer.message ??
        '${translateForWidget(ref, dirKey)}$index · $file$percent$speed';
    final color = transfer.failed ? scheme.error : scheme.primary;

    return Tooltip(
      message: transfer.currentFile ?? label,
      child: SizedBox(
        width: 160,
        height: 32,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  transfer.direction == FileTransferDirection.download
                      ? Icons.file_download_outlined
                      : Icons.file_upload_outlined,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            LinearProgressIndicator(
              value: transfer.progress,
              minHeight: 2,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildLspState(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(lspState);
    final initialized = state?.valueOrNull == true;
    final isLoading = state?.isLoading == true;
    final hasError = state?.hasError == true;
    final label = initialized
        ? translateForWidget(ref, I18nKey.statusLspReady)
        : isLoading
        ? translateForWidget(ref, I18nKey.statusLspStarting)
        : hasError
        ? translateForWidget(ref, I18nKey.statusLspError)
        : translateForWidget(ref, I18nKey.statusLspNotReady);
    final color = initialized
        ? scheme.primary
        : isLoading
        ? scheme.tertiary
        : hasError
        ? scheme.error
        : scheme.outline;
    return StatusBarButton(
      label: label,
      icon: Icons.data_object,
      statusColor: color,
      tooltip: translateForWidget(ref, I18nKey.settingsLspPageTitle),
      onPressed: () => context.go("/settings/lsp"),
    );
  }

  Widget buildBoardConnectState(BuildContext context, WidgetRef ref) {
    final usb = ref.watch(serialProvider);
    final isConnected = usb.isConnected;
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final label = isMobile
        ? (isConnected
              ? usb.selectedPortName!
              : translateForWidget(ref, I18nKey.statusDeviceShort))
        : (isConnected
              ? translateForWidget(
                  ref,
                  I18nKey.statusDevicePort,
                ).replaceAll('{port}', usb.selectedPortName!)
              : translateForWidget(ref, I18nKey.statusDeviceDisconnected));
    return StatusBarButton(
      label: label,
      icon: Icons.usb,
      compact: isMobile,
      statusColor: isConnected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.outline,
      tooltip: translateForWidget(
        ref,
        isConnected
            ? I18nKey.statusOpenDeviceManager
            : I18nKey.statusConnectDevice,
      ),
      onPressed: () => context.go("/tools"),
    );
  }

  Widget buildGitState(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final summary = ref.watch(gitStatusSummaryProvider);
    if (summary == null) {
      return StatusBarButton(
        label: 'Git',
        icon: Icons.account_tree_outlined,
        compact: isMobile,
        statusColor: scheme.outline,
        tooltip: translateForWidget(ref, I18nKey.statusOpenSourceControl),
        onPressed: () => context.go('/git'),
      );
    }

    final label = isMobile
        ? summary.branchLabel
        : '${summary.branchLabel} · Git';
    return StatusBarButton(
      label: label,
      icon: Icons.account_tree_outlined,
      compact: isMobile,
      statusColor: scheme.primary,
      tooltip: translateForWidget(ref, I18nKey.statusOpenSourceControl),
      onPressed: () => context.go('/git'),
    );
  }

  Widget buildConsoleState(BuildContext context, WidgetRef ref) {
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final visible = ref.watch(consolePageShow);
    return StatusBarButton(
      label: isMobile
          ? "REPL"
          : (visible ? I18nKey.statusShowConsole : I18nKey.statusHideConsole),
      icon: Icons.terminal,
      compact: isMobile,
      tooltip: translateForWidget(
        ref,
        isMobile
            ? I18nKey.statusOpenConsole
            : (visible ? I18nKey.statusHideConsole : I18nKey.statusShowRepl),
      ),
      onPressed: () {
        if (isMobile) {
          showMobileConsoleSheet(context);
          return;
        }
        ref.read(consolePageShow.notifier).state = !visible;
      },
    );
  }

  Widget _buildRunningOperation(
    BuildContext context,
    WidgetRef ref,
    RunningOperation op,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final color = op.failed ? scheme.error : scheme.primary;
    return Container(
      height: 32,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (op.progress != null)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                value: op.progress,
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
          const SizedBox(width: 6),
          Text(
            op.label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (op.canInterrupt) ...[
            const SizedBox(width: 4),
            SizedBox(
              width: 24,
              height: 24,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 17,
                tooltip: translateForWidget(ref, I18nKey.statusInterrupt),
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: op.onInterrupt,
              ),
            ),
          ],
          if (op.canForceReset) ...[
            SizedBox(
              width: 24,
              height: 24,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 17,
                tooltip: translateForWidget(ref, I18nKey.statusForceReset),
                icon: const Icon(Icons.refresh),
                onPressed: op.onForceReset,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MobileNavigationDrawerButton extends ConsumerWidget {
  const MobileNavigationDrawerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: translateForWidget(ref, I18nKey.statusOpenMenu),
      style: IconButton.styleFrom(
        minimumSize: const Size(36, 32),
        fixedSize: const Size(36, 32),
        padding: EdgeInsets.zero,
      ),
      onPressed: () => Scaffold.of(context).openDrawer(),
      icon: const Icon(Icons.menu, size: 20),
    );
  }
}
