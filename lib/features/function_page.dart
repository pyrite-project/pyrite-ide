import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/constants/navigation_bar.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/services/board_manager/utils.dart';
import 'package:pyrite_ide/core/services/editor/lsp_state.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/features/window.dart';
import 'package:pyrite_ide/pages/editor/main.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:xterm/xterm.dart';

Widget consolePage() {
  return const Column(
    children: [
      PaneHeader(
        title: "REPL",
        subtitle: "MicroPython 交互式终端",
        leadingIcon: Icons.terminal,
      ),
      Expanded(child: ReplView()),
    ],
  );
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
      tooltip: isMobile ? "打开 REPL" : (consoleVisible ? "隐藏 REPL" : "显示 REPL"),
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
      icon: Icon(visible ? Icons.left_panel_close : Icons.left_panel_open),
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
      icon: Icon(visible ? Icons.right_panel_close : Icons.right_panel_open),
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
      bottomNavigationBar: bottomNavigationBar(context, ref),
      body: Column(
        children: [
          Expanded(child: child),
          const EditorToolsBar(),
        ],
      ),
    );
  }

  Widget bottomNavigationBar(BuildContext context, WidgetRef ref) {
    return NavigationBar(
      destinations: bottomItems,
      selectedIndex: ref.watch(mobileSelectedIndex),
      onDestinationSelected: (value) {
        selectedIndexValue = value;
        ref.read(tabletSelectedIndex.notifier).state = selectedIndexValue;
        ref.read(mobileSelectedIndex.notifier).state = selectedIndexValue;
        if (selectedIndexValue < desktopRailItems.length) {
          ref.read(desktopSelectedIndex.notifier).state = selectedIndexValue;
        } else {
          ref.read(desktopSelectedIndex.notifier).state = 0;
        }
        context.go(routesName[selectedIndexValue]);
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
      minWidth: 64,
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
    Widget functionPage,
    WidgetRef ref,
  ) {
    final List<shadcn.ResizablePane> children = [];

    if (ref.watch(functionPageShow)) {
      children.add(
        shadcn.ResizablePane.flex(
          initialFlex: 2,
          minSize: 200,
          child: functionPage,
        ),
      );
    }
    children.add(
      shadcn.ResizablePane.flex(
        initialFlex: 4,
        minSize: 300,
        child: shadcn.ResizablePanel.vertical(
          draggerBuilder: (context) {
            return shadcn.HorizontalResizableDragger();
          },
          children: buildConsoleView(ref, Editor()),
        ),
      ),
    );
    if (ref.watch(expansionPageShow)) {
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
        draggerBuilder: (context) {
          return shadcn.HorizontalResizableDragger();
        },
        children: _pageStructure(child, ref),
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
    return Column(
      children: [
        Expanded(child: TerminalView(repl, controller: replController)),
      ],
    );
  }
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
  const EditorToolsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          buildLspState(context, ref),
          const SizedBox(width: 4),
          Flexible(child: buildBoardConnectState(context, ref)),
          const Spacer(),
          buildConsoleState(context, ref),
        ],
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
        ? Colors.green
        : isLoading
        ? scheme.tertiary
        : scheme.error;
    return StatusBarButton(
      label: label,
      icon: Icons.data_object,
      statusColor: color,
      tooltip: "语言服务器设置",
      onPressed: () => context.push("/settings/lsp"),
    );
  }

  Widget buildBoardConnectState(BuildContext context, WidgetRef ref) {
    final usb = ref.watch(getUsbSerialProvider());
    final isConnected = usb.isConnected;
    final label = isConnected ? "设备：${usb.selectedPortName!}" : "未连接设备";
    return StatusBarButton(
      label: label,
      icon: Icons.usb,
      statusColor: isConnected
          ? Colors.green
          : Theme.of(context).colorScheme.error,
      tooltip: isConnected ? "打开设备管理" : "连接 MicroPython 设备",
      onPressed: () => context.push("/tools"),
    );
  }

  Widget buildConsoleState(BuildContext context, WidgetRef ref) {
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final visible = ref.watch(consolePageShow);
    return StatusBarButton(
      label: isMobile ? "REPL" : (visible ? "REPL 显示" : "REPL 隐藏"),
      icon: Icons.terminal,
      compact: isMobile,
      tooltip: isMobile ? "打开 REPL" : (visible ? "隐藏 REPL" : "显示 REPL"),
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
