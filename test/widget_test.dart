import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/app/app.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/services/app.dart' as app;
import 'package:pyrite_ide/core/services/periodic_task/provider.dart';

void main() {
  // 路由表（lib/app/routes.dart）在 redirect 里直接读全局的 `container`，
  // 所以挂载整个 `PyriteIDE` 之前必须先给它赋值；否则 `PyriteIDE` 一构建
  // 就抛 "LateInitializationError: Field 'container' has not been initialized"。
  // 全局容器只能设置一次，因此所有用例共享一个。
  setUpAll(() => app.container = ProviderContainer());
  tearDownAll(() => app.container.dispose());

  // 为什么这些用例要在 macOS 这个 platform variant 下跑：
  //
  // `PyriteIDE` 用 `Platform.isMacOS || defaultTargetPlatform == macOS`
  // 决定是否挂 `MacOSMenu`。flutter_test 的 target platform 默认是 android，
  // 而宿主机是 macOS —— 于是 `Platform.isMacOS` 为真、菜单被挂上，但
  // `PlatformProvidedMenuItemType.about` 等系统菜单项在 android 目标上不存在，
  // 构建时抛 ArgumentError，连整个应用树（含欢迎页）都建不出来。
  //
  // 生产环境里 host 与 target 一致（macOS 桌面构建两者都是 macOS），不存在
  // 这个组合；因此这是**测试环境**的失真，而不是产品 bug。用
  // TargetPlatformVariant 让测试目标平台与宿主对齐——它会在每个用例前后
  // 自动设置/还原 debugDefaultTargetPlatformOverride，避免手工赋值触发
  // "ainfoundation debug variable was changed by the test" 断言。
  // lib/app/app.dart 不在本任务可改范围内，故在测试侧修正环境。
  Future<void> pumpApp(WidgetTester tester, {required bool onboarded}) async {
    app.container.read(app.welcomeCompletedProvider.notifier).state = onboarded;
    // 路由表也是全局的：每个用例都从首页重新开始。
    routes.go(welcome);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: app.container,
        child: const PyriteIDE(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 停掉应用注册的定期任务（串口轮询等）：容器在用例之间共享，但组件树
  /// 不是，否则计时器会活过测试并触发 "A Timer is still pending"。
  void stopPeriodicTasks() =>
      app.container.read(periodicTaskManagerProvider).dispose();

  testWidgets(
    'Pyrite IDE starts on the editor welcome page',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (WidgetTester tester) async {
      await pumpApp(tester, onboarded: true);

      // 期望值更新：欢迎页快速开始步骤的文案在 ff2f122
      //（"fix: optimize the display of the welcome page"）去掉了前缀序号，
      // '1. 打开保存脚本的项目文件夹' 变为 '打开保存脚本的项目文件夹'。这里
      // 跟随当前文案；断言本身的意图（欢迎页展示第一步引导）不变。
      expect(find.text('打开保存脚本的项目文件夹'), findsOneWidget);
      expect(find.text('打开项目文件夹'), findsOneWidget);
      expect(find.text('连接设备'), findsOneWidget);
      expect(find.text('新建文件'), findsOneWidget);
      stopPeriodicTasks();
    },
  );

  testWidgets(
    'mobile portrait navigation opens from drawer',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (WidgetTester tester) async {
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
    },
  );
}
