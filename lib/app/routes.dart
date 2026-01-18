import 'package:flutter/material.dart';
import 'package:pyrite_ide/pages/edit/main.dart';
import 'package:pyrite_ide/pages/file/main.dart';
import 'package:pyrite_ide/pages/home/main.dart';
import 'package:pyrite_ide/pages/settings/about.dart';
import 'package:pyrite_ide/pages/settings/main.dart';
import 'package:pyrite_ide/features/function_page.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/pages/tools/main.dart';

const String home = '/';
const String file = '/file';
const String tools = '/tools';
const String settings = '/settings';
const String edit = '/edit';
const String about = '/settings/about';

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
  routes: [
    ShellRoute(
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) =>
              topCustomTransitionPage(child: const Home(), state: state),
        ),
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
            GoRoute(path: '/about', builder: (context, state) => const About()),
          ],
        ),
        GoRoute(
          path: '/edit',
          pageBuilder: (context, state) =>
              topCustomTransitionPage(child: const Edit(), state: state),
        ),
      ],
      builder: (context, state, child) =>
          FunctionPage(state: state, child: child),
    ),
  ],
);

// 为 NavigationBar 提供
const List<String> routesName = [home, file, tools, settings, edit];
