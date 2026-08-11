import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/sdk/activation_manager.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/core/sdk/view_model_store_provider.dart';
import 'package:pyrite_ide/core/services/persistence/plugin_persistence.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_view_surface.dart';
import 'package:pyrite_ide/pages/plugins/detail.dart';
import 'package:pyrite_ide/pages/plugins/main.dart';

const _plugin = Plugin(
  id: 'minimal-legacy-plugin',
  name: 'Minimal Legacy Plugin',
  version: '1.0.0',
  author: 'PyriteIDE',
  description: 'T00 legacy plugin lifecycle fixture',
  type: PluginType.ui,
  status: PluginStatus.usable,
  declaredPermissions: {
    'ui': ['view', 'navigate'],
    'settings': ['read'],
  },
  permissions: {
    'ui': ['view', 'navigate'],
    'settings': ['read'],
  },
  platforms: ['windows', 'linux', 'macos', 'android'],
  manifest: PluginManifestV2(
    id: 'minimal-legacy-plugin',
    name: 'Minimal Legacy Plugin',
    version: '1.0.0',
    type: PluginType.ui,
    author: 'PyriteIDE',
    description: 'T00 legacy plugin lifecycle fixture',
    activationEvents: ['onView:minimal-legacy-plugin.home'],
    permissions: ['ui.view', 'ui.navigate', 'settings.read'],
    platforms: ['windows', 'linux', 'macos', 'android'],
    contributes: PluginContributions(
      navigationContainers: [
        PluginNavigationContainerContribution(
          id: 'minimal-legacy-plugin',
          title: 'Minimal Legacy Plugin',
          icon: PluginIconReference.material('extension_outlined'),
        ),
      ],
      views: [
        PluginViewContribution(
          id: 'minimal-legacy-plugin.home',
          container: 'minimal-legacy-plugin',
          title: 'Home',
          renderer: 'native.markdown',
        ),
      ],
    ),
  ),
);

const _multiViewPlugin = Plugin(
  id: 'debug-enhanced',
  name: 'Debug Enhanced',
  version: '1.0.0',
  author: 'PyriteIDE',
  description: 'Multiple plugin views in one navigation container',
  type: PluginType.ui,
  status: PluginStatus.usable,
  declaredPermissions: {
    'ui': ['view'],
  },
  permissions: {
    'ui': ['view'],
  },
  platforms: ['windows', 'linux', 'macos', 'android'],
  manifest: PluginManifestV2(
    id: 'debug-enhanced',
    name: 'Debug Enhanced',
    version: '1.0.0',
    type: PluginType.ui,
    author: 'PyriteIDE',
    description: 'Multiple plugin views in one navigation container',
    activationEvents: [
      'onView:debug-enhanced.outline',
      'onView:debug-enhanced.device-variables',
    ],
    permissions: ['ui.view'],
    platforms: ['windows', 'linux', 'macos', 'android'],
    contributes: PluginContributions(
      navigationContainers: [
        PluginNavigationContainerContribution(
          id: 'debug-enhanced',
          title: 'Debug Enhanced',
        ),
      ],
      views: [
        PluginViewContribution(
          id: 'debug-enhanced.outline',
          container: 'debug-enhanced',
          title: 'Outline',
          renderer: 'native.outline',
          icon: PluginIconReference.material('account_tree_outlined'),
          order: 10,
        ),
        PluginViewContribution(
          id: 'debug-enhanced.device-variables',
          container: 'debug-enhanced',
          title: 'Device Variables',
          renderer: 'native.variableInspector',
          icon: PluginIconReference.material('data_object'),
          order: 20,
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

class _FixtureRunManagers extends PluginRunManagerNotifier {
  _FixtureRunManagers(super.ref, Plugin plugin, PluginRunManager manager) {
    state = {plugin: manager};
  }

  @override
  Future<void> start(Plugin plugin) {
    throw StateError('The fixture run manager must already be running');
  }
}

class _ActiveActivationManager extends ActivationManagerNotifier {
  _ActiveActivationManager(Plugin plugin)
    : super(startPlugin: (_) async => true, stopPlugin: (_) async {}) {
    state = {plugin.id: const ActivationRecord(state: ActivationState.active)};
  }
}

class _PluginViewHostToggle extends StatefulWidget {
  const _PluginViewHostToggle({super.key});

  @override
  State<_PluginViewHostToggle> createState() => _PluginViewHostToggleState();
}

class _PluginViewHostToggleState extends State<_PluginViewHostToggle> {
  bool _visible = true;

  void hide() => setState(() => _visible = false);

  @override
  Widget build(BuildContext context) => _visible
      ? const PluginViewHost(pluginId: 'missing', containerId: 'missing')
      : const SizedBox.shrink();
}

PluginRunManager _legacyManager(Plugin plugin) {
  return PluginRunManager(
    transport: _IdleTransport(),
    assetsPath: 'test/fixtures/plugins/minimal_legacy_plugin',
    pluginId: plugin.id,
    pluginType: plugin.type.name,
    pluginPermissions: plugin.permissions,
  );
}

ProviderScope _testApp(GoRouter router, {Plugin plugin = _plugin}) {
  final manager = _legacyManager(plugin);
  return ProviderScope(
    overrides: [
      pluginManagerProvider.overrideWith((ref) {
        final notifier = PluginManagerNotifier(ref);
        notifier.loadPersisted([PluginPersistedData.fromPlugin(plugin)]);
        return notifier;
      }),
      pluginRunManagerProvider.overrideWith(
        (ref) => _FixtureRunManagers(ref, plugin, manager),
      ),
      contributionRegistryProvider.overrideWith((ref) {
        final registry = ContributionRegistry(
          ref.read(contextKeyServiceProvider),
        );
        final manifest = plugin.manifest;
        if (manifest != null) registry.registerPlugin(manifest);
        return registry;
      }),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

GoRouter _router({
  ValueChanged<Uri>? onPluginDetail,
  ValueChanged<Uri>? onPluginView,
  String initialLocation = '/plugins',
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/plugins', builder: (context, state) => const Plugins()),
      GoRoute(
        path: '/plugins/detail',
        builder: (context, state) {
          onPluginDetail?.call(state.uri);
          return PluginDetailPage(pluginId: state.uri.queryParameters['id']!);
        },
      ),
      GoRoute(
        path: '/plugin-view',
        builder: (context, state) {
          onPluginView?.call(state.uri);
          return const Scaffold(body: Text('plugin view host'));
        },
      ),
    ],
  );
}

void main() {
  testWidgets('plugin view host can be disposed without reading a dead ref', (
    tester,
  ) async {
    final key = GlobalKey<_PluginViewHostToggleState>();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: _PluginViewHostToggle(key: key)),
      ),
    );

    key.currentState!.hide();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('plugin view host exposes every view in its container', (
    tester,
  ) async {
    final manager = _legacyManager(_multiViewPlugin);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluginManagerProvider.overrideWith((ref) {
            final notifier = PluginManagerNotifier(ref);
            notifier.loadPersisted([
              PluginPersistedData.fromPlugin(_multiViewPlugin),
            ]);
            return notifier;
          }),
          pluginRunManagerProvider.overrideWith(
            (ref) => _FixtureRunManagers(ref, _multiViewPlugin, manager),
          ),
          contributionRegistryProvider.overrideWith((ref) {
            final registry = ContributionRegistry(
              ref.read(contextKeyServiceProvider),
            );
            registry.registerPlugin(_multiViewPlugin.manifest!);
            return registry;
          }),
          activationManagerProvider.overrideWith(
            (ref) => _ActiveActivationManager(_multiViewPlugin),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PluginViewHost(
              pluginId: 'debug-enhanced',
              containerId: 'debug-enhanced',
              viewId: 'debug-enhanced.outline',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Outline'), findsOneWidget);
    expect(find.text('Device Variables'), findsOneWidget);
    expect(
      tester
          .widget<PluginViewSurface>(find.byType(PluginViewSurface))
          .instance
          .viewId,
      'debug-enhanced.outline',
    );

    await tester.tap(find.text('Device Variables'));
    await tester.pump();

    expect(
      tester
          .widget<PluginViewSurface>(find.byType(PluginViewSurface))
          .instance
          .viewId,
      'debug-enhanced.device-variables',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('plugin view tabs preserve inactive TextField state', (
    tester,
  ) async {
    final manager = _legacyManager(_multiViewPlugin);
    final store = ViewModelStore();
    final outlineInstance = ViewInstanceId(
      pluginId: _multiViewPlugin.id,
      sessionId: manager.sessionId,
      viewId: 'debug-enhanced.outline',
      instanceId: 'container:debug-enhanced',
    );
    final variablesInstance = ViewInstanceId(
      pluginId: _multiViewPlugin.id,
      sessionId: manager.sessionId,
      viewId: 'debug-enhanced.device-variables',
      instanceId: 'container:debug-enhanced',
    );
    store.installSnapshot(
      instance: outlineInstance,
      revision: 1,
      nodes: [
        {
          'type': 'TextField',
          'props': {'id': 'draft', 'value': ''},
        },
      ],
    );
    store.installSnapshot(
      instance: variablesInstance,
      revision: 1,
      nodes: [
        {
          'type': 'Text',
          'props': {'value': 'Device view'},
        },
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluginManagerProvider.overrideWith((ref) {
            final notifier = PluginManagerNotifier(ref);
            notifier.loadPersisted([
              PluginPersistedData.fromPlugin(_multiViewPlugin),
            ]);
            return notifier;
          }),
          pluginRunManagerProvider.overrideWith(
            (ref) => _FixtureRunManagers(ref, _multiViewPlugin, manager),
          ),
          contributionRegistryProvider.overrideWith((ref) {
            final registry = ContributionRegistry(
              ref.read(contextKeyServiceProvider),
            );
            registry.registerPlugin(_multiViewPlugin.manifest!);
            return registry;
          }),
          activationManagerProvider.overrideWith(
            (ref) => _ActiveActivationManager(_multiViewPlugin),
          ),
          viewModelStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PluginViewHost(
              pluginId: 'debug-enhanced',
              containerId: 'debug-enhanced',
              viewId: 'debug-enhanced.outline',
            ),
          ),
        ),
      ),
    );
    addTearDown(store.clear);
    await tester.pump();

    final fieldState = tester.state(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'unsaved draft');
    await tester.pump();

    await tester.tap(find.text('Device Variables'));
    await tester.pump();

    expect(find.text('Device view'), findsOneWidget);
    expect(fieldState.mounted, isTrue);
    final hiddenField = tester.widget<TextField>(
      find.byType(TextField, skipOffstage: false),
    );
    expect(hiddenField.controller?.text, 'unsaved draft');

    await tester.tap(find.text('Outline'));
    await tester.pump();

    expect(tester.state(find.byType(TextField)), same(fieldState));
    expect(find.text('unsaved draft'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('plugin list item opens the detail page, not plugin UI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Uri? detailUri;
    final router = _router(onPluginDetail: (uri) => detailUri = uri);
    addTearDown(router.dispose);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.onTap, isNotNull);
    tile.onTap!();
    await tester.pumpAndSettle();

    expect(find.byType(PluginDetailPage), findsOneWidget);
    expect(detailUri.toString(), '/plugins/detail?id=minimal-legacy-plugin');
  });

  testWidgets('detail page renders manifest metadata and contributions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = _router(
      initialLocation: '/plugins/detail?id=minimal-legacy-plugin',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    expect(find.text('minimal-legacy-plugin'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
    expect(find.text('PyriteIDE'), findsOneWidget);
    // Declared permissions are grouped by resource with sorted actions.
    expect(find.text('navigate, view'), findsOneWidget);
    expect(find.text('read'), findsOneWidget);
    // Contributions come from the registry, keyed by plugin.
    expect(find.text('Home (minimal-legacy-plugin.home)'), findsOneWidget);
    expect(
      find.text('Minimal Legacy Plugin (minimal-legacy-plugin)'),
      findsOneWidget,
    );
  });

  testWidgets('detail page reports a missing plugin instead of crashing', (
    tester,
  ) async {
    final router = _router(initialLocation: '/plugins/detail?id=nope');
    addTearDown(router.dispose);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    expect(find.byType(PluginDetailPage), findsOneWidget);
    expect(find.text('插件不存在'), findsOneWidget);
  });

  testWidgets('details menu action opens the detail page', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Uri? detailUri;
    final router = _router(onPluginDetail: (uri) => detailUri = uri);
    addTearDown(router.dispose);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(PluginDetailPage), findsOneWidget);
    expect(detailUri.toString(), '/plugins/detail?id=minimal-legacy-plugin');
  });

  testWidgets('detail page disable action moves the plugin to disabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = _router(
      initialLocation: '/plugins/detail?id=minimal-legacy-plugin',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.pause_circle_outline));
    await tester.pumpAndSettle();

    // The enable affordance replaces disable once the status flips.
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_outline), findsNothing);
  });

  testWidgets('detail page delete action asks for confirmation first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = _router(
      initialLocation: '/plugins/detail?id=minimal-legacy-plugin',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    // Cancelling leaves the plugin in place.
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(PluginDetailPage), findsOneWidget);
  });

  testWidgets('detail page open action routes to the plugin view host', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Uri? viewUri;
    final router = _router(
      initialLocation: '/plugins/detail?id=minimal-legacy-plugin',
      onPluginView: (uri) => viewUri = uri,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.open_in_new));
    await tester.pumpAndSettle();

    expect(viewUri, isNotNull);
    expect(viewUri!.path, '/plugin-view');
    expect(viewUri!.queryParameters['plugin'], 'minimal-legacy-plugin');
    expect(viewUri!.queryParameters['view'], 'minimal-legacy-plugin.home');
  });
}
