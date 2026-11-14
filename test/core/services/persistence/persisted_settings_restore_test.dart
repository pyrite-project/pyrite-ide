import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/file_transfer_mode_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/persistence/app_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/data_contributions_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/editor/tabs_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/file/project_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/function_page_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_manager.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:pyrite_ide/core/services/persistence/settings_persistence.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';

// Riverpod marks ProviderContainer as sealed to discourage production
// subclasses. A local recording container is the only way to observe which
// providers the save path reads, and it is not passed outside this test.
// ignore: subtype_of_sealed_class
/// A container that remembers every provider the save path reads.
///
/// The recording is done at the container boundary. `ref.read` inside a
/// provider being built also routes through [ProviderContainer.read], so reads
/// that happen while another read is on the stack are skipped: only the
/// providers `saveFromContainer` asks for directly are captured.
class _RecordingContainer extends ProviderContainer {
  final List<ProviderListenable<Object?>> reads = [];
  int _readDepth = 0;

  @override
  Result read<Result>(ProviderListenable<Result> provider) {
    if (_readDepth == 0) reads.add(provider);
    _readDepth++;
    try {
      return super.read(provider);
    } finally {
      _readDepth--;
    }
  }
}

class _NoopAppPersistence extends AppPersistence {
  @override
  Future<void> save(AppPersistedData data) async {}
}

class _NoopSettingsPersistence extends SettingsPersistence {
  @override
  Future<void> save(SettingsPersistedData data) async {}
}

class _NoopFunctionPagePersistence extends FunctionPagePersistence {
  @override
  Future<void> save(FunctionPagePersistedData data) async {}
}

class _NoopProjectPersistence extends ProjectPersistence {
  @override
  Future<void> save(ProjectPersistedData data) async {}
}

class _NoopTabsPersistence extends TabsPersistence {
  @override
  Future<void> save(TabsPersistedData data) async {}
}

class _NoopDataContributionsPersistence extends DataContributionsPersistence {
  @override
  Future<void> save(List<DataContributionRecord> records) async {}
}

void main() {
  group('restoring persisted settings', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('restores the minimap and Chinese-to-Unicode switches', () {
      PersistenceManager().applyTo(
        container,
        PersistedData(editorMinimap: false, chineseToUnicodeConversion: false),
      );

      expect(container.read(editorMinimap), isFalse);
      expect(container.read(chineseToUnicodeConversion), isFalse);
    });

    test('restores settings from every persisted section', () {
      PersistenceManager().applyTo(
        container,
        PersistedData(
          themeMode: 'dark',
          themeStyle: 'compact',
          activeLocale: 'en-US',
          replMode: 'paste',
          fileTransferMode: 'streaming',
          hardwareResetStrategy: 'esp32',
          functionPageShow: false,
          consoleDockSide: 'right',
          terminalAppearance: 'light',
        ),
      );

      expect(container.read(themeMode), ThemeMode.dark);
      expect(container.read(themeStyle), ThemeStyle.compact);
      expect(container.read(activeLocaleProvider), 'en-US');
      expect(container.read(replModeProvider), ReplMode.paste);
      expect(
        container.read(fileTransferModeProvider),
        FileTransferMode.streaming,
      );
      expect(
        container.read(hardwareResetStrategyProvider),
        HardwareResetStrategy.esp32,
      );
      expect(container.read(functionPageShow), isFalse);
      expect(container.read(consoleDockSideProvider), PaneEdge.right);
      expect(container.read(terminalAppearance), TerminalAppearance.light);
    });
  });

  group('save subscriptions', () {
    test(
      'cover every provider saveFromContainer reads except editor tabs',
      () async {
        final container = _RecordingContainer();
        addTearDown(container.dispose);

        final manager = PersistenceManager(
          appPersistence: _NoopAppPersistence(),
          settingsPersistence: _NoopSettingsPersistence(),
          functionPagePersistence: _NoopFunctionPagePersistence(),
          projectPersistence: _NoopProjectPersistence(),
          tabsPersistence: _NoopTabsPersistence(),
          dataContributionsPersistence: _NoopDataContributionsPersistence(),
        );
        await manager.saveFromContainer(container);

        // The open tabs and their layout have their own change watchers, so they
        // are persisted without being settings subscriptions.
        final savedSettings = container.reads.toSet()
          ..remove(tabbedViewControllerProvider)
          ..remove(editorLayoutProvider);

        expect(
          persistedSettingProviders.toSet(),
          savedSettings,
          reason:
              'a provider saved by saveFromContainer but missing from '
              'persistedSettingProviders would not trigger an auto-save',
        );
      },
    );

    test('lists each persisted setting once', () {
      expect(
        persistedSettingProviders.toSet(),
        hasLength(persistedSettingProviders.length),
      );
    });
  });
}
