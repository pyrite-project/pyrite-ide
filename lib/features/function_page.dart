import 'dart:async';
import 'dart:io';

import 'package:code_forge/code_forge.dart' show CodeForgeController;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/constants/corner_radius.dart';
import 'package:pyrite_ide/core/constants/navigation_bar.dart';
import 'package:pyrite_ide/core/constants/selection.dart';
import 'package:pyrite_ide/core/constants/theme_density.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';
import 'package:pyrite_ide/core/sdk/command_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/editor_document_host.dart';
import 'package:pyrite_ide/core/sdk/environment_notifier_provider.dart';
import 'package:pyrite_ide/core/sdk/menu_resolver.dart';
import 'package:pyrite_ide/core/sdk/models/plugin_theme.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_resources.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/editor/desktop_terminal_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_layout_commands.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/lsp_state.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/git/git_status_summary_provider.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/serial/active_device_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';
import 'package:pyrite_ide/core/services/status_bar/running_operation_provider.dart';
import 'package:pyrite_ide/core/services/status_bar/status_bar_registry.dart';
import 'package:pyrite_ide/core/services/workspace_pane.dart';
import 'package:pyrite_ide/features/command_palette/command_palette.dart';
import 'package:pyrite_ide/features/command_palette/editor_palette_hooks.dart';
import 'package:pyrite_ide/features/command_palette/palette_entry.dart';
import 'package:pyrite_ide/features/edit_core/lsp_location_dialog.dart';
import 'package:pyrite_ide/features/function_page/console_tabs.dart';
import 'package:pyrite_ide/features/function_page/editor_split_drop.dart';
import 'package:pyrite_ide/features/function_page/repl_surface.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_icons.dart';
import 'package:pyrite_ide/features/terminal/desktop_terminal_surface.dart';
import 'package:pyrite_ide/features/terminal/terminal_context_menu.dart';
import 'package:pyrite_ide/features/terminal/terminal_link_handlers.dart';
import 'package:pyrite_ide/features/window.dart';
import 'package:pyrite_ide/pages/editor/editor_page.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/pyrite_menu.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:pyrite_ide/shared/tabbed_view/tab_strip_theme.dart';
import 'package:pyrite_ide/shared/tabbed_view/tabbed_view.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;
import 'package:xterm/xterm.dart';

part 'function_page/function_page_views.dart';

/// Keeps the status bar's horizontal scroll position across rebuilds.
///
/// The bar rebuilds on every language-server/device/transfer change. Creating
/// a fresh [ScrollController] in `build` reset the offset each time, so a user
/// who scrolled to a status item lost their place whenever any other item
/// changed.
final AutoDisposeProvider<ScrollController> statusBarScrollControllerProvider =
    Provider.autoDispose<ScrollController>((ref) {
      final controller = ScrollController();
      ref.onDispose(controller.dispose);
      return controller;
    });

Widget consolePage() {
  return const ConsolePage();
}

/// The console panel.
///
/// It renders the same [TabbedView] as the editor and owns the same kind of
/// controller, which is what lets a tab be dragged from here into an editor
/// group and back: the shared drag already moves tabs across controllers.
/// Each surface brings its own buttons and menu, which the strip shows.
class ConsolePage extends ConsumerWidget {
  const ConsolePage({super.key});

  /// Only the panel's own surfaces may be dropped on its strip. A document
  /// would sit outside the editor layout, where persistence, the unsaved guard
  /// and the open-file dedup cannot see it.
  static bool _acceptsTab(DraggableData source, TabbedViewController _) =>
      isConsoleTab(source.tabData);

  /// Marks the console the pane the user is working in.
  static void _markFocused(WidgetRef ref) {
    ref.read(focusedWorkspacePaneProvider.notifier).state =
        WorkspacePane.console;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A click -- or keyboard focus arriving inside the panel -- marks the
    // console the focused pane, so a plugin view opened without an explicit
    // pane lands where the user is looking.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) _markFocused(ref);
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _markFocused(ref),
        child: TabbedViewTheme(
          data: buildTabStripTheme(context),
          child: TabbedView(
            controller: ref.watch(consoleTabbedViewControllerProvider),
            canDrop: _acceptsTab,
          ),
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

  /// Lowered from 240 so the terminal can grow taller before it gets snapped
  /// to fullscreen; the built-in collapse dead-drag also shrinks with it.
  static const double _primaryMinSize = 120;

  late final shadcn.FlexibleResizablePaneController _primaryController;
  late final shadcn.FlexibleResizablePaneController _consoleController;

  /// Whether the console held at least one tab on the previous notification.
  ///
  /// A console whose tabs have all been dragged out is not a group any more, so
  /// the pane goes away -- and the panel comes back at its default ratio when a
  /// tab is dragged back in.
  bool _consoleWasEmpty = false;

  /// The console controller, followed for its tabs: they change in place, so
  /// the provider never reports a group emptying.
  late final TabbedViewController _console;

  @override
  void initState() {
    super.initState();
    _primaryController = shadcn.FlexibleResizablePaneController(_primaryFlex);
    _consoleController = shadcn.FlexibleResizablePaneController(_consoleFlex);
    _console = ref.read(consoleTabbedViewControllerProvider)
      ..addListener(_onConsoleTabsChanged);
    _consoleWasEmpty = _console.tabs.isEmpty;
    ref.listenManual<bool>(consolePageShow, (_, _) => _resetPaneSizes());
    ref.listenManual<PaneEdge>(
      consoleDockSideProvider,
      (_, _) => _resetPaneSizes(),
    );
  }

  void _onConsoleTabsChanged() {
    if (!mounted) return;
    final empty = _console.tabs.isEmpty;
    if (empty == _consoleWasEmpty) return;
    _consoleWasEmpty = empty;
    // Reset before the rebuild that drops the pane: the panel keeps the ratio
    // it resolved while both panes existed otherwise.
    _resetPaneSizes();
    setState(() {});
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
    _console.removeListener(_onConsoleTabsChanged);
    _primaryController.dispose();
    _consoleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The console is a group like any other, so it only occupies a pane while
    // it still holds tabs: drag them all out and the group — and its pane —
    // goes away.
    final showConsole =
        widget.allowConsole && ref.watch(consolePageShow) && !_consoleWasEmpty;
    final dockSide = ref.watch(consoleDockSideProvider);
    final splitsVertically = dockSide.axis == Axis.vertical;

    final primaryPane = shadcn.ResizablePane.controlled(
      key: ConsoleWorkspace.primaryPaneKey,
      controller: _primaryController,
      minSize: _primaryMinSize,
      collapsedSize: showConsole ? widget.collapsedPrimarySize : null,
      child: widget.primary,
    );
    final consolePane = shadcn.ResizablePane.controlled(
      key: ConsoleWorkspace.consolePaneKey,
      controller: _consoleController,
      minSize: 160,
      child:
          widget.console ??
          EditorSplitDropRegion(
            // The panel is a group too, so its edges accept a tab like any
            // other group's: the new group lands in the editor area.
            controller: _console,
            edgeTarget: ref.read(tabbedViewControllerProvider),
            // Only the panel's own surfaces come back here. A document dropped
            // into this group would sit outside the layout tree, where
            // persistence, the unsaved guard and the open-file dedup cannot
            // see it at all.
            accept: (tab) => tab.value is ConsoleTabValue,
            child: consolePage(),
          ),
    );

    return shadcn.ResizablePanel(
      direction: dockSide.axis,
      optionalDivider: false,
      draggerBuilder: (context) {
        return Semantics(
          label: translateForWidget(ref, I18nKey.bottomPanelResize),
          child: splitsVertically
              ? const shadcn.HorizontalResizableDragger(
                  key: ConsoleWorkspace.draggerKey,
                )
              : const shadcn.VerticalResizableDragger(
                  key: ConsoleWorkspace.draggerKey,
                ),
        );
      },
      children: [
        if (dockSide.isLeading && showConsole) consolePane,
        primaryPane,
        if (!dockSide.isLeading && showConsole) consolePane,
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
    return TooltipAnchor(
      message: translateForWidget(
        ref,
        isMobile
            ? I18nKey.statusOpenConsole
            : (consoleVisible
                  ? I18nKey.statusHideConsole
                  : I18nKey.statusShowRepl),
      ),
      child: IconButton(
        onPressed: () {
          if (isMobile) {
            showMobileConsoleSheet(context);
            return;
          }
          ref.read(consolePageShow.notifier).state = !consoleVisible;
        },
        icon: const Icon(Icons.terminal),
      ),
    );
  }
}

class FunctionPaneToggle extends ConsumerWidget {
  const FunctionPaneToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(functionPageShow);
    return TooltipAnchor(
      message: translateForWidget(
        ref,
        visible
            ? I18nKey.bottomPanelHideFunctionPanel
            : I18nKey.bottomPanelShowFunctionPanel,
      ),
      child: IconButton(
        onPressed: () {
          ref.read(functionPageShow.notifier).state = !visible;
        },
        icon: Icon(
          visible ? Icons.keyboard_arrow_left : Icons.keyboard_arrow_right,
        ),
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
            children: [FunctionPaneToggle(), ConsoleToggle()],
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
  final selected = await showPyriteMenu<String>(
    context,
    globalPosition: globalPosition,
    entries: [
      for (final item in items)
        PyriteMenuEntry(
          value: item.commandId,
          label: item.title,
          enabled: item.enabled,
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
      borderRadius: context.innerCorners,
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
    // `container: true` keeps each rail destination its own semantics node so
    // adjacent destinations cannot absorb one another's tooltip anchor and
    // orphan its overlay node. See flutter/flutter#182444.
    icon: TooltipAnchor(
      message: tooltip,
      child: Semantics(container: true, child: destination.icon),
    ),
    selectedIcon: TooltipAnchor(
      message: tooltip,
      child: Semantics(
        container: true,
        child: _selectedRailIcon(context, destination.selectedIcon),
      ),
    ),
    label: destination.label,
    padding: destination.padding ?? const EdgeInsets.symmetric(vertical: 3),
    indicatorColor: destination.indicatorColor,
    indicatorShape: destination.indicatorShape,
    disabled: destination.disabled,
  );
}

class FunctionPage extends StatelessWidget {
  const FunctionPage({super.key, required this.child, required this.state});

  final Widget child;
  final GoRouterState state;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (ResponsiveBreakpoints.of(context).isDesktop) {
      nowViewSelectedIndex = desktopSelectedIndex;
      body = buildTitleBar(DesktopView(state: state, child: child));
    } else if (ResponsiveBreakpoints.of(context).isTablet) {
      nowViewSelectedIndex = tabletSelectedIndex;
      body = buildTitleBar(TabletView(state: state, child: child));
    } else {
      nowViewSelectedIndex = mobileSelectedIndex;
      body = buildTitleBar(MobileView(state: state, child: child));
    }
    return _WorkspaceShortcuts(child: body);
  }
}

/// Workspace-level keyboard entry points.
///
/// These live above the route so they work from the file tree, the editor, the
/// search page and every plugin surface. `CallbackShortcuts` still lets a
/// focused text field or terminal consume a key it handles first, so typing
/// `Ctrl+P` into a terminal remains the terminal's choice.
class _WorkspaceShortcuts extends ConsumerWidget {
  const _WorkspaceShortcuts({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void openPalette(PaletteLaunchMode mode) {
      unawaited(
        showCommandPalette(context, mode: mode, hooks: editorPaletteHooks()),
      );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // Commands: Cmd/Ctrl+Shift+P.
        const SingleActivator(
          LogicalKeyboardKey.keyP,
          meta: true,
          shift: true,
        ): () =>
            openPalette(PaletteLaunchMode.commands),
        const SingleActivator(
          LogicalKeyboardKey.keyP,
          control: true,
          shift: true,
        ): () =>
            openPalette(PaletteLaunchMode.commands),
        // Quick open: Cmd/Ctrl+P.
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true): () =>
            openPalette(PaletteLaunchMode.files),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            openPalette(PaletteLaunchMode.files),
        // Reopen the last closed tab.
        const SingleActivator(
          LogicalKeyboardKey.keyT,
          meta: true,
          shift: true,
        ): () =>
            unawaited(reopenClosedEditorTab(context, ref)),
        const SingleActivator(
          LogicalKeyboardKey.keyT,
          control: true,
          shift: true,
        ): () =>
            unawaited(reopenClosedEditorTab(context, ref)),
        // Split the editor group right / down.
        const SingleActivator(LogicalKeyboardKey.backslash, meta: true): () =>
            splitActiveEditor(ref, PaneEdge.right),
        const SingleActivator(
          LogicalKeyboardKey.backslash,
          control: true,
        ): () =>
            splitActiveEditor(ref, PaneEdge.right),
        const SingleActivator(
          LogicalKeyboardKey.backslash,
          meta: true,
          shift: true,
        ): () =>
            splitActiveEditor(ref, PaneEdge.bottom),
        const SingleActivator(
          LogicalKeyboardKey.backslash,
          control: true,
          shift: true,
        ): () =>
            splitActiveEditor(ref, PaneEdge.bottom),
        // Close the active editor group.
        const SingleActivator(
          LogicalKeyboardKey.keyW,
          meta: true,
          alt: true,
        ): () =>
            unawaited(closeActiveEditorGroup(context, ref)),
        const SingleActivator(
          LogicalKeyboardKey.keyW,
          control: true,
          alt: true,
        ): () =>
            unawaited(closeActiveEditorGroup(context, ref)),
      },
      child: child,
    );
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
    final scrollController = ref.watch(statusBarScrollControllerProvider);

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
              // The palette has to be reachable without a keyboard: touch
              // devices have no Cmd/Ctrl+P, and a terminal that consumes the
              // shortcut would otherwise leave no way in.
              StatusBarButton(
                label: I18nKey.paletteOpen,
                icon: Icons.keyboard_command_key,
                compact: ref.watch(themeStyle) == ThemeStyle.compact,
                tooltip:
                    '${translateForWidget(ref, I18nKey.paletteOpen)} '
                    '(${commandPaletteShortcutLabel()})',
                onPressed: () =>
                    showCommandPalette(context, hooks: editorPaletteHooks()),
              ),
              const SizedBox(width: 4),
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
              buildEditorState(context, ref),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildFileState(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // The focused group's tab, so the status bar describes the editor the
    // toolbar and the language server readout describe too.
    final value = ref.watch(activeEditorTabProvider).value;
    if (value == null || value.type != "file") {
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

    return TooltipAnchor(
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

  /// Caret position, selection size and the LSP error/warning counts for the
  /// selected file tab.
  ///
  /// Renders nothing when the active tab has no editor (welcome page, git diff
  /// tab, plugin view) so the status bar does not show a stale position from
  /// whatever file was open before.
  ///
  /// Subscribes to [CodeForgeController.displayChanges] only. That signal is
  /// frame-safe by construction, which matters here because this widget sits
  /// outside the editor's subtree while the editor notifies from inside its own
  /// `initState` and build. Subscribing to the controller itself, or to its
  /// `diagnosticsNotifier`, delivers callbacks during the build phase.
  Widget buildEditorState(BuildContext context, WidgetRef ref) {
    final value = ref.watch(activeEditorTabProvider).value;
    if (value == null || value.type != "file") {
      return const SizedBox.shrink();
    }
    final controller = value.editorController;
    if (controller == null) return const SizedBox.shrink();
    return _EditorStateLabel(
      // Stable key: the children list around this one has no keys and its
      // length changes with transfer progress, running operations and registry
      // items, so an unkeyed widget here can be re-matched to a different
      // sibling.
      key: const ValueKey('status-editor-state'),
      controller: controller,
      compact: ref.watch(themeStyle) == ThemeStyle.compact,
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
            // Registry items can carry a raw label or an i18n key; the key is
            // resolved at build time so a locale switch re-renders the chip.
            op.labelKey != null
                ? translateForWidget(ref, op.labelKey!)
                : op.label,
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
              child: TooltipAnchor(
                message: translateForWidget(ref, I18nKey.statusInterrupt),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: compact ? 15 : 17,
                  icon: const Icon(Icons.stop_circle_outlined),
                  onPressed: op.onInterrupt,
                ),
              ),
            ),
          ],
          if (op.canForceReset) ...[
            SizedBox(
              width: iconButtonSize,
              height: iconButtonSize,
              child: TooltipAnchor(
                message: translateForWidget(ref, I18nKey.statusForceReset),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: compact ? 15 : 17,
                  icon: const Icon(Icons.refresh),
                  onPressed: op.onForceReset,
                ),
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
    return TooltipAnchor(
      message: translateForWidget(ref, I18nKey.statusOpenMenu),
      child: IconButton(
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 32),
          fixedSize: const Size(36, 32),
          padding: EdgeInsets.zero,
        ),
        onPressed: () => Scaffold.of(context).openDrawer(),
        icon: const Icon(Icons.menu, size: 20),
      ),
    );
  }
}

/// LSP `DiagnosticSeverity` values the status bar counts and the diagnostic
/// picker lists. Information and Hint are intentionally left out: for a board
/// script they are noise, and counting them would make the number look
/// alarming for correct code. Sharing one pair of constants is what keeps the
/// status bar count and the picker list from ever disagreeing.
const int _lspSeverityError = 1;
const int _lspSeverityWarning = 2;

/// Trailing status bar segment: caret position, selection size and the
/// current file's LSP error/warning counts.
///
/// Listens to [CodeForgeController.displayChanges], the controller's
/// frame-safe signal, and to nothing else. It must not subscribe to the
/// controller directly: the editor notifies from inside its own `initState` and
/// build, and this widget lives outside the editor's subtree, so a direct
/// subscription would call back during the build phase.
///
/// The caret readout is a [TextButton] (clicking it scrolls the caret line
/// back into view) and the problem count is one as well, so the segment does
/// introduce button semantics nodes. Beyond those two, labels stay plain
/// [Text] rather than [Semantics] wrappers: this app has no accessibility
/// infrastructure today, and reshaping the engine's accessibility tree for
/// the whole window is a separate piece of work, not something to smuggle in
/// with a status bar readout.
class _EditorStateLabel extends ConsumerWidget {
  const _EditorStateLabel({
    super.key,
    required this.controller,
    required this.compact,
  });

  final CodeForgeController controller;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: controller.displayChanges,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontSize: compact ? 12 : null,
        );

        var errors = 0;
        var warnings = 0;
        for (final diagnostic in controller.diagnostics) {
          if (diagnostic.severity == _lspSeverityError) {
            errors++;
          } else if (diagnostic.severity == _lspSeverityWarning) {
            warnings++;
          }
        }

        final position = _positionText(ref, controller);
        final problems = errors > 0
            ? _problemText(ref, errors, warnings)
            : null;

        return Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, end: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (position.isNotEmpty)
                // Clicking the line/column readout scrolls the caret line
                // back into view after scrolling (or a find jump) has left
                // it off-screen.
                TextButton(
                  onPressed: () => _revealCaret(controller, ref),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                    minimumSize: const Size(0, 32),
                    // Same pill shape, height and padding as
                    // [_ProblemButton], so the readout stays one segment of
                    // the status bar instead of a differently shaped chip.
                    padding: const EdgeInsetsDirectional.only(
                      start: 10,
                      end: 12,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: context.effectiveRadius,
                    ),
                  ),
                  child: Text(position, style: textStyle),
                ),
              if (problems != null) ...[
                const SizedBox(width: 8),
                // Clicking the error/warning count opens the shared jump
                // window listing every diagnostic of this file.
                _ProblemButton(
                  text: problems,
                  textStyle: textStyle,
                  iconSize: compact ? 14 : 16,
                  onPressed: () =>
                      showEditorDiagnosticsPicker(context, ref, controller),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// The line the caret sits on, with the offset clamped to the document so a
  /// caret that outlived its text (the file shrank underneath it) still
  /// resolves instead of throwing.
  int _caretLine(CodeForgeController controller) {
    final offset = controller.selection.extentOffset.clamp(
      0,
      controller.length,
    );
    return controller.getLineAtOffset(offset);
  }

  /// Caret line/column, plus the selection size when there is a selection.
  ///
  /// A WidgetRef cannot use `translateWithReplacements` (it takes a `Ref`), so
  /// the placeholders are substituted directly.
  String _positionText(WidgetRef ref, CodeForgeController controller) {
    final offset = controller.selection.extentOffset.clamp(
      0,
      controller.length,
    );
    // Columns are 1-based and counted in characters, matching the LSP and
    // matching what a board traceback points at. An empty document has no
    // line to query, so fall through with column 1.
    final hasLines = controller.lineCount > 0;
    final line = hasLines ? _caretLine(controller) : 0;
    final column = hasLines
        ? offset - controller.getLineStartOffset(line) + 1
        : offset + 1;
    final caret = translateForWidget(
      ref,
      I18nKey.statusCursorPosition,
    ).replaceAll('{line}', '${line + 1}').replaceAll('{column}', '$column');
    final selection = controller.selection;
    if (selection.isCollapsed) return caret;
    final selected = translateForWidget(
      ref,
      I18nKey.statusSelectionCount,
    ).replaceAll('{count}', '${selection.end - selection.start}');
    return '$caret · $selected';
  }

  /// Scrolls the editor so the caret's line is visible again.
  ///
  /// The caret can end up far off-screen after the user scrolls away or a
  /// find jump moves the view, and the line/column readout is then the only
  /// visible hint of where editing continues.
  ///
  /// Compact layouts unmount the editor while another page is visible while
  /// the status bar keeps showing this readout, so a click can land on an
  /// unmounted editor. That follows the same policy as plugin reveals: switch
  /// to the dedicated editor route and retry until the editor mounts.
  Future<void> _revealCaret(
    CodeForgeController controller,
    WidgetRef ref,
  ) async {
    if (controller.lineCount == 0) return;
    final line = _caretLine(controller);
    try {
      await retryEditorReveal(
        reveal: () {
          controller.scrollToLine(line);
          // Hand focus back so the caret blinks at the revealed position —
          // the flash alone is easy to miss on a long file.
          controller.focusNode?.requestFocus();
        },
        onEditorUnavailable: () => _goToEditorPage(ref),
      );
    } on StateError catch (error) {
      // The editor never mounted within the retry budget (its tab was just
      // closed, for example).
      debugPrint('status bar reveal: editor not mounted: $error');
    } on RangeError catch (error) {
      // The caret outlived the document (the file shrank underneath it).
      debugPrint('status bar reveal: caret out of range: $error');
    }
  }

  /// Opens the editor page when the layout hosts the editor on its own route;
  /// the desktop workspace keeps the editor mounted on every route.
  void _goToEditorPage(WidgetRef ref) {
    final layoutMode = ref
        .read(environmentNotifierProvider)
        .snapshot
        .layoutMode;
    if (layoutNeedsDedicatedEditorRoute(layoutMode) &&
        !routes.state.matchedLocation.startsWith(edit)) {
      routes.go(edit);
    }
  }

  String _problemText(WidgetRef ref, int errors, int warnings) {
    final I18nKey key = switch ((errors, warnings)) {
      (_, 0) => I18nKey.statusProblemsErrorsOnly,
      (0, _) => I18nKey.statusProblemsWarningsOnly,
      _ => I18nKey.statusProblems,
    };
    return translateForWidget(
      ref,
      key,
    ).replaceAll('{errors}', '$errors').replaceAll('{warnings}', '$warnings');
  }
}

/// Clickable form of the status bar's error/warning count.
///
/// A [TextButton] rather than an [InkWell] wrapped around the readout so the
/// whole segment is one real hover/focus target. The child is still a plain
/// [Row] of an icon and a [Text], so the segment renders and measures
/// exactly like the previous non-interactive readout.
class _ProblemButton extends StatelessWidget {
  const _ProblemButton({
    required this.text,
    required this.textStyle,
    required this.onPressed,
    this.iconSize = 16,
  });

  final String text;
  final TextStyle? textStyle;
  final VoidCallback onPressed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: scheme.error,
        minimumSize: const Size(0, 32),
        // Same pill shape, height and padding as [StatusBarButton], so the
        // error count reads as one more segment of the status bar instead of
        // a differently shaped chip.
        padding: const EdgeInsetsDirectional.only(start: 10, end: 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: context.effectiveRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: iconSize, color: scheme.error),
          const SizedBox(width: 3),
          Text(text, style: textStyle?.copyWith(color: scheme.error)),
        ],
      ),
    );
  }
}

/// Opens the shared jump window over every diagnostic reported for
/// [controller]'s file, so the status bar's error count navigates exactly
/// like find-references does.
///
/// The file comes from the controller rather than an argument so the window
/// always describes the file whose count was just clicked.
Future<void> showEditorDiagnosticsPicker(
  BuildContext context,
  WidgetRef ref,
  CodeForgeController controller,
) async {
  final filePath = controller.openedFile;
  if (filePath == null) return;
  final scheme = Theme.of(context).colorScheme;
  final entries = <LspLocationEntry>[];
  for (final diagnostic in controller.diagnostics) {
    if (diagnostic.severity != _lspSeverityError &&
        diagnostic.severity != _lspSeverityWarning) {
      continue;
    }
    final start = diagnostic.range['start'];
    if (start is! Map) continue;
    final isError = diagnostic.severity == _lspSeverityError;
    entries.add(
      LspLocationEntry(
        path: filePath,
        line: (start['line'] as num?)?.toInt(),
        character: (start['character'] as num?)?.toInt(),
        // The diagnostic message is the useful label here: every row is the
        // same file, so repeating the file name as the title would waste the
        // one line that actually says something. The subtitle falls back to
        // the dialog's default "file line:column" rendering.
        title: diagnostic.message,
        icon: isError ? Icons.error_outline : Icons.warning_amber_rounded,
        iconColor: isError ? scheme.error : Colors.yellow.shade700,
        severityRank: isError ? 0 : 1,
      ),
    );
  }
  if (entries.isEmpty) {
    ref
        .read(ideMessageProvider.notifier)
        .show(translateForWidget(ref, I18nKey.editorDiagnosticsEmpty));
    return;
  }
  // Errors first, then in document order, so the list reads like the file.
  entries.sort((a, b) {
    final bySeverity = a.severityRank.compareTo(b.severityRank);
    if (bySeverity != 0) return bySeverity;
    return (a.line ?? 0).compareTo(b.line ?? 0);
  });
  await showLspLocationDialog(
    context,
    ref,
    titleBuilder: (ref) => translateForWidget(
      ref,
      I18nKey.editorDiagnosticsTitle,
    ).replaceAll('{count}', entries.length.toString()),
    entries: entries,
    emptyKey: I18nKey.editorDiagnosticsEmpty,
    onOpen: (entry) => revealLspLocation(
      context,
      ref,
      entry.path,
      entry.line,
      entry.character,
    ),
  );
}
