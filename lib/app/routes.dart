import 'package:flutter/material.dart';
import 'package:pyrite_ide/pages/edit/main.dart';
import 'package:pyrite_ide/pages/file/main.dart';
import 'package:pyrite_ide/pages/settings/about.dart';
import 'package:pyrite_ide/pages/settings/editor.dart';
import 'package:pyrite_ide/pages/settings/main.dart';
import 'package:pyrite_ide/features/function_page.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/pages/settings/style.dart';
import 'package:pyrite_ide/pages/tools/main.dart';
import 'package:responsive_framework/responsive_framework.dart';

CustomTransitionPage topCustomTransitionPage({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
        child: child,
      );
    },
  );
}

GoRouter routes = GoRouter(
  redirect: (context, state) {
    if (state.matchedLocation == "/") {
      if (ResponsiveBreakpoints.of(context).isDesktop) {
        return "/file";
      } else {
        return "/editor";
      }
    }
    return null;
  },
  routes: [
    ShellRoute(
      routes: [
        GoRoute(
          path: '/file',
          pageBuilder: (context, state) => topCustomTransitionPage(
            child: const ProjectFiles(),
            state: state,
          ),
        ),
        GoRoute(
          path: '/tools',
          pageBuilder: (context, state) =>
              topCustomTransitionPage(child: const Tools(), state: state),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              topCustomTransitionPage(child: const Settings(), state: state),
          routes: [
            GoRoute(
              path: '/editor',
              builder: (context, state) => const EditorSettings(),
            ),
            GoRoute(
              path: "/style",
              builder: (context, state) => const StyleSettings(),
            ),
            GoRoute(path: '/about', builder: (context, state) => const About()),
          ],
        ),
        GoRoute(
          path: '/editor',
          pageBuilder: (context, state) =>
              topCustomTransitionPage(child: const Editor(), state: state),
        ),
      ],
      builder: (context, state, child) =>
          FunctionPage(state: state, child: child),
    ),
  ],
);

// 地址别名
const String file = '/file';
const String tools = '/tools';
const String settings = '/settings';
const String edit = '/editor';

// 为 NavigationBar 提供
const List<String> routesName = [file, tools, settings, edit];
