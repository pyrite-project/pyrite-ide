import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/pages/settings/editor.dart';

void main() {
  testWidgets('plugin editor theme disables editor theme selection', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(dataRegistryProvider).registerTheme('fixture', 'highlight', {
      'editor.keyword': '#112233',
    });
    container.read(activePluginThemeId.notifier).state = 'fixture::highlight';

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorSettings()),
      ),
    );

    final selector = tester.widget<ListTile>(
      find.byKey(const Key('editor-theme-selector')),
    );
    expect(selector.enabled, isFalse);
    expect(selector.onTap, isNull);
    expect(find.text('highlight'), findsOneWidget);
    expect(find.text('当前颜色主题已指定编辑器高亮配色。'), findsOneWidget);
  });

  testWidgets(
    'non-editor plugin themes do not disable editor theme selection',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(dataRegistryProvider).registerTheme(
        'fixture',
        'terminal',
        {'terminal.foreground': '#112233'},
      );
      container.read(activePluginThemeId.notifier).state = 'fixture::terminal';

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EditorSettings()),
        ),
      );

      final selector = tester.widget<ListTile>(
        find.byKey(const Key('editor-theme-selector')),
      );
      expect(selector.enabled, isTrue);
      expect(selector.onTap, isNotNull);
      expect(find.text('当前颜色主题已指定编辑器高亮配色。'), findsNothing);
    },
  );
}
