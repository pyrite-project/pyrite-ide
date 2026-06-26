import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/services/plugins.dart';
import 'package:pyrite_ide/pages/editor/main.dart';
import 'package:pyrite_ide/pages/file/main.dart';
import 'package:pyrite_ide/pages/plugins/main.dart';
import 'package:pyrite_ide/pages/settings/about.dart';
import 'package:pyrite_ide/pages/settings/editor.dart';
import 'package:pyrite_ide/pages/settings/lsp.dart';
import 'package:pyrite_ide/pages/settings/main.dart';
import 'package:pyrite_ide/pages/settings/terminal.dart';
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
  observers: [routeObserver],
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
          path: '/plugins',
          pageBuilder: (context, state) =>
              topCustomTransitionPage(child: Plugins(), state: state),
          routes: [
            GoRoute(
              path: '/body',
              builder: (context, state) {
                final id = state.uri.queryParameters['id'];
                return PluginBody(pluginId: id!);
              },
            ),
          ],
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
              path: '/lsp',
              builder: (context, state) => const LspSettings(),
            ),
            GoRoute(
              path: "/style",
              builder: (context, state) => const StyleSettings(),
            ),
            GoRoute(
              path: '/terminal',
              builder: (context, state) => const TerminalSettings(),
            ),
            GoRoute(
              path: '/about',
              builder: (context, state) => const About(),
              routes: [
                GoRoute(
                  path: '/app_details',
                  builder: (context, state) => const AppDetails(),
                ),
                GoRoute(
                  path: "/feature/modern",
                  builder: (context, state) => const FeatureModern(),
                ),
                GoRoute(
                  path: "/feature/powerful",
                  builder: (context, state) => const FeaturePowerful(),
                ),
                GoRoute(
                  path: "/feature/cross_platform",
                  builder: (context, state) => const FeatureCrossPlatform(),
                ),
                GoRoute(
                  path: "/project",
                  builder: (context, state) => const AboutProject(),
                ),
              ],
            ),
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
const String plugins = '/plugins';
const String settings = '/settings';
const String edit = '/editor';

// 为 NavigationBar 提供
const List<String> routesName = [file, tools, plugins, settings, edit];
