import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/pages/settings/terminal.dart';

void main() {
  testWidgets('appearance selector reveals custom color controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TerminalSettings())),
    );

    expect(find.text('自定义终端颜色'), findsNothing);
    await tester.tap(find.text('自定义'));
    await tester.pump();

    expect(find.text('自定义终端颜色'), findsOneWidget);
    expect(find.text('终端预览'), findsNothing);

    final customColorsTitle = find.text('自定义终端颜色', skipOffstage: false);
    await tester.scrollUntilVisible(
      customColorsTitle,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(customColorsTitle);
    await tester.pumpAndSettle();

    expect(find.text('终端预览'), findsOneWidget);
  });

  testWidgets('terminal ligatures can be disabled', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TerminalSettings()),
      ),
    );

    expect(container.read(terminalLigatures), isTrue);
    await tester.tap(find.widgetWithText(SwitchListTile, '编程连体字'));
    await tester.pump();
    expect(container.read(terminalLigatures), isFalse);
  });

  testWidgets('custom terminal appearance exposes foreground and palette', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(terminalAppearance.notifier).state =
        TerminalAppearance.custom;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TerminalSettings()),
      ),
    );

    expect(find.text('终端外观'), findsOneWidget);
    expect(find.text('默认前景色'), findsNothing);

    await tester.tap(find.text('自定义终端颜色'));
    await tester.pumpAndSettle();

    expect(find.text('默认前景色'), findsOneWidget);
    expect(find.text('默认背景色'), findsOneWidget);
    expect(find.text('ANSI 颜色'), findsOneWidget);
  });

  testWidgets('reset restores every custom terminal color after confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(terminalAppearance.notifier).state =
        TerminalAppearance.custom;
    container.read(terminalCustomForeground.notifier).state = 0xFF123456;
    container.read(terminalCustomBackground.notifier).state = 0xFF654321;
    container.read(terminalCustomPalette.notifier).state = List<int>.generate(
      16,
      (index) => 0xFF000000 | index,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TerminalSettings()),
      ),
    );

    await tester.tap(find.text('自定义终端颜色'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '重置颜色'));
    await tester.pumpAndSettle();
    expect(find.text('重置自定义颜色？'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '重置颜色'));
    await tester.pumpAndSettle();

    expect(
      container.read(terminalCustomForeground),
      kDefaultTerminalCustomForeground,
    );
    expect(
      container.read(terminalCustomBackground),
      kDefaultTerminalCustomBackground,
    );
    expect(
      container.read(terminalCustomPalette),
      kDefaultTerminalCustomPalette,
    );
    expect(find.text('终端颜色已恢复默认值'), findsOneWidget);
  });

  testWidgets('custom terminal color layout fits a 375px viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(terminalAppearance.notifier).state =
        TerminalAppearance.custom;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TerminalSettings()),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    final customColorsTitle = find.text('自定义终端颜色');
    expect(customColorsTitle, findsOneWidget);
    await tester.tap(customColorsTitle);
    await tester.pumpAndSettle();
    expect(find.text('终端预览'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
