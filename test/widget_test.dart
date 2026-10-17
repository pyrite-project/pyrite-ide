import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/app/app.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/services/app.dart' as app;
import 'package:pyrite_ide/core/services/periodic_task/provider.dart';

void main() {
  // The app reads the container `main` builds -- the router's redirect, for
  // one -- so the tests mount the app on that container rather than their own.
  // It can only be set once, so the tests share it.
  setUpAll(() => app.container = ProviderContainer());
  tearDownAll(() => app.container.dispose());

  Future<void> pumpApp(WidgetTester tester, {required bool onboarded}) async {
    app.container.read(app.welcomeCompletedProvider.notifier).state = onboarded;
    // The router is global as well: start every test from the first page.
    routes.go(welcome);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: app.container,
        child: const PyriteIDE(),
      ),
    );
    await tester.pumpAndSettle();
    // Lets the environment notifier's debounced layout report go out, so no
    // timer outlives the test.
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Stops the app's periodic tasks -- the serial port poll -- which would
  /// otherwise outlive the widget tree: the container is shared, the tree is
  /// not.
  void stopPeriodicTasks() =>
      app.container.read(periodicTaskManagerProvider).dispose();

  testWidgets('a first launch starts on the onboarding page', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, onboarded: false);

    expect(find.text('欢迎使用 PyriteIDE'), findsOneWidget);
    expect(find.text('开始'), findsOneWidget);
    stopPeriodicTasks();
  });

  testWidgets('Pyrite IDE starts on the editor welcome page', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, onboarded: true);

    expect(find.text('打开保存脚本的项目文件夹'), findsOneWidget);
    expect(find.text('打开项目文件夹'), findsOneWidget);
    expect(find.text('连接设备'), findsOneWidget);
    expect(find.text('新建文件'), findsOneWidget);
    stopPeriodicTasks();
  });

  testWidgets('mobile portrait navigation opens from drawer', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester, onboarded: true);

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('打开菜单'), findsOneWidget);

    await tester.tap(find.byTooltip('打开菜单'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDrawer), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('Git'), findsAtLeastNWidgets(1));
    expect(find.text('编辑器'), findsOneWidget);

    await tester.tap(find.text('Git').last);
    await tester.pumpAndSettle();

    expect(find.text('没有检测到 Git 仓库'), findsOneWidget);
    stopPeriodicTasks();
  });
}
