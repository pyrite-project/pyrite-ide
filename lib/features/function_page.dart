import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/constants/navigation_bar.dart';
import 'package:pyrite_ide/core/constants/theme_density.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';
import 'package:pyrite_ide/core/services/editor/desktop_terminal_provider.dart';
import 'package:pyrite_ide/core/services/editor/repl_input_controller.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/active_device_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/editor/lsp_state.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/git/git_status_summary_provider.dart';
import 'package:pyrite_ide/core/services/status_bar/running_operation_provider.dart';
import 'package:pyrite_ide/core/services/status_bar/status_bar_registry.dart';
import 'package:pyrite_ide/core/sdk/command_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/menu_resolver.dart';
import 'package:pyrite_ide/core/sdk/models/plugin_theme.dart';
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
    final isConnected = ref.watch(deviceConnectedProvider);
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
          if (!isConnected && !useWebRepl)
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
    final statusBarHeight = ThemeDensityTokens.forStyle(
      ref.watch(themeStyle),
    ).statusBarHeight;
    final compact = ref.watch(themeStyle) == ThemeStyle.compact;
    return Container(
      height: statusBarHeight,
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
                dimension: compact ? 26 : 30,
                child: IconButtonTheme(
                  data: IconButtonThemeData(
                    style: ButtonStyle(
                      iconSize: WidgetStatePropertyAll(compact ? 15 : 17),
                      padding: WidgetStatePropertyAll(EdgeInsets.zero),
                      minimumSize: WidgetStatePropertyAll(
                        Size.square(compact ? 26 : 30),
                      ),
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
    final compact = ref.watch(themeStyle) == ThemeStyle.compact;
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
              size: compact ? 14 : 16,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            SizedBox(width: compact ? 4 : 6),
            UseText(
              label,
              style: TextStyle(
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                fontSize: compact ? 12 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConsoleWorkspace extends ConsumerStatefulWidget {
  const ConsoleWorkspace({
    super.key,
    required this.primary,
    this.allowConsole = true,
    this.collapsedPrimarySize = 0,
    this.console,
  });

  static const primaryPaneKey = ValueKey<String>('workspace-primary-pane');
  static const consolePaneKey = ValueKey<String>('workspace-console-pane');
  static const draggerKey = ValueKey<String>('workspace-console-dragger');

  final Widget primary;
  final bool allowConsole;
  final double collapsedPrimarySize;
  final Widget? console;

  @override
  ConsumerState<ConsoleWorkspace> createState() => _ConsoleWorkspaceState();
}

class _ConsoleWorkspaceState extends ConsumerState<ConsoleWorkspace> {
  static const _primaryFlex = 3.0;
  static const _consoleFlex = 1.0;

  late final shadcn.FlexibleResizablePaneController _primaryController;
  late final shadcn.FlexibleResizablePaneController _consoleController;

  @override
  void initState() {
    super.initState();
    _primaryController = shadcn.FlexibleResizablePaneController(_primaryFlex);
    _consoleController = shadcn.FlexibleResizablePaneController(_consoleFlex);
    ref.listenManual<bool>(consolePageShow, (_, _) => _resetPaneSizes());
  }

  @override
  void didUpdateWidget(covariant ConsoleWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.allowConsole != oldWidget.allowConsole) {
      _resetPaneSizes();
    }
  }

  void _resetPaneSizes() {
    _primaryController
      ..flex = _primaryFlex
      ..expand();
    _consoleController
      ..flex = _consoleFlex
      ..expand();
  }

  @override
  void dispose() {
    _primaryController.dispose();
    _consoleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showConsole = widget.allowConsole && ref.watch(consolePageShow);
    return shadcn.ResizablePanel.vertical(
      optionalDivider: false,
      draggerBuilder: (context) {
        return Semantics(
          label: translateForWidget(ref, I18nKey.bottomPanelResize),
          child: const shadcn.HorizontalResizableDragger(
            key: ConsoleWorkspace.draggerKey,
          ),
        );
      },
      children: [
        shadcn.ResizablePane.controlled(
          key: ConsoleWorkspace.primaryPaneKey,
          controller: _primaryController,
          minSize: 240,
          collapsedSize: showConsole ? widget.collapsedPrimarySize : null,
          child: widget.primary,
        ),
        if (showConsole)
          shadcn.ResizablePane.controlled(
            key: ConsoleWorkspace.consolePaneKey,
            controller: _consoleController,
            minSize: 160,
            child: widget.console ?? consolePage(),
          ),
      ],
    );
  }
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
  double collapsedPrimarySize = 0,
}) {
  return buildShadcnLayer(
    context,
    ConsoleWorkspace(
      primary: child,
      allowConsole: allowConsole,
      collapsedPrimarySize: collapsedPrimarySize,
    ),
  );
}

void showMobileConsoleSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final mediaQuery = MediaQuery.of(context);
      return Padding(
        padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
        child: SizedBox(
          height: mediaQuery.size.height * 0.55,
          child: consolePage(),
        ),
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
    this.pluginVersion,
  });

  final String pluginId;
  final PluginNavigationContainerContribution container;
  final String? viewId;
  final PluginIconSet? pluginIcons;
  final String? pluginVersion;

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
        pluginVersion: plugins[entry.pluginId]?.version,
      ),
  ];
}

Widget _pluginNavigationIcon(WidgetRef ref, _PluginNavigationItem item) {
  final icon = _pluginNavigationIconCore(item, iconSize: _navIconSize(ref));
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

Widget _pluginNavigationIconCore(
  _PluginNavigationItem item, {
  double iconSize = 24,
}) {
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
    revision: item.pluginVersion,
    width: iconSize,
    height: iconSize,
    monochrome: true,
    fallback: const Icon(Icons.extension_outlined),
  );
}

double _navIconSize(WidgetRef ref) {
  return ThemeDensityTokens.forStyle(ref.watch(themeStyle)).navIconSize;
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

String? _destinationTooltip(WidgetRef ref, Widget label) {
  if (label is UseText) return resolveI18nText(ref, label.data);
  if (label is Text) return label.data;
  return null;
}

Widget _selectedRailIcon(BuildContext context, Widget icon) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: icon,
  );
}

NavigationRailDestination _tooltippedDestination(
  BuildContext context,
  WidgetRef ref,
  NavigationRailDestination destination,
) {
  final tooltip = _destinationTooltip(ref, destination.label);
  if (tooltip == null) return destination;
  return NavigationRailDestination(
    icon: Tooltip(message: tooltip, child: destination.icon),
    selectedIcon: Tooltip(
      message: tooltip,
      child: _selectedRailIcon(context, destination.selectedIcon),
    ),
    label: destination.label,
    padding: destination.padding ?? const EdgeInsets.symmetric(vertical: 3),
    indicatorColor: destination.indicatorColor,
    indicatorShape: destination.indicatorShape,
    disabled: destination.disabled,
  );
}

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
                  Expanded(
                    child: buildVerticalWorkspace(
                      context,
                      ref,
                      child,
                      collapsedPrimarySize:
                          state.matchedLocation.startsWith('/editor')
                          ? ThemeDensityTokens.forStyle(
                              ref.watch(themeStyle),
                            ).toolbarHeight
                          : 0,
                    ),
                  ),
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
      for (final destination in [
        ...tabletRailItems,
        ...pluginNavigationRailDestinations(ref),
      ])
        _tooltippedDestination(context, ref, destination),
    ];
    final navigationRoutes = _navigationRoutes(pluginItems, builtInCount: 6);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(
                  context,
                ).colorScheme.copyWith(primary: Colors.transparent),
                splashFactory: NoSplash.splashFactory,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
              child: NavigationRail(
                backgroundColor: Theme.of(context).colorScheme.surface,
                labelType: NavigationRailLabelType.none,
                minWidth: ThemeDensityTokens.forStyle(
                  ref.watch(themeStyle),
                ).navRailWidth,
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
      for (final destination in [
        ...desktopRailItems,
        ...pluginNavigationRailDestinations(ref),
      ])
        _tooltippedDestination(context, ref, destination),
    ];
    final navigationRoutes = _navigationRoutes(pluginItems, builtInCount: 5);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(
                  context,
                ).colorScheme.copyWith(primary: Colors.transparent),
                splashFactory: NoSplash.splashFactory,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
              child: NavigationRail(
                backgroundColor: Theme.of(context).colorScheme.surface,
                labelType: NavigationRailLabelType.none,
                minWidth: ThemeDensityTokens.forStyle(
                  ref.watch(themeStyle),
                ).navRailWidth,
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
      ),
    );
  }

  List<shadcn.ResizablePane> _pageStructure(
    BuildContext context,
    WidgetRef ref,
  ) {
    final List<shadcn.ResizablePane> children = [];
    final isEditorRoute = state.matchedLocation.startsWith('/editor');
    final showFunctionPanel = ref.watch(functionPageShow) && !isEditorRoute;
    final showExpansionPanel = ref.watch(expansionPageShow);
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
        child: ConsoleWorkspace(
          primary: const Editor(),
          collapsedPrimarySize: ThemeDensityTokens.forStyle(
            ref.watch(themeStyle),
          ).toolbarHeight,
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
    final terminalTheme = buildTerminalTheme(context, ref);
    final terminalStyle = buildTerminalStyle(ref);
    return ReplSurface(
      backgroundColor: terminalTheme.background,
      foregroundColor: terminalTheme.foreground,
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
      theme: buildTerminalTheme(context, ref),
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
  TerminalTheme? _terminalTheme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(desktopTerminalProvider);
      if (DesktopTerminalView.isSupported && state.sessions.isEmpty) {
        ref
            .read(desktopTerminalProvider.notifier)
            .createSession(
              configureTerminal: (terminal, backgroundColor) {
                final theme = _terminalTheme;
                if (theme != null) {
                  configureTerminalColorQueries(
                    terminal,
                    theme,
                    backgroundColor: backgroundColor,
                  );
                }
              },
              defaultDir: ref.read(fileProvider),
            );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(desktopTerminalProvider);
    final scheme = Theme.of(context).colorScheme;
    final terminalTheme = buildTerminalTheme(context, ref);
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
                        .createSession(
                          configureTerminal: (terminal, backgroundColor) =>
                              configureTerminalColorQueries(
                                terminal,
                                terminalTheme,
                                backgroundColor: backgroundColor,
                              ),
                          defaultDir: ref.read(fileProvider),
                        ),
                    icon: const Icon(Icons.add),
                    label: const UseText(I18nKey.bottomPanelNewTerminal),
                  ),
                )
              : ValueListenableBuilder<Color?>(
                  valueListenable: session.backgroundColor,
                  builder: (context, programBackground, _) {
                    final effectiveTheme = programBackground != null
                        ? terminalThemeWithBackground(
                            terminalTheme,
                            programBackground,
                          )
                        : terminalTheme;
                    return TerminalView(
                      configureTerminalColorQueries(
                        session.terminal,
                        terminalTheme,
                        backgroundColor: session.backgroundColor,
                      ),
                      controller: session.controller,
                      theme: effectiveTheme,
                      textStyle: buildTerminalStyle(ref),
                      hardwareKeyboardOnly: true,
                      // Keep the renderer alive when a theme contribution is
                      // installed or selected. TerminalView updates its theme
                      // in place; replacing it would discard focus/scroll UI.
                      key: ValueKey('terminal_${session.id}'),
                    );
                  },
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
                          .createSession(
                            configureTerminal: (terminal, backgroundColor) =>
                                configureTerminalColorQueries(
                                  terminal,
                                  terminalTheme,
                                  backgroundColor: backgroundColor,
                                ),
                            defaultDir: ref.read(fileProvider),
                          ),
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

TerminalTheme buildTerminalTheme(BuildContext context, WidgetRef ref) {
  final scheme = Theme.of(context).colorScheme;
  final appearance = ref.watch(terminalAppearance);
  final minimumContrastRatio = ref.watch(terminalMinimumContrast) ? 4.5 : 1.0;
  late final TerminalTheme baseTheme;
  if (appearance == TerminalAppearance.custom) {
    final palette = ref.watch(terminalCustomPalette);
    baseTheme = _terminalThemeFromPalette(
      foreground: Color(ref.watch(terminalCustomForeground)),
      background: Color(ref.watch(terminalCustomBackground)),
      palette: palette.length == 16
          ? palette.map(Color.new).toList()
          : kDefaultTerminalCustomPalette.map(Color.new).toList(),
      minimumContrastRatio: minimumContrastRatio,
    );
  } else if (appearance == TerminalAppearance.light ||
      appearance == TerminalAppearance.followIde &&
          Theme.of(context).brightness == Brightness.light) {
    baseTheme = _terminalThemeFromPalette(
      foreground: appearance == TerminalAppearance.followIde
          ? scheme.onSurface
          : const Color(0xFF1F2328),
      background: appearance == TerminalAppearance.followIde
          ? scheme.surface
          : const Color(0xFFFFFFFF),
      palette: _lightTerminalPalette,
      minimumContrastRatio: minimumContrastRatio,
    );
  } else {
    final defaultTheme = TerminalThemes.defaultTheme;
    baseTheme = _terminalThemeFromPalette(
      foreground: appearance == TerminalAppearance.followIde
          ? scheme.onSurface
          : const Color(0xFFFFFFFF),
      background: appearance == TerminalAppearance.followIde
          ? scheme.surface
          : defaultTheme.background,
      palette: _paletteFromTheme(defaultTheme),
      minimumContrastRatio: minimumContrastRatio,
    );
  }

  final activeThemeId = ref.watch(activePluginThemeId);
  final registry = ref.watch(dataRegistryProvider);
  final pluginTheme = activeThemeId == null
      ? null
      : registry.getThemeById(activeThemeId);
  return _applyPluginTerminalTheme(baseTheme, pluginTheme);
}

TerminalTheme _applyPluginTerminalTheme(
  TerminalTheme base,
  PluginThemeData? pluginTheme,
) {
  if (pluginTheme == null ||
      pluginTheme.terminalForeground == null &&
          pluginTheme.terminalBackground == null &&
          pluginTheme.terminalAnsi == null) {
    return base;
  }
  return _terminalThemeFromPalette(
    foreground: pluginTheme.terminalForeground ?? base.foreground,
    background: pluginTheme.terminalBackground ?? base.background,
    palette: pluginTheme.terminalAnsi ?? _paletteFromTheme(base),
    minimumContrastRatio: base.minimumContrastRatio,
  );
}

const _lightTerminalPalette = <Color>[
  Color(0xFF000000),
  Color(0xFFCD3131),
  Color(0xFF008000),
  Color(0xFF795E00),
  Color(0xFF0451A5),
  Color(0xFFAF00DB),
  Color(0xFF00838F),
  Color(0xFF666666),
  Color(0xFF767676),
  Color(0xFFE51400),
  Color(0xFF16C60C),
  Color(0xFFB89500),
  Color(0xFF0066BF),
  Color(0xFFBC05BC),
  Color(0xFF0598BC),
  Color(0xFF333333),
];

List<Color> _paletteFromTheme(TerminalTheme theme) => [
  theme.black,
  theme.red,
  theme.green,
  theme.yellow,
  theme.blue,
  theme.magenta,
  theme.cyan,
  theme.white,
  theme.brightBlack,
  theme.brightRed,
  theme.brightGreen,
  theme.brightYellow,
  theme.brightBlue,
  theme.brightMagenta,
  theme.brightCyan,
  theme.brightWhite,
];

TerminalTheme _terminalThemeFromPalette({
  required Color foreground,
  required Color background,
  required List<Color> palette,
  required double minimumContrastRatio,
}) {
  return TerminalTheme(
    cursor: foreground.withValues(alpha: 0.8),
    selection: foreground.withValues(alpha: 0.3),
    foreground: foreground,
    background: background,
    black: palette[0],
    red: palette[1],
    green: palette[2],
    yellow: palette[3],
    blue: palette[4],
    magenta: palette[5],
    cyan: palette[6],
    white: palette[7],
    brightBlack: palette[8],
    brightRed: palette[9],
    brightGreen: palette[10],
    brightYellow: palette[11],
    brightBlue: palette[12],
    brightMagenta: palette[13],
    brightCyan: palette[14],
    brightWhite: palette[15],
    searchHitBackground: const Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: const Color(0xFF31FF26),
    searchHitForeground: const Color(0xFF000000),
    minimumContrastRatio: minimumContrastRatio,
  );
}

Terminal configureTerminalColorQueries(
  Terminal terminal,
  TerminalTheme theme, {
  ValueNotifier<Color?>? backgroundColor,
}) {
  terminal.onPrivateOSC = (code, args) {
    final value = args.firstOrNull;
    if ((code == '10' || code == '11') && value == '?') {
      final color = code == '10'
          ? theme.foreground
          : backgroundColor?.value != null
          ? backgroundColor!.value!
          : theme.background;
      terminal.textInput('\x1b]$code;${_oscRgb(color)}\x1b\\');
      return;
    }
    if (code == '11' && value != null && backgroundColor != null) {
      final parsed = parseTerminalOscColor(value);
      if (parsed != null) backgroundColor.value = parsed;
      return;
    }
    if (code == '111' && backgroundColor != null) {
      backgroundColor.value = null;
    }
  };
  return terminal;
}

Color? parseTerminalOscColor(String value) {
  List<String> components;
  if (value.startsWith('rgb:')) {
    components = value.substring(4).split('/');
  } else if (value.startsWith('#')) {
    final hex = value.substring(1);
    if (hex.length % 3 != 0) return null;
    final width = hex.length ~/ 3;
    if (width < 1 || width > 4) return null;
    components = [
      hex.substring(0, width),
      hex.substring(width, width * 2),
      hex.substring(width * 2),
    ];
  } else {
    return null;
  }

  if (components.length != 3) return null;
  final bytes = <int>[];
  for (final component in components) {
    if (component.isEmpty || component.length > 4) return null;
    final parsed = int.tryParse(component, radix: 16);
    if (parsed == null) return null;
    final maximum = (1 << (component.length * 4)) - 1;
    bytes.add((parsed * 255 / maximum).round());
  }
  return Color.fromARGB(0xff, bytes[0], bytes[1], bytes[2]);
}

TerminalTheme terminalThemeWithBackground(
  TerminalTheme theme,
  Color background,
) {
  return TerminalTheme(
    cursor: theme.cursor,
    selection: theme.selection,
    foreground: theme.foreground,
    background: background,
    black: theme.black,
    red: theme.red,
    green: theme.green,
    yellow: theme.yellow,
    blue: theme.blue,
    magenta: theme.magenta,
    cyan: theme.cyan,
    white: theme.white,
    brightBlack: theme.brightBlack,
    brightRed: theme.brightRed,
    brightGreen: theme.brightGreen,
    brightYellow: theme.brightYellow,
    brightBlue: theme.brightBlue,
    brightMagenta: theme.brightMagenta,
    brightCyan: theme.brightCyan,
    brightWhite: theme.brightWhite,
    searchHitBackground: theme.searchHitBackground,
    searchHitBackgroundCurrent: theme.searchHitBackgroundCurrent,
    searchHitForeground: theme.searchHitForeground,
    minimumContrastRatio: theme.minimumContrastRatio,
  );
}

String _oscRgb(Color color) {
  String expand(double component) {
    final byte = (component * 255).round().clamp(0, 255);
    final hex = byte.toRadixString(16).padLeft(2, '0');
    return '$hex$hex';
  }

  return 'rgb:${expand(color.r)}/${expand(color.g)}/${expand(color.b)}';
}

TerminalStyle buildTerminalStyle(WidgetRef ref) {
  return TerminalStyle(
    fontSize: ref.watch(terminalFontSize),
    height: ref.watch(terminalLineHeight),
    fontFamily: editorTextFonts[ref.watch(terminalFontFamily)] ?? 'monospace',
    enableLigatures: ref.watch(terminalLigatures),
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
      height: ThemeDensityTokens.forStyle(
        ref.watch(themeStyle),
      ).statusBarHeight,
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
    final value = ref.watch(tabbedViewControllerProvider).selectedTab?.value;
    if (value is! TabDataValue || value.type != "file") {
      return StatusBarButton(
        label: I18nKey.statusWelcomePage,
        icon: Icons.home_outlined,
        compact: ref.watch(themeStyle) == ThemeStyle.compact,
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
      label: "$source · $savedLabel · $fileName",
      icon: value.isBoardFile == true
          ? Icons.developer_board_outlined
          : Icons.description_outlined,
      statusColor: saved ? scheme.primary : scheme.tertiary,
      compact: ref.watch(themeStyle) == ThemeStyle.compact,
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
    final compact = ref.watch(themeStyle) == ThemeStyle.compact;

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
                  size: compact ? 14 : 16,
                  color: color,
                ),
                SizedBox(width: compact ? 4 : 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: compact ? 12 : null,
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
      compact: ref.watch(themeStyle) == ThemeStyle.compact,
      tooltip: translateForWidget(ref, I18nKey.settingsLspPageTitle),
      onPressed: () => context.go("/settings/lsp"),
    );
  }

  Widget buildBoardConnectState(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(deviceConnectedProvider);
    final deviceLabel = ref.watch(activeDeviceLabelProvider);
    final label = isConnected
        ? (deviceLabel ?? translateForWidget(ref, I18nKey.statusDeviceShort))
        : translateForWidget(ref, I18nKey.statusDeviceDisconnected);
    return StatusBarButton(
      label: label,
      icon: Icons.usb,
      compact: ref.watch(themeStyle) == ThemeStyle.compact,
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
        compact: ref.watch(themeStyle) == ThemeStyle.compact,
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
      compact: ref.watch(themeStyle) == ThemeStyle.compact,
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
      compact: ref.watch(themeStyle) == ThemeStyle.compact,
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
    final compact = ref.watch(themeStyle) == ThemeStyle.compact;
    final spinnerSize = compact ? 14.0 : 16.0;
    final iconButtonSize = compact ? 20.0 : 24.0;
    return Container(
      height: 32,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (op.progress != null)
            SizedBox(
              width: spinnerSize,
              height: spinnerSize,
              child: CircularProgressIndicator(
                value: op.progress,
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            SizedBox(
              width: spinnerSize,
              height: spinnerSize,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
          SizedBox(width: compact ? 4 : 6),
          Text(
            op.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: compact ? 12 : null,
            ),
          ),
          if (op.canInterrupt) ...[
            SizedBox(width: compact ? 2 : 4),
            SizedBox(
              width: iconButtonSize,
              height: iconButtonSize,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: compact ? 15 : 17,
                tooltip: translateForWidget(ref, I18nKey.statusInterrupt),
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: op.onInterrupt,
              ),
            ),
          ],
          if (op.canForceReset) ...[
            SizedBox(
              width: iconButtonSize,
              height: iconButtonSize,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: compact ? 15 : 17,
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
