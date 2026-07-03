import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/app/app.dart';

void main() {
  testWidgets('Pyrite IDE starts on the editor welcome page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: PyriteIDE()));
    await tester.pumpAndSettle();

    expect(find.text('1. 打开保存脚本的项目文件夹'), findsOneWidget);
    expect(find.text('打开项目文件夹'), findsOneWidget);
    expect(find.text('连接设备'), findsOneWidget);
    expect(find.text('新建文件'), findsOneWidget);
  });

  testWidgets('mobile portrait navigation opens from drawer', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: PyriteIDE()));
    await tester.pumpAndSettle();

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
  });
}
