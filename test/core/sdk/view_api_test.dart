import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/api/view_api.dart';
import 'package:pyrite_ide/core/sdk/component_method_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_perf_budget.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/core/sdk/view_model_store_provider.dart';
import 'package:pyrite_ide/core/sdk/view_route_stack.dart';

class _ComponentHost implements ComponentMethodHostEntry {
  _ComponentHost(this.instance, {this.error});

  @override
  final ViewInstanceId instance;
  final ComponentMethodException? error;
  final List<(String, String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invokeComponentMethod(
    String componentId,
    String method,
    Map<String, dynamic> arguments,
  ) async {
    if (error case final error?) throw error;
    calls.add((componentId, method, arguments));
    return {'handled': true};
  }
}

class _Transport implements PluginTransport {
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  final StreamController<PluginTransportState> _states =
      StreamController<PluginTransportState>.broadcast();
  final List<Map<String, dynamic>> responses = [];
  final List<Map<String, dynamic>> frames = [];

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
      case SdkCommands.responseOk:
      case SdkCommands.responseError:
        responses.add(envelope);
      default:
        // ide.view.ack/nack/resync control frames.
        frames.add(envelope);
    }
  }

  void _reply(String type, Map<String, dynamic> req, int seq, Map payload) {
    _messages.add(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode(
            makeEnvelope(
              type: type,
              pluginId: req['pluginId'] as String,
              sessionId: req['sessionId'] as String,
              generation: req['generation'] as int,
              replyTo: req['requestId'] as String,
              sequence: seq,
              payload: Map<String, dynamic>.from(payload),
            ),
          ),
        ),
      ),
    );
  }

  void inject(Map<String, dynamic> envelope) {
    _messages.add(Uint8List.fromList(utf8.encode(jsonEncode(envelope))));
  }

  List<Map<String, dynamic>> framesOfType(String type) =>
      frames.where((f) => f['type'] == type).toList();

  @override
  Future<void> close() async {
    await _messages.close();
    await _states.close();
  }
}

Future<({PluginRunManager manager, _Transport transport})> _start(
  ProviderContainer container,
) async {
  final transport = _Transport();
  final manager = PluginRunManager(
    transport: transport,
    assetsPath: '.',
    pluginId: 'view-test',
    pluginPermissions: const {},
    sessionId: 'session-1',
    generation: 1,
  );
  container.read(sdkViewProvider).bind(manager);
  await manager.connect();
  return (manager: manager, transport: transport);
}

/// Inbound sequence numbers must strictly increase or the manager drops the
/// frame as a duplicate.
int _sequence = 100;

Future<Map<String, dynamic>> _request(
  PluginRunManager manager,
  _Transport transport,
  String type,
  Map<String, dynamic> payload,
) async {
  final envelope = makeEnvelope(
    type: type,
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
  throw StateError('No response for ${envelope['type']}');
}

Map<String, dynamic> _viewKeys() => {'viewId': 'outline', 'instanceId': 'i1'};

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('snapshot then patch acks the new revision', () async {
    final started = await _start(container);
    await _request(
      started.manager,
      started.transport,
      SdkCommands.viewSnapshot,
      {
        ..._viewKeys(),
        'revision': 1,
        'nodes': [
          {'id': 'a', 'label': 'A'},
        ],
      },
    );
    final patch = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewPatch,
      {
        ..._viewKeys(),
        'baseRevision': 1,
        'revision': 2,
        'ops': [
          {
            'op': 'insert',
            'id': 'b',
            'data': {'label': 'B'},
          },
        ],
      },
    );
    expect(patch['type'], SdkCommands.responseOk);
    final acks = started.transport.framesOfType(IdeCommands.viewAck);
    expect(acks.single['payload']['revision'], 2);

    final store = container.read(viewModelStoreProvider);
    final model = store.model(
      const ViewInstanceId(
        pluginId: 'view-test',
        sessionId: 'session-1',
        viewId: 'outline',
        instanceId: 'i1',
      ),
    );
    expect(model!.nodes.length, 2);
    await started.manager.stop();
  });

  test('snapshot node budget rejects oversized models', () async {
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewSnapshot,
      {
        ..._viewKeys(),
        'revision': 1,
        'nodes': [
          for (var i = 0; i <= PluginPerfBudget.maxSnapshotNodes; i++)
            {'id': 'node-$i'},
        ],
      },
    );

    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'payload_too_large');
    await started.manager.stop();
  });

  test('patch operation budget rejects oversized transactions', () async {
    final started = await _start(container);
    await _request(
      started.manager,
      started.transport,
      SdkCommands.viewSnapshot,
      {..._viewKeys(), 'revision': 1, 'nodes': const []},
    );
    final response = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewPatch,
      {
        ..._viewKeys(),
        'baseRevision': 1,
        'revision': 2,
        'ops': [
          for (var i = 0; i <= PluginPerfBudget.maxPatchOps; i++)
            {'op': 'insert', 'id': 'node-$i', 'data': const {}},
        ],
      },
    );

    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'payload_too_large');
    await started.manager.stop();
  });

  test('a revision gap nacks and requests resync', () async {
    final started = await _start(container);
    await _request(
      started.manager,
      started.transport,
      SdkCommands.viewSnapshot,
      {..._viewKeys(), 'revision': 1, 'nodes': const []},
    );
    final patch = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewPatch,
      {
        ..._viewKeys(),
        'baseRevision': 9, // gap
        'revision': 10,
        'ops': const [],
      },
    );
    expect(patch['type'], SdkCommands.responseError);
    expect(patch['payload']['code'], 'revisionGap');
    expect(started.transport.framesOfType(IdeCommands.viewNack), hasLength(1));
    final resync = started.transport.framesOfType(IdeCommands.viewResync);
    expect(resync.single['payload']['revision'], 1);
    await started.manager.stop();
  });

  test('a rolled-back invalid patch nacks without resync', () async {
    final started = await _start(container);
    await _request(
      started.manager,
      started.transport,
      SdkCommands.viewSnapshot,
      {..._viewKeys(), 'revision': 1, 'nodes': const []},
    );
    final patch = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewPatch,
      {
        ..._viewKeys(),
        'baseRevision': 1,
        'revision': 2,
        'ops': [
          {'op': 'remove', 'id': 'ghost'},
        ],
      },
    );
    expect(patch['payload']['code'], 'invalidOperation');
    expect(started.transport.framesOfType(IdeCommands.viewNack), hasLength(1));
    // invalidOperation is not recoverable by resync (client bug), so none sent.
    expect(started.transport.framesOfType(IdeCommands.viewResync), isEmpty);
    await started.manager.stop();
  });

  test('route push syncs the new stack back to the plugin', () async {
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewRoutePush,
      {
        ..._viewKeys(),
        'route': 'detail',
        'params': {'id': 7},
      },
    );
    expect(response['type'], SdkCommands.responseOk);
    expect(response['payload']['data']['route'], 'detail');
    expect(response['payload']['data']['stack'], ['home', 'detail']);

    final sync = started.transport.framesOfType(IdeCommands.viewRouteSync);
    expect(sync.single['payload']['route'], 'detail');
    expect(sync.single['payload']['stack'], ['home', 'detail']);
    expect(sync.single['payload']['params']['id'], 7);
    expect(sync.single['payload']['instance']['instanceId'], 'i1');
    await started.manager.stop();
  });

  test('two instances of one view route independently over the wire', () async {
    final started = await _start(container);
    await _request(
      started.manager,
      started.transport,
      SdkCommands.viewRoutePush,
      {'viewId': 'outline', 'instanceId': 'sidebar', 'route': 'detail'},
    );
    final tab = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewRoutePush,
      {'viewId': 'outline', 'instanceId': 'tab', 'route': 'settings'},
    );
    expect(tab['payload']['data']['stack'], ['home', 'settings']);

    final stacks = container.read(viewRouteStacksProvider);
    ViewInstanceId instance(String id) => ViewInstanceId(
      pluginId: 'view-test',
      sessionId: 'session-1',
      viewId: 'outline',
      instanceId: id,
    );
    expect(stacks.routesOf(instance('sidebar')), ['home', 'detail']);
    expect(stacks.routesOf(instance('tab')), ['home', 'settings']);
    await started.manager.stop();
  });

  test(
    'popping a root-only stack reports popped false, not an error',
    () async {
      final started = await _start(container);
      final response = await _request(
        started.manager,
        started.transport,
        SdkCommands.viewRoutePop,
        {..._viewKeys()},
      );
      expect(response['type'], SdkCommands.responseOk);
      expect(response['payload']['data']['popped'], false);
      expect(response['payload']['data']['route'], 'home');
      // Nothing moved, so no sync frame is worth sending.
      expect(
        started.transport.framesOfType(IdeCommands.viewRouteSync),
        isEmpty,
      );
      await started.manager.stop();
    },
  );

  test('route goto collapses the stack and replace keeps its depth', () async {
    final started = await _start(container);
    for (final route in ['a', 'b']) {
      await _request(
        started.manager,
        started.transport,
        SdkCommands.viewRoutePush,
        {..._viewKeys(), 'route': route},
      );
    }
    final replaced = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewRouteReplace,
      {..._viewKeys(), 'route': 'b2'},
    );
    expect(replaced['payload']['data']['stack'], ['home', 'a', 'b2']);

    final gone = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewRouteGoto,
      {..._viewKeys(), 'route': 'root2'},
    );
    expect(gone['payload']['data']['stack'], ['root2']);

    final popped = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewRoutePop,
      {..._viewKeys()},
    );
    expect(popped['payload']['data']['popped'], false);
    await started.manager.stop();
  });

  test('a route command without a route is an invalid request', () async {
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewRoutePush,
      {..._viewKeys()},
    );
    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'invalid_request');
    await started.manager.stop();
  });

  test('a route command without an instance is an invalid request', () async {
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewRoutePush,
      {'viewId': 'outline', 'route': 'detail'},
    );
    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'invalid_request');
    await started.manager.stop();
  });

  test('closing a view forgets its route history', () async {
    final started = await _start(container);
    await _request(
      started.manager,
      started.transport,
      SdkCommands.viewRoutePush,
      {..._viewKeys(), 'route': 'detail'},
    );
    await _request(started.manager, started.transport, SdkCommands.viewClose, {
      ..._viewKeys(),
    });
    final stacks = container.read(viewRouteStacksProvider);
    expect(
      stacks.routesOf(
        const ViewInstanceId(
          pluginId: 'view-test',
          sessionId: 'session-1',
          viewId: 'outline',
          instanceId: 'i1',
        ),
      ),
      ['home'],
    );
    await started.manager.stop();
  });

  test('patch after close is rejected', () async {
    final started = await _start(container);
    await _request(
      started.manager,
      started.transport,
      SdkCommands.viewSnapshot,
      {..._viewKeys(), 'revision': 1, 'nodes': const []},
    );
    await _request(started.manager, started.transport, SdkCommands.viewClose, {
      ..._viewKeys(),
    });
    final patch = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewPatch,
      {..._viewKeys(), 'baseRevision': 1, 'revision': 2, 'ops': const []},
    );
    expect(patch['type'], SdkCommands.responseError);
    await started.manager.stop();
  });

  test('host reports view visibility without waiting for a response', () async {
    final started = await _start(container);
    const instance = ViewInstanceId(
      pluginId: 'view-test',
      sessionId: 'session-1',
      viewId: 'outline',
      instanceId: 'container:python-tools',
    );

    container
        .read(sdkViewProvider)
        .sendVisibilityChanged(started.manager, instance, false);
    await Future<void>.delayed(Duration.zero);

    final frames = started.transport.framesOfType(
      IdeCommands.viewVisibilityChanged,
    );
    expect(frames, hasLength(1));
    expect(frames.single['payload'], {
      'instance': instance.toJson(),
      'visible': false,
    });
    await started.manager.stop();
  });

  test('component invoke reaches only the addressed mounted view', () async {
    final started = await _start(container);
    final instance = ViewInstanceId(
      pluginId: 'view-test',
      sessionId: started.manager.sessionId,
      viewId: 'outline',
      instanceId: 'i1',
    );
    final host = _ComponentHost(instance);
    container.read(componentMethodRegistryProvider).attach(instance, host);

    final response = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewComponentInvoke,
      {
        ..._viewKeys(),
        'componentId': 'tree',
        'method': 'expand',
        'arguments': {'id': 'node-1'},
      },
    );

    expect(response['type'], SdkCommands.responseOk);
    expect(response['payload']['data'], {'handled': true});
    expect(host.calls, hasLength(1));
    expect(host.calls.single.$1, 'tree');
    expect(host.calls.single.$2, 'expand');
    expect(host.calls.single.$3, {'id': 'node-1'});
    await started.manager.stop();
  });

  test('component invoke preserves stable host error codes', () async {
    final started = await _start(container);
    final instance = ViewInstanceId(
      pluginId: 'view-test',
      sessionId: started.manager.sessionId,
      viewId: 'outline',
      instanceId: 'i1',
    );
    final host = _ComponentHost(
      instance,
      error: const ComponentMethodException(
        'method_not_supported',
        'unsupported',
        details: {'method': 'missing'},
      ),
    );
    container.read(componentMethodRegistryProvider).attach(instance, host);

    final response = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewComponentInvoke,
      {
        ..._viewKeys(),
        'componentId': 'tree',
        'method': 'missing',
        'arguments': const {},
      },
    );

    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'method_not_supported');
    expect(response['payload']['details'], {'method': 'missing'});
    await started.manager.stop();
  });

  test('component invoke rejects non-object arguments', () async {
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkCommands.viewComponentInvoke,
      {
        ..._viewKeys(),
        'componentId': 'tree',
        'method': 'expand',
        'arguments': ['node-1'],
      },
    );
    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'invalid_arguments');
    await started.manager.stop();
  });
}
