part of '../function_page.dart';

class MobileView extends ConsumerWidget {
  const MobileView({super.key, required this.child, required this.state});

  final Widget child;
  final GoRouterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pluginItems = _pluginNavigationItems(ref);
    // 确保组件重绘后导航栏选择的值与实际显示内容同步
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final routeIndex = _navigationIndex(state, pluginItems, builtInCount: 7);
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
            // Wrapped like the desktop and tablet workspaces are: the editor
            // area lays its groups out with `shadcn.ResizablePanel`, whose
            // default divider is a shadcn `VerticalDivider` that asserts when
            // no shadcn theme is in scope. A restored split reaches this branch
            // on a narrow window, where the layout is no longer a single group.
            Expanded(child: buildShadcnLayer(context, child)),
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
    final navigationRoutes = _navigationRoutes(pluginItems, builtInCount: 7);
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
      final routeIndex = _navigationIndex(state, pluginItems, builtInCount: 7);
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
    final navigationRoutes = _navigationRoutes(pluginItems, builtInCount: 7);
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
    final navigationRoutes = _navigationRoutes(pluginItems, builtInCount: 6);
    // 确保组件重绘后导航栏选择的值与实际显示内容同步
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final routeIndex = _navigationIndex(state, pluginItems, builtInCount: 6);
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
    final isGitRoute = state.matchedLocation.startsWith('/git');
    // Search and source control both render a dense list of file paths, so
    // they get a wider left pane than the file tree.
    final isWideRoute =
        isGitRoute || state.matchedLocation.startsWith('/search');

    // The desktop workspace already owns the central editor pane. Mounting the
    // /editor route child here would render the same tab controller twice.
    if (showFunctionPanel) {
      children.add(
        shadcn.ResizablePane.flex(
          initialFlex: isWideRoute ? 3 : 2,
          minSize: isWideRoute ? 340 : 220,
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
      onSecondaryTapUp: (details, cell) =>
          _showOutputLogContextMenu(context, ref, details.globalPosition),
    );
  }
}

/// The log's right-click menu drops paste and search: the log is output-only,
/// with nothing to paste into and no search bar to open.
const Set<TerminalContextAction> _outputLogMenuActions = {
  TerminalContextAction.copy,
  TerminalContextAction.selectAll,
  TerminalContextAction.clear,
};

bool get _outputLogHasSelection {
  final selection = ideOutputController.selection;
  if (selection == null || selection.isCollapsed) return false;
  return ideOutputTerminal.buffer.getText(selection).isNotEmpty;
}

Future<void> _showOutputLogContextMenu(
  BuildContext context,
  WidgetRef ref,
  Offset globalPosition,
) async {
  final action = await showTerminalContextMenu(
    context,
    globalPosition: globalPosition,
    hasSelection: _outputLogHasSelection,
    actions: _outputLogMenuActions,
  );
  if (!context.mounted || action == null) return;
  // Clearing goes through the notifier so the entry list behind the log's own
  // clear button is emptied along with the terminal buffer.
  if (action == TerminalContextAction.clear) {
    ref.read(ideOutputLogProvider.notifier).clear();
    return;
  }
  await applyTerminalContextAction(
    action,
    terminal: ideOutputTerminal,
    controller: ideOutputController,
  );
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
                    // Rebind the OSC 10/11 color queries to the current theme
                    // before the surface renders: the closure captures the
                    // theme by value, and a theme switch must be answered with
                    // the new palette rather than the one from startup.
                    configureTerminalColorQueries(
                      session.terminal,
                      terminalTheme,
                      backgroundColor: session.backgroundColor,
                    );
                    return DesktopTerminalSurface(
                      // Keying on the session id still rebuilds for a new
                      // session; the surface keeps a GlobalKey on its
                      // TerminalView so a theme contribution updates the
                      // renderer in place instead of recreating it.
                      key: ValueKey('terminal_${session.id}'),
                      terminal: session.terminal,
                      controller: session.controller,
                      theme: effectiveTheme,
                      textStyle: buildTerminalStyle(ref),
                      // The link actions need the editor and the message
                      // system, which the surface deliberately does not import;
                      // they are injected here where the workspace providers
                      // are already in scope.
                      onUrlClick: (link) =>
                          openTerminalUrlLink(context, ref, link.url!),
                      onFileReferenceClick: (link) =>
                          revealTerminalFileLink(context, ref, link),
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
                    TooltipAnchor(
                      message: translateForWidget(
                        ref,
                        I18nKey.bottomPanelNewTerminal,
                      ),
                      child: IconButton(
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
              TooltipAnchor(
                message: translateForWidget(
                  ref,
                  I18nKey.bottomPanelCloseTerminal,
                ),
                child: IconButton(
                  onPressed: () => ref
                      .read(desktopTerminalProvider.notifier)
                      .closeSession(session.id),
                  icon: const Icon(Icons.close, size: 16),
                ),
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
  // One selection tint for every surface in the app: the terminal is painted
  // by xterm, so it cannot inherit the theme's `textSelectionTheme` and has to
  // be handed the same color explicitly.
  final selection = AppSelection.text(scheme);
  late final TerminalTheme baseTheme;
  if (appearance == TerminalAppearance.custom) {
    final palette = ref.watch(terminalCustomPalette);
    baseTheme = _terminalThemeFromPalette(
      foreground: Color(ref.watch(terminalCustomForeground)),
      background: Color(ref.watch(terminalCustomBackground)),
      palette: palette.length == 16
          ? palette.map(Color.new).toList()
          : kDefaultTerminalCustomPalette.map(Color.new).toList(),
      selection: selection,
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
      selection: selection,
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
      selection: selection,
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
    // A plugin theme may repaint the palette, never the selection tint: the
    // app-wide selection color has to stay recognisable across surfaces.
    selection: base.selection,
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
  required Color selection,
  required double minimumContrastRatio,
}) {
  return TerminalTheme(
    cursor: foreground.withValues(alpha: 0.8),
    selection: selection,
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
