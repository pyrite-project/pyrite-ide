import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/constants/navigation_bar.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/desktop_terminal_provider.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/editor/lsp_state.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/file_transfer_progress.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/features/window.dart';
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
    final isConnected = ref.watch(getUsbSerialProvider()).isConnected;
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
            tooltip: '清空输出',
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
              tooltip: "连接 WebREPL",
              onPressed: () {
                ref.read(webReplProvider.notifier).connect();
              },
              icon: const Icon(Icons.wifi),
            ),
          IconButton(
            tooltip: "清空终端",
            onPressed: () => repl.write('\x1b[2J\x1b[H'),
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
          IconButton(
            tooltip: useWebRepl
                ? "中断设备运行"
                : (isConnected ? "中断设备运行" : "连接设备后可中断运行"),
            onPressed: (useWebRepl || isConnected)
                ? () {
                    if (useWebRepl) {
                      ref.read(webReplProvider.notifier).sendCommand("\x03");
                    } else {
                      ref
                          .read(getUsbSerialProvider().notifier)
                          .sendCommand("\x03");
                    }
                  }
                : null,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
          IconButton(
            tooltip: useWebRepl
                ? "软重启设备"
                : (isConnected ? "软重启设备" : "连接设备后可软重启"),
            onPressed: (useWebRepl || isConnected)
                ? () {
                    if (useWebRepl) {
                      ref.read(webReplProvider.notifier).sendCommand("\x04");
                    } else {
                      ref
                          .read(getUsbSerialProvider().notifier)
                          .sendCommand("\x04");
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
      height: 38,
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
            label: '输出',
            icon: Icons.article_outlined,
            index: 1,
            selectedIndex: selectedIndex,
          ),
          _BottomPanelTab(
            label: '终端',
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

  final String label;
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
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
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
      optionalDivider: true,
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
      tooltip: isMobile ? "打开控制台" : (consoleVisible ? "隐藏控制台" : "显示 REPL"),
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
      tooltip: visible ? "隐藏功能面板" : "显示功能面板",
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
      tooltip: visible ? "隐藏扩展面板" : "显示扩展面板",
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

class MobileView extends ConsumerWidget {
  const MobileView({super.key, required this.child, required this.state});

  final Widget child;
  final GoRouterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useNavigationDrawer =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    // 确保组件重绘后导航栏选择的值与实际显示内容同步
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final routeIndex = routesName.indexOf(
        "/${state.matchedLocation.split("/")[1]}",
      );
      // 这里对获取到的路径进行切片处理，并仅获取父页面的路径内容，确保 selectedIndexValue 的值符合预期
      // e.g. "/settings/about" => "/settings"
      if (routeIndex != -1 && routeIndex != ref.read(mobileSelectedIndex)) {
        selectedIndexValue = routeIndex;
        ref.read(mobileSelectedIndex.notifier).state = routeIndex;
      }
    });
    return Scaffold(
      drawer: useNavigationDrawer ? mobileNavigationDrawer(context, ref) : null,
      bottomNavigationBar: useNavigationDrawer
          ? null
          : bottomNavigationBar(context, ref),
      body: Column(
        children: [
          Expanded(child: child),
          EditorToolsBar(showNavigationDrawerButton: useNavigationDrawer),
        ],
      ),
    );
  }

  void selectDestination(BuildContext context, WidgetRef ref, int value) {
    selectedIndexValue = value;
    ref.read(tabletSelectedIndex.notifier).state = selectedIndexValue;
    ref.read(mobileSelectedIndex.notifier).state = selectedIndexValue;
    if (selectedIndexValue < desktopRailItems.length) {
      ref.read(desktopSelectedIndex.notifier).state = selectedIndexValue;
    } else {
      ref.read(desktopSelectedIndex.notifier).state = 0;
    }
    context.go(routesName[selectedIndexValue]);
  }

  Widget mobileNavigationDrawer(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(mobileSelectedIndex);
    return Builder(
      builder: (drawerContext) {
        return NavigationDrawer(
          selectedIndex:
              selectedIndex >= 0 && selectedIndex < drawerItems.length
              ? selectedIndex
              : null,
          onDestinationSelected: (value) {
            Navigator.of(drawerContext).pop();
            selectDestination(context, ref, value);
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
            ...drawerItems,
          ],
        );
      },
    );
  }

  Widget bottomNavigationBar(BuildContext context, WidgetRef ref) {
    return NavigationBar(
      destinations: bottomItems,
      selectedIndex: ref.watch(mobileSelectedIndex),
      onDestinationSelected: (value) => selectDestination(context, ref, value),
    );
  }
}

class TabletView extends ConsumerWidget {
  const TabletView({super.key, required this.child, required this.state});

  final Widget child;
  final GoRouterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 确保组件重绘后导航栏选择的值与实际显示内容同步
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final routeIndex = routesName.indexOf(
        "/${state.matchedLocation.split("/")[1]}",
      );
      // 这里对获取到的路径进行切片处理，并仅获取父页面的路径内容，确保 selectedIndexValue 的值符合预期
      // e.g. "/settings/about" => "/settings"
      if (routeIndex != -1 && routeIndex != ref.read(tabletSelectedIndex)) {
        selectedIndexValue = routeIndex;
        ref.read(tabletSelectedIndex.notifier).state = routeIndex;
      }
    });
    return Scaffold(
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
    );
  }

  Widget railNavigationBar(BuildContext context, WidgetRef ref) {
    return NavigationRail(
      minWidth: 72,
      backgroundColor: Theme.of(context).colorScheme.surface,
      labelType: NavigationRailLabelType.selected,
      destinations: tabletRailItems,
      selectedIndex: ref.watch(tabletSelectedIndex),
      onDestinationSelected: (value) {
        selectedIndexValue = value;
        ref.read(desktopSelectedIndex.notifier).state = selectedIndexValue;
        ref.read(mobileSelectedIndex.notifier).state = selectedIndexValue;
        ref.read(tabletSelectedIndex.notifier).state = selectedIndexValue;
        context.go(routesName[selectedIndexValue]);
      },
    );
  }
}

class DesktopView extends ConsumerWidget {
  const DesktopView({super.key, required this.child, required this.state});

  final Widget child;
  final GoRouterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 确保组件重绘后导航栏选择的值与实际显示内容同步
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final routeIndex = routesName.indexOf(
        "/${state.matchedLocation.split("/")[1]}",
      );
      // 这里对获取到的路径进行切片处理，并仅获取父页面的路径内容，确保 selectedIndexValue 的值符合预期
      // e.g. "/settings/about" => "/settings"
      if (routeIndex >= desktopRailItems.length) {
        selectedIndexValue = 0;
        context.go(file);
        return;
      }
      if (routeIndex != -1) {
        selectedIndexValue = routeIndex;
      }
      ref.read(desktopSelectedIndex.notifier).state = selectedIndexValue;
    });
    return Scaffold(
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
    );
  }

  Widget railNavigationBar(BuildContext context, WidgetRef ref) {
    return NavigationRail(
      backgroundColor: Theme.of(context).colorScheme.surface,
      minWidth: 72,
      labelType: NavigationRailLabelType.selected,
      destinations: desktopRailItems,
      selectedIndex: ref.watch(desktopSelectedIndex),
      trailing: const RailTrailingActions(),
      onDestinationSelected: (value) {
        selectedIndexValue = value;
        ref.read(desktopSelectedIndex.notifier).state = selectedIndexValue;
        ref.read(mobileSelectedIndex.notifier).state = selectedIndexValue;
        ref.read(tabletSelectedIndex.notifier).state = selectedIndexValue;
        context.go(routesName[selectedIndexValue]);
      },
    );
  }

  List<shadcn.ResizablePane> _pageStructure(
    BuildContext context,
    WidgetRef ref,
  ) {
    final List<shadcn.ResizablePane> children = [];
    final width = MediaQuery.sizeOf(context).width;
    final showFunctionPanel = ref.watch(functionPageShow);
    final showExpansionPanel = ref.watch(expansionPageShow) && width >= 1280;

    if (showFunctionPanel) {
      children.add(
        shadcn.ResizablePane.flex(initialFlex: 2, minSize: 220, child: child),
      );
    }
    children.add(
      shadcn.ResizablePane.flex(
        initialFlex: 4,
        minSize: 300,
        child: shadcn.ResizablePanel.vertical(
          optionalDivider: true,
          draggerBuilder: (context) {
            return shadcn.HorizontalResizableDragger();
          },
          children: buildConsoleView(ref, Editor()),
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
        optionalDivider: true,
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
    final webReplState = ref.watch(webReplProvider);
    final webReplConnected = webReplState.state == WebReplState.connected;

    if (webReplConnected) {
      repl.onOutput = (String data) {
        ref.read(webReplProvider.notifier).sendText(data);
      };
    }

    final terminalTheme = buildTerminalTheme(context);
    final surface = Theme.of(context).colorScheme.surface;
    return TerminalView(
      repl,
      controller: replController,
      theme: terminalTheme,
      textStyle: buildTerminalStyle(ref),
      key: ValueKey('repl_${surface.toARGB32()}'),
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
          label: const Text('Android 暂不支持桌面终端'),
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
                    label: const Text('新建终端'),
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
                    const Expanded(child: Text('终端')),
                    IconButton(
                      tooltip: '新建终端',
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
                tooltip: '关闭终端',
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
    return Container(
      height: 40,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (showNavigationDrawerButton) ...[
            const MobileNavigationDrawerButton(),
            const SizedBox(width: 4),
          ] else if (!isMobile) ...[
            buildLspState(context, ref),
            const SizedBox(width: 4),
          ],
          Flexible(flex: isMobile ? 1 : 2, child: buildFileState(context, ref)),
          const SizedBox(width: 4),
          Flexible(child: buildBoardConnectState(context, ref)),
          const SizedBox(width: 4),
          buildConsoleState(context, ref),
          const SizedBox(width: 4),
          if (ref.watch(fileTransferProgressProvider).isActive) ...[
            Flexible(flex: 1, child: buildTransferState(context, ref)),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  Widget buildFileState(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final value = ref.watch(tabbedViewControllerProvider).selectedTab?.value;
    if (value is! TabDataValue || value.type != "file") {
      return StatusBarButton(
        label: "欢迎页",
        icon: Icons.home_outlined,
        compact: isMobile,
        tooltip: "当前未打开代码文件",
        onPressed: () {},
      );
    }

    final fileName = path.basename(value.filePath);
    final source = value.isBoardFile == true ? "设备" : "本地";
    final saved = value.isSaved;
    return StatusBarButton(
      label: isMobile
          ? (saved ? "已保存" : "未保存")
          : "$source · ${saved ? "已保存" : "未保存"} · $fileName",
      icon: value.isBoardFile == true
          ? Icons.developer_board_outlined
          : Icons.description_outlined,
      statusColor: saved ? scheme.primary : scheme.tertiary,
      compact: isMobile,
      tooltip: saved ? "再次保存当前文件" : "保存当前文件",
      onPressed: () async {
        await ref.read(fileProvider.notifier).saveCurrentFile();
        if (!context.mounted) return;

        showIdeSuccess(context, "已保存当前文件");
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
    final label =
        transfer.message ?? '${transfer.directionLabel}$index · $file$percent';
    final color = transfer.failed ? scheme.error : scheme.primary;

    return Tooltip(
      message: transfer.currentFile ?? label,
      child: SizedBox(
        height: 32,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
        ? "LSP 正常"
        : isLoading
        ? "LSP 启动中"
        : hasError
        ? "LSP 异常"
        : "LSP 未就绪";
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
      tooltip: "语言服务器设置",
      onPressed: () => context.go("/settings/lsp"),
    );
  }

  Widget buildBoardConnectState(BuildContext context, WidgetRef ref) {
    final usb = ref.watch(getUsbSerialProvider());
    final isConnected = usb.isConnected;
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final label = isMobile
        ? (isConnected ? usb.selectedPortName! : "设备")
        : (isConnected ? "设备：${usb.selectedPortName!}" : "未连接设备");
    return StatusBarButton(
      label: label,
      icon: Icons.usb,
      compact: isMobile,
      statusColor: isConnected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.outline,
      tooltip: isConnected ? "打开设备管理" : "连接 MicroPython 设备",
      onPressed: () => context.go("/tools"),
    );
  }

  Widget buildConsoleState(BuildContext context, WidgetRef ref) {
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final visible = ref.watch(consolePageShow);
    return StatusBarButton(
      label: isMobile ? "REPL" : (visible ? "显示控制台" : "隐藏控制台"),
      icon: Icons.terminal,
      compact: isMobile,
      tooltip: isMobile ? "打开控制台" : (visible ? "隐藏控制台" : "显示 REPL"),
      onPressed: () {
        if (isMobile) {
          showMobileConsoleSheet(context);
          return;
        }
        ref.read(consolePageShow.notifier).state = !visible;
      },
    );
  }
}

class MobileNavigationDrawerButton extends StatelessWidget {
  const MobileNavigationDrawerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: "打开菜单",
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
