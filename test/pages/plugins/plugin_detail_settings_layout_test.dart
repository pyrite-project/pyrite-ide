import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_config_store.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/persistence/plugin_persistence.dart';
import 'package:pyrite_ide/pages/plugins/detail.dart';

const String _pluginId = 'settings-layout-fixture';
const String _baseUrlId = '$_pluginId.base_url';
const String _maxTokensId = '$_pluginId.max_tokens';
const String _baseUrl = 'https://api.example.com/v1';

/// A plugin declaring one string and one integer setting, so a row can be
/// inspected in both layouts.
const _plugin = Plugin(
  id: _pluginId,
  name: 'Settings Layout Fixture',
  version: '1.0.0',
  author: 'PyriteIDE',
  description: 'Responsive configuration fixture',
  type: PluginType.ui,
  status: PluginStatus.usable,
  manifest: PluginManifestV2(
    id: _pluginId,
    name: 'Settings Layout Fixture',
    version: '1.0.0',
    type: PluginType.ui,
    author: 'PyriteIDE',
    description: 'Responsive configuration fixture',
    activationEvents: [],
    permissions: [],
    platforms: ['macos'],
    contributes: PluginContributions(
      navigationContainers: [
        PluginNavigationContainerContribution(
          id: _pluginId,
          title: 'Settings Layout Fixture',
          icon: PluginIconReference.material('extension_outlined'),
        ),
      ],
      views: [
        PluginViewContribution(
          id: '$_pluginId.home',
          container: _pluginId,
          title: 'Home',
          renderer: 'native.markdown',
        ),
      ],
      configuration: [
        PluginConfigurationContribution(
          id: _baseUrlId,
          title: 'API Base URL',
          description: 'OpenAI-compatible endpoint',
          type: 'string',
          defaultValue: _baseUrl,
        ),
        PluginConfigurationContribution(
          id: _maxTokensId,
          title: 'Max Tokens',
          type: 'integer',
          defaultValue: 4096,
          order: 1,
        ),
      ],
    ),
  ),
);

class _IdleTransport implements PluginTransport {
  @override
  String get type => 'Fake';

  @override
  Stream<Uint8List> get messages => const Stream.empty();

  @override
  Stream<PluginTransportState> get states => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> send(Uint8List message) async {}

  @override
  Future<void> close() async {}
}

void main() {
  /// Pumps the detail page at [size] and returns the store it writes to.
  Future<PluginConfigStore> pumpDetail(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('pyrite-settings-layout');
    addTearDown(() => temp.deleteSync(recursive: true));
    final registry = ContributionRegistry(ContextKeyService());
    registry.registerPlugin(_plugin.manifest!);
    final store = PluginConfigStore(
      registry: registry,
      emit: (_, _) {},
      dataDirectoryForPlugin: (pluginId) =>
          Directory('${temp.path}/$pluginId').path,
    );
    final router = GoRouter(
      initialLocation: '/plugins/detail?id=$_pluginId',
      routes: [
        GoRoute(
          path: '/plugins/detail',
          builder: (context, state) =>
              PluginDetailPage(pluginId: state.uri.queryParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluginManagerProvider.overrideWith((ref) {
            final notifier = PluginManagerNotifier(ref);
            notifier.loadPersisted([PluginPersistedData.fromPlugin(_plugin)]);
            return notifier;
          }),
          pluginRunManagerProvider.overrideWith(
            (ref) => PluginRunManagerNotifier(ref)
              ..state = {
                _plugin: PluginRunManager(
                  transport: _IdleTransport(),
                  assetsPath: 'test/fixtures/plugins',
                  pluginId: _plugin.id,
                  pluginType: _plugin.type.name,
                  pluginPermissions: _plugin.permissions,
                ),
              },
          ),
          contributionRegistryProvider.overrideWith((ref) => registry),
          pluginConfigStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    // The store reads its data directory with real file IO, which does not
    // drive frames; give the load future a real gap to complete in.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('a wide row edits its value in place, without a dialog', (
    tester,
  ) async {
    final store = await pumpDetail(tester, const Size(1000, 900));

    final field = find.widgetWithText(TextField, _baseUrl);
    expect(field, findsOneWidget);
    // The whole point of the wide layout: no button stands between the user
    // and the value.
    expect(find.widgetWithIcon(IconButton, Icons.edit_outlined), findsNothing);

    await tester.enterText(field, 'https://api.example.com/v2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(
      await store.get(_pluginId, _baseUrlId),
      'https://api.example.com/v2',
    );
  });

  testWidgets('a wide row keeps an invalid number out of the store', (
    tester,
  ) async {
    final store = await pumpDetail(tester, const Size(1000, 900));

    final field = find.widgetWithText(TextField, '4096');
    expect(field, findsOneWidget);

    await tester.enterText(field, 'not a number');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(await store.get(_pluginId, _maxTokensId), 4096);
  });

  testWidgets('a narrow row offers a small edit button that opens a dialog', (
    tester,
  ) async {
    await pumpDetail(tester, const Size(420, 1200));

    // Only the search box remains a field; the values moved behind buttons.
    expect(find.byType(TextField), findsOneWidget);
    final edit = find.widgetWithIcon(IconButton, Icons.edit_outlined);
    expect(edit, findsWidgets);

    await tester.ensureVisible(edit.first);
    await tester.pumpAndSettle();
    await tester.tap(edit.first);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
