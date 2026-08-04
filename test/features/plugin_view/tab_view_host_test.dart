import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/renderer_registry.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/core/sdk/view_model_store_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/expansion_page.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_view_surface.dart';

const _pluginId = 'outline-plugin';
const _viewId = 'outline-plugin.outline';
const _sessionId = 'session-1';

const _plugin = Plugin(
  id: _pluginId,
  name: 'Outline Plugin',
  version: '1.0.0',
  author: 'PyriteIDE',
  description: 'tab view host fixture',
  type: PluginType.ui,
  status: PluginStatus.usable,
  declaredPermissions: {
    'tab': ['create'],
  },
  permissions: {
    'tab': ['create'],
  },
  platforms: ['windows'],
);

/// The sidebar placement of the same view, as PluginViewHost creates it.
const _sidebarInstance = ViewInstanceId(
  pluginId: _pluginId,
  sessionId: _sessionId,
  viewId: _viewId,
  instanceId: 'container:outline-plugin',
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
  _FixtureRunManagers(super.ref, PluginRunManager? manager) {
    state = manager == null ? {} : {_plugin: manager};
  }

  @override
  Future<void> start(Plugin plugin) async {}
}

PluginRunManager _manager() => PluginRunManager(
  transport: _IdleTransport(),
  assetsPath: '.',
  pluginId: _pluginId,
  pluginType: _plugin.type.name,
  pluginPermissions: _plugin.permissions,
  sessionId: _sessionId,
);

ProviderContainer _container({bool running = true}) => ProviderContainer(
  overrides: [
    pluginRunManagerProvider.overrideWith(
      (ref) => _FixtureRunManagers(ref, running ? _manager() : null),
    ),
  ],
);

Widget _app(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: SizedBox(height: 400, width: 600, child: child)),
      ),
    );

void main() {
  late ProviderContainer container;

  setUp(() => container = _container());
  tearDown(() => container.dispose());

  test(
    'a tab instance is distinct from the sidebar instance of the same view',
    () {
      final tabInstance = container
          .read(tabbedViewControllerProvider.notifier)
          .openPluginView(
            pluginId: _pluginId,
            viewId: _viewId,
            renderer: RendererTokens.outline,
          );

      expect(tabInstance, isNotNull);
      expect(tabInstance!.viewId, _viewId);
      expect(tabInstance, isNot(_sidebarInstance));
      expect(tabInstance.instanceId, isNot(_sidebarInstance.instanceId));
      expect(tabInstance.sessionId, _sessionId);
    },
  );

  test('two tabs of the same view get independent instances', () {
    final notifier = container.read(tabbedViewControllerProvider.notifier);
    final first = notifier.openPluginView(
      pluginId: _pluginId,
      viewId: _viewId,
      renderer: RendererTokens.outline,
    );
    final second = notifier.openPluginView(
      pluginId: _pluginId,
      viewId: _viewId,
      renderer: RendererTokens.outline,
    );

    expect(first, isNot(second));
    expect(container.read(tabbedViewControllerProvider).tabs.length, 3);
  });

  test('a stopped plugin gets no tab', () {
    final stopped = _container(running: false);
    addTearDown(stopped.dispose);

    final instance = stopped
        .read(tabbedViewControllerProvider.notifier)
        .openPluginView(
          pluginId: _pluginId,
          viewId: _viewId,
          renderer: RendererTokens.outline,
        );

    expect(instance, isNull);
    // Only the welcome tab remains.
    expect(stopped.read(tabbedViewControllerProvider).tabs.length, 1);
  });

  test('the expansion placement opens in the expansion controller', () {
    final instance = container
        .read(tabbedViewControllerProvider.notifier)
        .openPluginView(
          pluginId: _pluginId,
          viewId: _viewId,
          renderer: RendererTokens.outline,
          expansion: true,
        );

    expect(instance, isNotNull);
    expect(container.read(tabbedViewControllerProvider).tabs.length, 1);
    expect(container.read(expansionViewController).tabs.length, 2);
  });

  test(
    'the tab carries the plugin view discriminator and a synthetic path',
    () {
      final instance = container
          .read(tabbedViewControllerProvider.notifier)
          .openPluginView(
            pluginId: _pluginId,
            viewId: _viewId,
            renderer: RendererTokens.outline,
            title: 'Outline',
          )!;

      final tab = container.read(tabbedViewControllerProvider).tabs.last;
      final value = tab.value as TabDataValue;
      expect(value.isPluginView, isTrue);
      expect(value.pluginId, _pluginId);
      expect(value.viewId, _viewId);
      expect(value.viewInstanceId, instance.instanceId);
      expect(value.renderer, RendererTokens.outline);
      expect(
        value.filePath,
        'plugin://$_pluginId/$_viewId#${instance.instanceId}',
      );
      expect(tab.text, 'Outline');
    },
  );

  testWidgets('the tab content is the shared plugin view surface', (
    tester,
  ) async {
    final instance = container
        .read(tabbedViewControllerProvider.notifier)
        .openPluginView(
          pluginId: _pluginId,
          viewId: _viewId,
          renderer: RendererTokens.outline,
        )!;
    final content = container
        .read(tabbedViewControllerProvider)
        .tabs
        .last
        .content!;

    await tester.pumpWidget(_app(container, content));

    expect(find.byType(PluginViewSurface), findsOneWidget);
    final surface = tester.widget<PluginViewSurface>(
      find.byType(PluginViewSurface),
    );
    expect(surface.instance, instance);
    expect(surface.renderer, RendererTokens.outline);
  });

  testWidgets('snapshotting the tab instance leaves the sidebar untouched', (
    tester,
  ) async {
    final store = container.read(viewModelStoreProvider);
    store.installSnapshot(
      instance: _sidebarInstance,
      revision: 1,
      nodes: [
        {'id': 'n1', 'label': 'sidebar row'},
      ],
    );

    final tabInstance = container
        .read(tabbedViewControllerProvider.notifier)
        .openPluginView(
          pluginId: _pluginId,
          viewId: _viewId,
          renderer: RendererTokens.outline,
        )!;
    final content = container
        .read(tabbedViewControllerProvider)
        .tabs
        .last
        .content!;

    await tester.pumpWidget(
      _app(
        container,
        Column(
          children: [
            const Expanded(
              child: PluginViewSurface(
                instance: _sidebarInstance,
                renderer: RendererTokens.outline,
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );

    // The tab has no snapshot of its own yet, so it must still be waiting.
    expect(find.text('sidebar row'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    store.installSnapshot(
      instance: tabInstance,
      revision: 1,
      nodes: [
        {'id': 'n9', 'label': 'tab row'},
      ],
    );
    await tester.pump();

    expect(find.text('sidebar row'), findsOneWidget);
    expect(find.text('tab row'), findsOneWidget);
    expect(store.model(_sidebarInstance)!.nodes.single['label'], 'sidebar row');
    expect(store.model(tabInstance)!.nodes.single['label'], 'tab row');
  });

  test('closing the tab closes its instance and spares the sidebar', () {
    final store = container.read(viewModelStoreProvider);
    store.installSnapshot(
      instance: _sidebarInstance,
      revision: 1,
      nodes: [
        {'id': 'n1', 'label': 'sidebar row'},
      ],
    );

    final notifier = container.read(tabbedViewControllerProvider.notifier);
    final tabInstance = notifier.openPluginView(
      pluginId: _pluginId,
      viewId: _viewId,
      renderer: RendererTokens.outline,
    )!;
    store.installSnapshot(
      instance: tabInstance,
      revision: 1,
      nodes: [
        {'id': 'n9', 'label': 'tab row'},
      ],
    );

    final tabs = container.read(tabbedViewControllerProvider).tabs;
    final index = tabs.length - 1;
    notifier.afterTabClose(index, tabs[index]);

    expect(store.model(tabInstance), isNull);
    expect(store.model(_sidebarInstance), isNotNull);

    // A late patch to the closed instance must be rejected, not applied.
    final result = store.applyPatch(
      instance: tabInstance,
      baseRevision: 1,
      nextRevision: 2,
      ops: [
        const PatchOp(
          kind: PatchOpKind.update,
          id: 'n9',
          data: {'label': 'too late'},
        ),
      ],
    );
    expect(result.isOk, isFalse);
    expect(result.rejection, PatchRejection.noSnapshot);
  });
}
