import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/api/runtime_api.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/runtime_inspection.dart';

class _Transport implements PluginTransport {
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  final StreamController<PluginTransportState> _states =
      StreamController<PluginTransportState>.broadcast();
  final _responses = StreamController<Map<String, dynamic>>.broadcast();

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
        _responses.add(envelope);
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

  Stream<Map<String, dynamic>> get responses => _responses.stream;

  @override
  Future<void> close() async {
    await _messages.close();
    await _states.close();
    await _responses.close();
  }
}

/// A backend that records CTRL-C attempts (there must be none) and serves
/// configurable pages.
class _FakeBackend implements RuntimeBackend {
  RuntimePage? scopesPage;
  RuntimePage? variablesPage;
  RuntimePage? childrenPage;
  Map<String, dynamic>? info;
  final List<({int start, int count})> childrenCalls = [];

  @override
  Future<RuntimePage?> scopes(String sessionId) async => scopesPage;

  @override
  Future<RuntimePage?> variables(
    String sessionId,
    String scopeId, {
    int start = 0,
    int count = 0,
  }) async => variablesPage;

  @override
  Future<RuntimePage?> children(
    String reference, {
    int start = 0,
    int count = 0,
  }) async {
    childrenCalls.add((start: start, count: count));
    return childrenPage;
  }

  @override
  Future<Map<String, dynamic>?> objectInfo(String reference) async => info;
}

class _FakeHost implements RuntimeHost {
  _FakeHost();

  @override
  final RuntimeInspectionService service = RuntimeInspectionService(
    emit: (topic, payload) {},
  );

  @override
  final _FakeBackend backend = _FakeBackend();
}

Future<({PluginRunManager manager, _Transport transport})> _start(
  ProviderContainer container,
) async {
  final transport = _Transport();
  final manager = PluginRunManager(
    transport: transport,
    assetsPath: '.',
    pluginId: 'rt-test',
    pluginPermissions: const {
      'runtime': ['inspect'],
    },
    sessionId: 'session-1',
    generation: 1,
  );
  container.read(sdkRuntimeProvider).bind(manager);
  await manager.connect();
  return (manager: manager, transport: transport);
}

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
    sequence: 100,
  );
  final response = transport.responses
      .firstWhere((e) => e['replyTo'] == envelope['requestId'])
      .timeout(const Duration(seconds: 5));
  transport.inject(envelope);
  return response;
}

void main() {
  late ProviderContainer container;
  late _FakeHost host;

  setUp(() {
    host = _FakeHost();
    container = ProviderContainer(
      overrides: [runtimeHostProvider.overrideWithValue(host)],
    );
  });

  tearDown(() => container.dispose());

  test('sessions lists the live runtime sessions', () async {
    host.service.createSession('device');
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkRuntimeCommands.sessions,
      {},
    );
    final data = response['payload']['data'] as Map<String, dynamic>;
    expect((data['sessions'] as List).single['sessionId'], 'device');
    await started.manager.stop();
  });

  test('scopes returns unavailable when capability is unavailable', () async {
    host.service.createSession(
      'device',
      capability: RuntimeCapability.unavailable,
    );
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkRuntimeCommands.scopes,
      {'sessionId': 'device'},
    );
    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'unavailable');
    await started.manager.stop();
  });

  test('scopes returns the backend page when available', () async {
    host.service.createSession('device');
    host.backend.scopesPage = const RuntimePage(
      items: [
        {'id': 'globals', 'name': 'globals'},
      ],
    );
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkRuntimeCommands.scopes,
      {'sessionId': 'device'},
    );
    final data = response['payload']['data'] as Map<String, dynamic>;
    expect((data['items'] as List).single['id'], 'globals');
    await started.manager.stop();
  });

  test('children of a stale reference returns stale_reference', () async {
    host.service.createSession('device');
    final ref = host.service.reference('device', '42')!;
    host.service.restartBackend('device'); // invalidates ref
    host.backend.childrenPage = const RuntimePage(items: []);
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkRuntimeCommands.children,
      {'reference': ref.encode()},
    );
    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'stale_reference');
    // A stale reference must never reach the backend.
    expect(host.backend.childrenCalls, isEmpty);
    await started.manager.stop();
  });

  test(
    'children forwards paging to the backend for a valid reference',
    () async {
      host.service.createSession('device');
      final ref = host.service.reference('device', '42')!;
      host.backend.childrenPage = const RuntimePage(
        items: [
          {'name': '0'},
        ],
        total: 3,
        start: 1,
      );
      final started = await _start(container);
      final response = await _request(
        started.manager,
        started.transport,
        SdkRuntimeCommands.children,
        {'reference': ref.encode(), 'start': 1, 'count': 2},
      );
      expect(response['type'], SdkCommands.responseOk);
      expect(host.backend.childrenCalls.single, (start: 1, count: 2));
      final data = response['payload']['data'] as Map<String, dynamic>;
      expect(data['total'], 3);
      await started.manager.stop();
    },
  );

  test('object_info on a malformed reference is rejected', () async {
    host.service.createSession('device');
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkRuntimeCommands.objectInfo,
      {'reference': 'not-a-reference'},
    );
    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'invalid_request');
    await started.manager.stop();
  });
}
