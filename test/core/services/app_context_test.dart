import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/app.dart';

/// Guards the invariant that makes the unsaved-changes prompt on window close
/// possible in the first place.
///
/// `appContext` is handed to code that has no BuildContext of its own -- the
/// window-close handler, the plugin SDK, the file provider -- and that code
/// calls `showDialog` on it. The app shell installs `appContext` from
/// `MaterialApp.router`'s `builder`, and that builder is an *ancestor* of the
/// Navigator. `Navigator.of` on it throws, so a dialog raised there never
/// appears and the awaited future never completes.
void main() {
  testWidgets('appContext resolves a Navigator once the router has built', (
    tester,
  ) async {
    final router = GoRouter(
      navigatorKey: appNavigatorKey,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
      ],
    );

    late BuildContext shellBuilderContext;
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder: (context, child) {
          shellBuilderContext = context;
          return child!;
        },
      ),
    );
    await tester.pumpAndSettle();

    // The premise of the bug: the shell's own context cannot push routes.
    expect(
      () => Navigator.of(shellBuilderContext),
      throwsA(isA<FlutterError>()),
      reason:
          'This assertion is what made the bug invisible: if the builder '
          'context ever did resolve a Navigator, the fix would be unnecessary.',
    );

    final context = appContext;
    expect(context, isNotNull);
    expect(
      () => Navigator.of(context!),
      returnsNormally,
      reason: 'appContext must be able to push a dialog route.',
    );
  });

  testWidgets('a dialog raised on appContext actually appears', (
    tester,
  ) async {
    final router = GoRouter(
      navigatorKey: appNavigatorKey,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    String? result;
    final pending = showDialog<String>(
      context: appContext!,
      builder: (dialogContext) => AlertDialog(
        content: const Text('unsaved'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: const Text('discard'),
          ),
        ],
      ),
    ).then((value) => result = value);

    await tester.pumpAndSettle();
    expect(find.text('unsaved'), findsOneWidget);

    await tester.tap(find.text('discard'));
    await tester.pumpAndSettle();
    await pending;

    expect(result, 'discard');
    expect(find.text('unsaved'), findsNothing);
  });
}