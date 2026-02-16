import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/constants/navigation_bar.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/services/editor.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/pylsp/data.dart';
import 'package:pyrite_ide/features/window.dart';
import 'package:pyrite_ide/pages/edit/main.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:xterm/xterm.dart';

Widget consolePage() {
  return DefaultTabController(
    length: 2,
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TabBar(
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: "REPL", height: 35),
                  Tab(text: "问题", height: 35),
                ],
                isScrollable: true,
              ),
            ),
          ],
        ),

        Expanded(child: TabBarView(children: [ReplView(), QuestionView()])),
      ],
    ),
  );
}

List<shadcn.ResizablePane> buildConsoleView(WidgetRef ref, Widget child) {
  final List<shadcn.ResizablePane> children = [];
  children.add(
    shadcn.ResizablePane.flex(initialFlex: 3, minSize: 50, child: child),
  );

  if (ref.watch(consolePageShow)) {
    children.add(
      shadcn.ResizablePane.flex(
        initialFlex: 1,
        minSize: 10,
        child: consolePage(),
      ),
    );
  }

  return children;
}

class MobileView extends ConsumerWidget {
  const MobileView({super.key, required this.child, required this.state});

  final Widget child;
  final GoRouterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 确保组件重绘后导航栏选择的值与实际显示内容同步
    WidgetsBinding.instance.addPostFrameCallback((_) {
      selectedIndexValue = routesName.indexOf(
        "/${state.matchedLocation.split("/")[1]}",
      );
      // 这里对获取到的路径进行切片处理，并仅获取父页面的路径内容，确保 selectedIndexValue 的值符合预期
      // e.g. "/settings/about" => "/settings"
      if (selectedIndexValue != ref.read(mobileSelectedIndex)) {
        selectedIndexValue = ref.read(mobileSelectedIndex);
        context.go(routesName[selectedIndexValue]);
      }
    });
    return Scaffold(
      bottomNavigationBar: bottomNavigationBar(context, ref),
      body: shadcn.ShadcnLayer(
        theme: shadcn.ThemeData(
          colorScheme: Theme.of(context).brightness == Brightness.light
              ? shadcn.ColorSchemes.lightDefaultColor
              : shadcn.ColorSchemes.darkDefaultColor,
        ),
        child: shadcn.ResizablePanel.vertical(
          draggerBuilder: (context) {
            return shadcn.HorizontalResizableDragger();
          },
          children: buildConsoleView(ref, child),
        ),
      ),
    );
  }

  Widget bottomNavigationBar(BuildContext context, WidgetRef ref) {
    return NavigationBar(
      // labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
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
      selectedIndexValue = routesName.indexOf(
        "/${state.matchedLocation.split("/")[1]}",
      );
      // 这里对获取到的路径进行切片处理，并仅获取父页面的路径内容，确保 selectedIndexValue 的值符合预期
      // e.g. "/settings/about" => "/settings"
      if (selectedIndexValue != ref.read(mobileSelectedIndex)) {
        selectedIndexValue = ref.read(mobileSelectedIndex);
        context.go(routesName[selectedIndexValue]);
      }
    });
    return Scaffold(
      body: Row(
        children: [
          railNavigationBar(context, ref),
          Expanded(
            child: shadcn.ShadcnLayer(
              theme: shadcn.ThemeData(
                colorScheme: Theme.of(context).brightness == Brightness.light
                    ? shadcn.ColorSchemes.lightDefaultColor
                    : shadcn.ColorSchemes.darkDefaultColor,
              ),
              child: shadcn.ResizablePanel.vertical(
                draggerBuilder: (context) {
                  return shadcn.HorizontalResizableDragger();
                },
                children: buildConsoleView(ref, child),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget railNavigationBar(BuildContext context, WidgetRef ref) {
    return NavigationRail(
      minWidth: 60,
      backgroundColor: Theme.of(context).colorScheme.surface,
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
      selectedIndexValue = routesName.indexOf(
        "/${state.matchedLocation.split("/")[1]}",
      );
      // 这里对获取到的路径进行切片处理，并仅获取父页面的路径内容，确保 selectedIndexValue 的值符合预期
      // e.g. "/settings/about" => "/settings"
      if (selectedIndexValue >= desktopRailItems.length) {
        selectedIndexValue = 0;
        context.go(home);
      }
      ref.read(desktopSelectedIndex.notifier).state = selectedIndexValue;
    });
    return Scaffold(
      body: Row(
        children: [
          railNavigationBar(context, ref),
          Expanded(child: pageStructure(context, ref)),
        ],
      ),
    );
  }

  Widget railNavigationBar(BuildContext context, WidgetRef ref) {
    return NavigationRail(
      minWidth: 40,
      backgroundColor: Theme.of(context).colorScheme.surface,
      destinations: desktopRailItems,
      selectedIndex: ref.watch(desktopSelectedIndex),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(10),
            child: IconButton(
              onPressed: () {
                ref.read(functionPageShow.notifier).state = !ref
                    .read(functionPageShow.notifier)
                    .state;
              },
              icon: const Icon(Icons.menu),
            ),
          ),
        ),
      ),
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
          children: buildConsoleView(ref, Edit()),
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
    return shadcn.ShadcnLayer(
      theme: shadcn.ThemeData(
        colorScheme: Theme.of(context).brightness == Brightness.light
            ? shadcn.ColorSchemes.lightDefaultColor
            : shadcn.ColorSchemes.darkDefaultColor,
      ),
      child: shadcn.ResizablePanel.horizontal(
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

class ReplView extends StatelessWidget {
  const ReplView({super.key});

  @override
  Widget build(BuildContext context) {
    return TerminalView(repl, controller: replController);
  }
}

class QuestionView extends ConsumerWidget {
  const QuestionView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScrollConfiguration(
      behavior: NoScrollbarBehavior(),
      child: ListView.builder(
        addAutomaticKeepAlives: false,
        itemCount: ref.watch(diagnostics).length,
        itemBuilder: (context, index) {
          List<DiagnosticItem> nowDiagnostics = ref.watch(diagnostics);
          return ListTile(
            title: Text(nowDiagnostics[index].message),
            subtitle: Text(
              "[行 ${nowDiagnostics[index].range.start["line"] + 1}, 列 ${nowDiagnostics[index].range.start["character"] + 1}]",
            ),
          );
        },
      ),
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
