import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/persistence/plugin_persistence.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';
import 'package:pyrite_ide/core/sdk/renderer_registry.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/core/sdk/view_model_store_provider.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_view_surface.dart';

const _instance = ViewInstanceId(
  pluginId: 'p',
  sessionId: 's',
  viewId: 'outline',
  instanceId: 'container:sidebar',
);

/// A second instance of the same view, as a tab host would create.
const _tabInstance = ViewInstanceId(
  pluginId: 'p',
  sessionId: 's',
  viewId: 'outline',
  instanceId: 'tab:1',
);

const _menuInstance = ViewInstanceId(
  pluginId: 'p',
  sessionId: 's',
  viewId: 'p.log',
  instanceId: 'container:p',
);

const _menuManifest = PluginManifestV2(
  id: 'p',
  name: 'Plugin',
  version: '1.0.0',
  type: PluginType.ui,
  activationEvents: ['onView:p.log', 'onCommand:p.copyLog'],
  permissions: ['ui.view'],
  platforms: ['windows'],
  contributes: PluginContributions(
    navigationContainers: [
      PluginNavigationContainerContribution(id: 'p', title: 'Plugin'),
    ],
    views: [
      PluginViewContribution(
        id: 'p.log',
        container: 'p',
        title: 'Runtime log',
        renderer: RendererTokens.virtualList,
      ),
    ],
    commands: [
      PluginCommandContribution(
        id: 'p.copyLog',
        title: 'Copy log',
        icon: PluginIconReference.material('content_copy'),
      ),
    ],
    menus: [
      PluginMenuContribution(
        location: 'view/title',
        view: 'p.log',
        command: 'p.copyLog',
      ),
    ],
  ),
);

class _ReentrantListenable extends ChangeNotifier {
  bool _notifyOnRemove = true;

  @override
  void removeListener(VoidCallback listener) {
    if (_notifyOnRemove) {
      _notifyOnRemove = false;
      listener();
    }
    super.removeListener(listener);
  }
}

class _ReentrantViewModelStore extends ViewModelStore {
  final _listenable = _ReentrantListenable();

  @override
  Listenable listenableFor(ViewInstanceId instance) => _listenable;
}

Widget _app(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: SizedBox(height: 400, width: 600, child: child)),
      ),
    );

void main() {
  late ProviderContainer container;
  late ViewModelStore store;

  setUp(() {
    container = ProviderContainer();
    store = container.read(viewModelStoreProvider);
  });
  tearDown(() => container.dispose());

  void installMenuPlugin() {
    container.read(pluginManagerProvider.notifier).loadPersisted([
      PluginPersistedData(id: 'p', name: 'Plugin', manifest: _menuManifest),
    ]);
  }

  testWidgets('shows a spinner until the first snapshot arrives', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        container,
        const PluginViewSurface(
          instance: _instance,
          renderer: RendererTokens.outline,
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('ignores a reentrant model callback while disposing', (
    tester,
  ) async {
    final reentrantStore = _ReentrantViewModelStore();
    final reentrantContainer = ProviderContainer(
      overrides: [viewModelStoreProvider.overrideWithValue(reentrantStore)],
    );
    addTearDown(reentrantContainer.dispose);

    await tester.pumpWidget(
      _app(
        reentrantContainer,
        const PluginViewSurface(
          instance: _instance,
          renderer: RendererTokens.outline,
        ),
      ),
    );
    await tester.pumpWidget(_app(reentrantContainer, const SizedBox.shrink()));

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the model through the renderer once snapshotted', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        container,
        const PluginViewSurface(
          instance: _instance,
          renderer: RendererTokens.outline,
        ),
      ),
    );

    store.installSnapshot(
      instance: _instance,
      revision: 1,
      nodes: [
        {'id': 'n1', 'label': 'Widget'},
        {'id': 'n2', 'label': 'build'},
      ],
    );
    await tester.pump();

    expect(find.text('Widget'), findsOneWidget);
    expect(find.text('build'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view/title commands render on a headerless native renderer', (
    tester,
  ) async {
    installMenuPlugin();
    await tester.pumpWidget(
      _app(
        container,
        const PluginViewSurface(
          instance: _menuInstance,
          renderer: RendererTokens.virtualList,
        ),
      ),
    );
    store.installSnapshot(
      instance: _menuInstance,
      revision: 1,
      nodes: [
        {'id': 'line-1', 'label': 'ready'},
      ],
    );
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Runtime log'), findsOneWidget);
    expect(find.byTooltip('Copy log'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view/title commands merge into a component tree AppBar', (
    tester,
  ) async {
    installMenuPlugin();
    await tester.pumpWidget(
      _app(
        container,
        const PluginViewSurface(
          instance: _menuInstance,
          renderer: RendererTokens.form,
        ),
      ),
    );
    store.installSnapshot(
      instance: _menuInstance,
      revision: 1,
      nodes: [
        {
          'type': 'Scaffold',
          'children': [
            {
              'type': 'AppBar',
              'props': {'title': 'Plugin page'},
            },
            {
              'type': 'Text',
              'props': {'value': 'Body'},
            },
          ],
        },
      ],
    );
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Plugin page'), findsOneWidget);
    expect(find.byTooltip('Copy log'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view/title commands add an AppBar to a component-only view', (
    tester,
  ) async {
    installMenuPlugin();
    await tester.pumpWidget(
      _app(
        container,
        const PluginViewSurface(
          instance: _menuInstance,
          renderer: RendererTokens.form,
        ),
      ),
    );
    store.installSnapshot(
      instance: _menuInstance,
      revision: 1,
      nodes: [
        {
          'type': 'Text',
          'props': {'value': 'Component body'},
        },
      ],
    );
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Runtime log'), findsOneWidget);
    expect(find.text('Component body'), findsOneWidget);
    expect(find.byTooltip('Copy log'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a patch repaints the surface without a manual rebuild', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        container,
        const PluginViewSurface(
          instance: _instance,
          renderer: RendererTokens.outline,
        ),
      ),
    );
    store.installSnapshot(
      instance: _instance,
      revision: 1,
      nodes: [
        {'id': 'n1', 'label': 'before'},
      ],
    );
    await tester.pump();
    expect(find.text('before'), findsOneWidget);

    // Applying a patch must drive the repaint through the store's listenable.
    final result = store.applyPatch(
      instance: _instance,
      baseRevision: 1,
      nextRevision: 2,
      ops: [
        const PatchOp(
          kind: PatchOpKind.update,
          id: 'n1',
          data: {'label': 'after'},
        ),
      ],
    );
    expect(result.isOk, isTrue);
    await tester.pump();

    expect(find.text('after'), findsOneWidget);
    expect(find.text('before'), findsNothing);
  });

  testWidgets('a rejected patch does not change what is on screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        container,
        const PluginViewSurface(
          instance: _instance,
          renderer: RendererTokens.outline,
        ),
      ),
    );
    store.installSnapshot(
      instance: _instance,
      revision: 1,
      nodes: [
        {'id': 'n1', 'label': 'stable'},
      ],
    );
    await tester.pump();

    // A revision gap must be rejected and leave the view untouched.
    final result = store.applyPatch(
      instance: _instance,
      baseRevision: 7,
      nextRevision: 8,
      ops: const [],
    );
    expect(result.isOk, isFalse);
    await tester.pump();
    expect(find.text('stable'), findsOneWidget);
  });

  testWidgets('renders a free-form component tree when the plugin sends one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        container,
        const PluginViewSurface(
          instance: _instance,
          renderer: RendererTokens.outline,
        ),
      ),
    );
    store.installSnapshot(
      instance: _instance,
      revision: 1,
      nodes: [
        {
          'id': 'root',
          'component': {
            'type': 'Column',
            'children': [
              {
                'type': 'Text',
                'props': {'value': 'composed by the plugin'},
              },
              {
                'type': 'Button',
                'props': {'id': 'go', 'label': 'Run'},
              },
            ],
          },
        },
      ],
    );
    await tester.pump();

    expect(find.text('composed by the plugin'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the SDK direct component snapshot shape', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        container,
        const PluginViewSurface(
          instance: _instance,
          renderer: RendererTokens.outline,
        ),
      ),
    );
    store.installSnapshot(
      instance: _instance,
      revision: 1,
      nodes: [
        {
          'type': 'Button',
          'props': {'id': 'direct', 'label': 'Direct component'},
        },
      ],
    );
    await tester.pump();

    expect(find.text('Direct component'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a malformed component tree renders an error boundary', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        container,
        const PluginViewSurface(
          instance: _instance,
          renderer: RendererTokens.outline,
        ),
      ),
    );
    store.installSnapshot(
      instance: _instance,
      revision: 1,
      nodes: [
        {
          'id': 'root',
          'component': {'type': 'Frobnicator'},
        },
      ],
    );
    await tester.pump();

    expect(find.textContaining('unknown component'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a closed view reports that the plugin closed it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        container,
        const PluginViewSurface(
          instance: _instance,
          renderer: RendererTokens.outline,
        ),
      ),
    );
    store.installSnapshot(
      instance: _instance,
      revision: 1,
      nodes: [
        {'id': 'n1', 'label': 'x'},
      ],
    );
    await tester.pump();
    store.setState(_instance, ViewState.disconnected);
    await tester.pump();

    expect(find.textContaining('closed this view'), findsOneWidget);
  });

  testWidgets('two instances of one view stay independent', (tester) async {
    // This is the property that lets a tab and the sidebar host the same view
    // without sharing state.
    await tester.pumpWidget(
      _app(
        container,
        const Column(
          children: [
            Expanded(
              child: PluginViewSurface(
                instance: _instance,
                renderer: RendererTokens.outline,
              ),
            ),
            Expanded(
              child: PluginViewSurface(
                instance: _tabInstance,
                renderer: RendererTokens.outline,
              ),
            ),
          ],
        ),
      ),
    );

    store.installSnapshot(
      instance: _instance,
      revision: 1,
      nodes: [
        {'id': 'n1', 'label': 'sidebar row'},
      ],
    );
    await tester.pump();

    // Only the sidebar instance has data; the tab instance still waits.
    expect(find.text('sidebar row'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    store.installSnapshot(
      instance: _tabInstance,
      revision: 1,
      nodes: [
        {'id': 'n9', 'label': 'tab row'},
      ],
    );
    await tester.pump();

    expect(find.text('sidebar row'), findsOneWidget);
    expect(find.text('tab row'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
