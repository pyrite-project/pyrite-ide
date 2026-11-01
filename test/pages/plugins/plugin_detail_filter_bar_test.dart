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

/// A plugin whose manifest declares one boolean setting, so the detail page
/// renders the configuration section with its filter bar.
const _plugin = Plugin(
  id: 'settings-fixture',
  name: 'Settings Fixture',
  version: '1.0.0',
  author: 'PyriteIDE',
  description: 'Configuration filter bar fixture',
  type: PluginType.ui,
  status: PluginStatus.usable,
  manifest: PluginManifestV2(
    id: 'settings-fixture',
    name: 'Settings Fixture',
    version: '1.0.0',
    type: PluginType.ui,
    author: 'PyriteIDE',
    description: 'Configuration filter bar fixture',
    activationEvents: [],
    permissions: [],
    platforms: ['macos'],
    contributes: PluginContributions(
      navigationContainers: [
        PluginNavigationContainerContribution(
          id: 'settings-fixture',
          title: 'Settings Fixture',
          icon: PluginIconReference.material('extension_outlined'),
        ),
      ],
      views: [
        PluginViewContribution(
          id: 'settings-fixture.home',
          container: 'settings-fixture',
          title: 'Home',
          renderer: 'native.markdown',
        ),
      ],
      configuration: [
        PluginConfigurationContribution(
          id: 'settings-fixture.enabled',
          title: 'Enabled',
          type: 'boolean',
          defaultValue: false,
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
  testWidgets(
    'configuration filter bar keeps one height with and without text',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('pyrite-filter-bar');
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
        initialLocation: '/plugins/detail?id=settings-fixture',
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

      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      // The field's own container draws the box, so that is what must hold a
      // fixed height rather than the bare editable area inside it.
      final box = find
          .ancestor(of: field, matching: find.byType(Container))
          .first;
      final emptyHeight = tester.getSize(box).height;
      expect(emptyHeight, 36);

      await tester.enterText(field, '0');
      await tester.pumpAndSettle();

      // The clear button that appears while typing must not move the box.
      expect(tester.getSize(box).height, emptyHeight);
    },
  );
}
