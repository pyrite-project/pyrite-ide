import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/sdk/api/tab.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/permissions.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/renderer_registry.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/core/sdk/view_model_store_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';

const _pluginId = 'tabbed-plugin';
const _viewId = 'tabbed-plugin.outline';
const _sessionId = 'session-1';

const _contributions = PluginContributions(
  navigationContainers: [
    PluginNavigationContainerContribution(
      id: _pluginId,
      title: 'Tabbed Plugin',
      icon: PluginIconReference.material('extension_outlined'),
    ),
  ],
  views: [
    PluginViewContribution(
      id: _viewId,
      container: _pluginId,
      title: 'Outline',
      renderer: RendererTokens.outline,
    ),
  ],
);

const _manifest = PluginManifestV2(
  id: _pluginId,
  name: 'Tabbed Plugin',
  version: '1.0.0',
  type: PluginType.ui,
  platforms: ['windows'],
  permissions: ['tab.create'],
  contributes: _contributions,
);

const _plugin = Plugin(
  id: _pluginId,
  name: 'Tabbed Plugin',
  version: '1.0.0',
  author: 'PyriteIDE',
  description: 'sdk.tab.create_view fixture',
  type: PluginType.ui,
  status: PluginStatus.usable,
  declaredPermissions: {
    'tab': ['create'],
  },
  permissions: {
    'tab': ['create'],
  },
  platforms: ['windows'],
  manifest: _manifest,
);

class _Transport implements PluginTransport {
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  final StreamController<PluginTransportState> _states =
      StreamController<PluginTransportState>.broadcast();
  final List<Map<String, dynamic>> responses = [];

  @override
  String get type => 'Fake';
  @override
  Stream<Uint8List> get messages => _messages.stream;
  @override
  Stream<PluginTransportState> get states => _states.stream;

  @override
  Future<void> start() async {
    _states.add(PluginTransportState.connecting);
    _states.add(PluginTransportState.ready);
  }

  @override
  Future<void> send(Uint8List message) async {
    final envelope = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
    switch (envelope['type']) {
      case IdeCommands.initialize:
        _reply(SdkCommands.initialize, envelope, 1, {
          'protocolVersion': 1,
          'capabilities': ['sdk.v1'],
        });
      case IdeCommands.initialized:
        _reply(SdkCommands.ready, envelope, 2, {
          'capabilities': ['sdk.v1'],
        });
      default:
        responses.add(envelope);
    }
  }

  void _reply(String type, Map<String, dynamic> req, int seq, Map payload) {
    inject(
      makeEnvelope(
        type: type,
        pluginId: req['pluginId'] as String,
        sessionId: req['sessionId'] as String,
        generation: req['generation'] as int,
        replyTo: req['requestId'] as String,
        sequence: seq,
        payload: Map<String, dynamic>.from(payload),
      ),
    );
  }

  void inject(Map<String, dynamic> envelope) {
    _messages.add(Uint8List.fromList(utf8.encode(jsonEncode(envelope))));
  }

  @override
  Future<void> close() async {
    await _messages.close();
    await _states.close();
  }
}

class _FixtureRunManagers extends PluginRunManagerNotifier {
  _FixtureRunManagers(super.ref, PluginRunManager? manager) {
    state = manager == null ? {} : {_plugin: manager};
  }

  @override
  Future<void> start(Plugin plugin) async {}
}

/// Inbound sequence numbers must strictly increase or the manager drops the
/// frame as a duplicate.
int _sequence = 100;

Future<Map<String, dynamic>> _request(
  PluginRunManager manager,
  _Transport transport,
  Map<String, dynamic> payload,
) async {
  final envelope = makeEnvelope(
    type: SdkTabCommands.createView,
    payload: payload,
    pluginId: manager.pluginId,
    sessionId: manager.sessionId,
    generation: manager.generation,
    sequence: ++_sequence,
  );
  transport.inject(envelope);
  // Handlers reply synchronously once the injected frame is dispatched; poll
  // the recorded responses rather than racing a broadcast stream listener.
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final match = transport.responses
        .where((e) => e['replyTo'] == envelope['requestId'])
        .firstOrNull;
    if (match != null) return match;
  }
  throw StateError('No response for ${SdkTabCommands.createView}');
}

Future<
  ({
    ProviderContainer container,
    _Transport transport,
    PluginRunManager manager,
  })
>
_harness({
  bool running = true,
  Map<String, List<String>> permissions = const {
    'tab': ['create'],
  },
}) async {
  final transport = _Transport();
  final manager = PluginRunManager(
    transport: transport,
    assetsPath: '.',
    pluginId: _pluginId,
    pluginType: _plugin.type.name,
    pluginPermissions: permissions,
    sessionId: _sessionId,
    generation: 1,
  );
  final container = ProviderContainer(
    overrides: [
      pluginRunManagerProvider.overrideWith(
        (ref) => _FixtureRunManagers(ref, running ? manager : null),
      ),
      contributionRegistryProvider.overrideWith((ref) {
        final registry = ContributionRegistry(
          ref.read(contextKeyServiceProvider),
        );
        registry.registerPlugin(_manifest);
        return registry;
      }),
    ],
  );
  container.read(sdkTabProvider).bind(manager);
  await manager.connect();
  return (container: container, transport: transport, manager: manager);
}

void main() {
  test('sdk.tab.create_view requires the same permission as its siblings', () {
    expect(
      Permissions.getRequirement(SdkTabCommands.createView),
      Permissions.getRequirement(SdkTabCommands.createFile),
    );
    expect(Permissions.isPublic(SdkTabCommands.createView), isFalse);
  });

  test('creating a view tab replies with the allocated instance', () async {
    final harness = await _harness();
    addTearDown(harness.container.dispose);

    final response = await _request(harness.manager, harness.transport, {
      'viewId': _viewId,
    });

    expect(response['type'], 'sdk.response.ok');
    final instance = response['payload']['data'] as Map<String, dynamic>;
    expect(instance['pluginId'], _pluginId);
    expect(instance['sessionId'], _sessionId);
    expect(instance['viewId'], _viewId);
    expect(instance['instanceId'], isNot('container:$_pluginId'));

    final tab = harness.container.read(tabbedViewControllerProvider).tabs.last;
    final value = tab.value as TabDataValue;
    expect(value.isPluginView, isTrue);
    expect(value.viewInstanceId, instance['instanceId']);
    // The renderer comes from the contribution when the plugin omits it.
    expect(value.renderer, RendererTokens.outline);
    expect(tab.text, 'Outline');
  });

  test('the responded instance is the one the plugin can patch', () async {
    final harness = await _harness();
    addTearDown(harness.container.dispose);

    final response = await _request(harness.manager, harness.transport, {
      'viewId': _viewId,
    });
    final data = response['payload']['data'] as Map<String, dynamic>;
    final instance = ViewInstanceId(
      pluginId: data['pluginId'] as String,
      sessionId: data['sessionId'] as String,
      viewId: data['viewId'] as String,
      instanceId: data['instanceId'] as String,
    );

    final store = harness.container.read(viewModelStoreProvider);
    store.installSnapshot(
      instance: instance,
      revision: 1,
      nodes: [
        {'id': 'n1', 'label': 'from the plugin'},
      ],
    );
    final result = store.applyPatch(
      instance: instance,
      baseRevision: 1,
      nextRevision: 2,
      ops: [
        const PatchOp(
          kind: PatchOpKind.update,
          id: 'n1',
          data: {'label': 'patched'},
        ),
      ],
    );

    expect(result.isOk, isTrue);
    expect(store.model(instance)!.nodes.single['label'], 'patched');
  });

  test('a view the plugin does not contribute is rejected', () async {
    final harness = await _harness();
    addTearDown(harness.container.dispose);

    final response = await _request(harness.manager, harness.transport, {
      'viewId': 'someone-else.outline',
    });

    expect(response['type'], 'sdk.response.error');
    expect(response['payload']['message'], contains('someone-else.outline'));
    expect(harness.container.read(tabbedViewControllerProvider).tabs.length, 1);
  });

  test('a missing viewId is rejected', () async {
    final harness = await _harness();
    addTearDown(harness.container.dispose);

    final response = await _request(
      harness.manager,
      harness.transport,
      const {},
    );

    expect(response['type'], 'sdk.response.error');
    expect(harness.container.read(tabbedViewControllerProvider).tabs.length, 1);
  });

  test('a plugin without tab:create cannot open a view tab', () async {
    final harness = await _harness(permissions: const {});
    addTearDown(harness.container.dispose);

    final response = await _request(harness.manager, harness.transport, {
      'viewId': _viewId,
    });

    expect(response['type'], 'sdk.response.error');
    expect(harness.container.read(tabbedViewControllerProvider).tabs.length, 1);
  });

  test('an explicit renderer overrides the contributed one', () async {
    final harness = await _harness();
    addTearDown(harness.container.dispose);

    final response = await _request(harness.manager, harness.transport, {
      'viewId': _viewId,
      'renderer': RendererTokens.log,
      'title': 'Log',
    });

    expect(response['type'], 'sdk.response.ok');
    final tab = harness.container.read(tabbedViewControllerProvider).tabs.last;
    expect((tab.value as TabDataValue).renderer, RendererTokens.log);
    expect(tab.text, 'Log');
  });
}
