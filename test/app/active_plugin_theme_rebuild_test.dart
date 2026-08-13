import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';

void main() {
  testWidgets(
    'registering an unselected theme does not rebuild the app theme',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var builds = 0;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                builds++;
                final activeThemeId = ref.watch(activePluginThemeId);
                ref.watch(
                  dataRegistryProvider.select(
                    (registry) => activeThemeId == null
                        ? null
                        : registry.getThemeById(activeThemeId),
                  ),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(builds, 1);

      container.read(dataRegistryProvider).registerTheme('fixture', 'new', {
        'terminal.background': '#101820',
      });
      await tester.pump();

      expect(builds, 1);
    },
  );
}
