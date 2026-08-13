import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:tabbed_view/tabbed_view.dart';

class _LocalizedStateNotifier extends StateNotifier<List<String>> {
  _LocalizedStateNotifier(Ref ref)
    : super([translate(ref, I18nKey.terminalSessionTitle)]);
}

final _localizedStateProvider =
    StateNotifierProvider<_LocalizedStateNotifier, List<String>>(
      _LocalizedStateNotifier.new,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('theme contribution does not recreate localized service state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(_localizedStateProvider.notifier);
    final state = container.read(_localizedStateProvider);

    container.read(dataRegistryProvider).registerTheme('fixture', 'theme', {
      'terminal.background': '#101820',
    });

    expect(container.read(_localizedStateProvider.notifier), same(notifier));
    expect(container.read(_localizedStateProvider), same(state));
  });

  test('theme contribution preserves open editor tabs and controller', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(tabbedViewControllerProvider.notifier);
    final controller = container.read(tabbedViewControllerProvider);
    controller.addTab(
      TabData(text: 'fixture.py', content: const SizedBox.shrink()),
    );
    expect(controller.tabs.length, 2);

    container.read(dataRegistryProvider).registerTheme('fixture', 'theme', {
      'terminal.foreground': '#ffffff',
      'terminal.background': '#101820',
    });

    expect(
      container.read(tabbedViewControllerProvider.notifier),
      same(notifier),
    );
    expect(container.read(tabbedViewControllerProvider), same(controller));
    expect(
      container.read(tabbedViewControllerProvider).tabs.map((tab) => tab.text),
      contains('fixture.py'),
    );
  });
}
