import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/core/constants/navigation_bar.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/pages/edit/main.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

int selectedIndexValue = 0;
final StateProvider<int> desktopSelectedIndex = StateProvider<int>(
  (ref) => selectedIndexValue,
);
final StateProvider<int> mobileSelectedIndex = StateProvider<int>(
  (ref) => selectedIndexValue,
);
final StateProvider<int> tabletSelectedIndex = StateProvider<int>(
  (ref) => selectedIndexValue,
);
final StateProvider<bool> functionPageState = StateProvider<bool>(
  (ref) => true,
);

class MobileView extends ConsumerWidget {
  const MobileView({super.key, required this.child, required this.state});

  final Widget child;
  final GoRouterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      bottomNavigationBar: bottomNavigationBar(context, ref),
      body: child,
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
    return Scaffold(
      body: Row(
        children: [
          railNavigationBar(context, ref),
          const VerticalDivider(),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget railNavigationBar(BuildContext context, WidgetRef ref) {
    return NavigationRail(
      labelType: NavigationRailLabelType.all,
      destinations: tabletRailItems,
      selectedIndex: ref.watch(tabletSelectedIndex),
      leading: SizedBox(
        width: 60,
        height: 60,
        child: Card(
          elevation: 0,
          color: Theme.of(context).dividerTheme.color,
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Image.asset(
              "assets/icons/app_icon_100px.png",
              width: 40,
              height: 40,
            ),
          ),
        ),
      ),
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
          const VerticalDivider(),
          Expanded(child: functionPage(context, ref)),
        ],
      ),
    );
  }

  Widget railNavigationBar(BuildContext context, WidgetRef ref) {
    return NavigationRail(
      labelType: NavigationRailLabelType.all,
      destinations: desktopRailItems,
      selectedIndex: ref.watch(desktopSelectedIndex),
      leading: SizedBox(
        width: 60,
        height: 60,
        child: Card(
          elevation: 0,
          color: Theme.of(context).dividerTheme.color,
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Image.asset(
              "assets/icons/app_icon_100px.png",
              width: 40,
              height: 40,
            ),
          ),
        ),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(10),
            child: IconButton(
              onPressed: () {
                ref.read(functionPageState.notifier).state = !ref
                    .read(functionPageState.notifier)
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

  Widget functionPage(BuildContext context, WidgetRef ref) {
    if (ref.watch(functionPageState)) {
      return shadcn.ShadcnLayer(
        theme: shadcn.ThemeData(colorScheme: shadcn.ColorSchemes.darkOrange),
        child: shadcn.ResizablePanel.horizontal(
          draggerBuilder: (context) {
            return shadcn.HorizontalResizableDragger();
          },
          children: [
            shadcn.ResizablePane.flex(
              initialFlex: 2,
              minSize: 200,
              child: child,
            ),
            shadcn.ResizablePane.flex(
              initialFlex: 2,
              minSize: 300,
              child: Edit(),
            ),
          ],
        ),
      );
    } else {
      return Edit();
    }
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

class FunctionPage extends StatelessWidget {
  const FunctionPage({super.key, required this.child, required this.state});

  final Widget child;
  final GoRouterState state;

  @override
  Widget build(BuildContext context) {
    if (ResponsiveBreakpoints.of(context).isDesktop) {
      return DesktopView(state: state, child: child);
    } else if (ResponsiveBreakpoints.of(context).isTablet) {
      return TabletView(state: state, child: child);
    } else {
      return MobileView(state: state, child: child);
    }
  }
}
