import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/pages/settings/terminal.dart';

void main() {
  testWidgets('plugin terminal theme disables only terminal color settings', (
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
    container.read(dataRegistryProvider).registerTheme('fixture', 'terminal', {
      'terminal.ansi': List<String>.filled(16, '#112233'),
    });
    container.read(activePluginThemeId.notifier).state = 'fixture::terminal';

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TerminalSettings()),
      ),
    );

    final selector = tester.widget<SegmentedButton<TerminalAppearance>>(
      find.byType(SegmentedButton<TerminalAppearance>),
    );
    final customColors = tester.widget<ExpansionTile>(
      find.byKey(const Key('terminal-custom-colors-expansion')),
    );
    expect(selector.onSelectionChanged, isNull);
    expect(customColors.enabled, isFalse);
    expect(find.text('当前颜色主题已指定终端配色。'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(SwitchListTile, '编程连体字'));
    await tester.tap(find.widgetWithText(SwitchListTile, '增强低对比度文字'));
    await tester.pump();

    expect(container.read(terminalLigatures), isFalse);
    expect(container.read(terminalMinimumContrast), isTrue);
  });

  testWidgets('plugin UI colors do not disable terminal color settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(dataRegistryProvider).registerTheme('fixture', 'ui-only', {
      'color.primary': '#112233',
    });
    container.read(activePluginThemeId.notifier).state = 'fixture::ui-only';

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TerminalSettings()),
      ),
    );

    final selector = tester.widget<SegmentedButton<TerminalAppearance>>(
      find.byType(SegmentedButton<TerminalAppearance>),
    );
    expect(selector.onSelectionChanged, isNotNull);
    expect(find.text('当前颜色主题已指定终端配色。'), findsNothing);
  });
}
