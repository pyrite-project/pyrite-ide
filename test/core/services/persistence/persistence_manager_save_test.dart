import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/persistence/app_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/data_contributions_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/editor/tabs_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/file/project_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/function_page_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_manager.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:pyrite_ide/core/services/persistence/settings_persistence.dart';

class _CountingAppPersistence extends AppPersistence {
  int saves = 0;

  @override
  Future<bool> save(AppPersistedData data, {String? encoded}) async {
    saves++;
    return true;
  }
}

class _CountingSettingsPersistence extends SettingsPersistence {
  int saves = 0;

  @override
  Future<bool> save(SettingsPersistedData data, {String? encoded}) async {
    saves++;
    return true;
  }
}

class _CountingFunctionPagePersistence extends FunctionPagePersistence {
  int saves = 0;

  @override
  Future<bool> save(FunctionPagePersistedData data, {String? encoded}) async {
    saves++;
    return true;
  }
}

class _CountingProjectPersistence extends ProjectPersistence {
  int saves = 0;

  @override
  Future<bool> save(ProjectPersistedData data, {String? encoded}) async {
    saves++;
    return true;
  }
}

class _CountingTabsPersistence extends TabsPersistence {
  int saves = 0;

  @override
  Future<bool> save(TabsPersistedData data, {String? encoded}) async {
    saves++;
    return true;
  }
}

class _CountingDataContributionsPersistence
    extends DataContributionsPersistence {
  int saves = 0;

  @override
  Future<bool> save(
    List<DataContributionRecord> records, {
    String? encoded,
  }) async {
    saves++;
    return true;
  }
}

void main() {
  test('a navigation change rewrites only the changed store', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final app = _CountingAppPersistence();
    final settings = _CountingSettingsPersistence();
    final functionPage = _CountingFunctionPagePersistence();
    final project = _CountingProjectPersistence();
    final tabs = _CountingTabsPersistence();
    final contributions = _CountingDataContributionsPersistence();
    final manager = PersistenceManager(
      appPersistence: app,
      settingsPersistence: settings,
      functionPagePersistence: functionPage,
      projectPersistence: project,
      tabsPersistence: tabs,
      dataContributionsPersistence: contributions,
    );

    await manager.saveFromContainer(container);
    expect(app.saves, 1);
    expect(settings.saves, 1);
    expect(functionPage.saves, 1);
    expect(project.saves, 1);
    expect(tabs.saves, 1);
    expect(contributions.saves, 1);

    app.saves = 0;
    settings.saves = 0;
    functionPage.saves = 0;
    project.saves = 0;
    tabs.saves = 0;
    contributions.saves = 0;

    // A page switch changes only the navigation store.
    final current = container.read(desktopSelectedIndex);
    container.read(desktopSelectedIndex.notifier).state = current == 0 ? 1 : 0;
    await manager.saveFromContainer(container);

    expect(functionPage.saves, 1);
    expect(app.saves, 0);
    expect(settings.saves, 0);
    expect(project.saves, 0);
    expect(tabs.saves, 0);
    expect(contributions.saves, 0);

    // A second pass with the same payload writes nothing at all.
    functionPage.saves = 0;
    await manager.saveFromContainer(container);
    expect(functionPage.saves, 0);
  });
}
