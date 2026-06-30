import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/constants/navigation_bar.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';
import 'package:pyrite_ide/core/services/editor/lsp_state.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:tolyui_message/tolyui_message.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/features/window.dart';
import 'package:pyrite_ide/pages/editor/main.dart';
import 'package:pyrite_ide/pages/file/main.dart';
import 'package:pyrite_ide/pages/settings/about.dart';
import 'package:pyrite_ide/pages/settings/editor.dart';
import 'package:pyrite_ide/pages/settings/lsp.dart';
import 'package:pyrite_ide/pages/settings/main.dart';
import 'package:pyrite_ide/pages/settings/style.dart';
import 'package:pyrite_ide/pages/device_tools/main.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:xterm/xterm.dart';

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
    final useWebRepl = webReplConnected || webReplState.state == WebReplState.waitingPassword;

    return Column(
      children: [
        PaneHeader(
          title: "REPL",
          subtitle: useWebRepl
              ? "WiFi WebREPL 连接"
              : (isConnected ? "MicroPython 交互式终端" : "连接设备后可输入命令"),
          leadingIcon: Icons.terminal,
          actions: [
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
          ],
        ),
        const Expanded(child: ReplView()),
      ],
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
                      "assets/icons/app_icon_appbar.png",
                      color: Theme.of(context).colorScheme.onSurface,
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

    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final defaultTheme = TerminalThemes.defaultTheme;
    final terminalTheme = TerminalTheme(
      cursor: defaultTheme.cursor,
      selection: defaultTheme.selection,
      foreground: onSurface,
      background: surface,
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
    return TerminalView(
      repl,
      controller: replController,
      theme: terminalTheme,
      key: ValueKey('repl_${surface.value}'),
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
          const Spacer(),
          buildConsoleState(context, ref),
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

        $message.attach(context);
        $message.success(message: "已保存当前文件");
      },
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
