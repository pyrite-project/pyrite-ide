import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';

/// Fake transport that completes the handshake and records outbound frames.
class _Transport implements PluginTransport {
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  final StreamController<PluginTransportState> _states =
      StreamController<PluginTransportState>.broadcast();
  final List<Map<String, dynamic>> sent = [];
  bool _closed = false;

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
    sent.add(envelope);
    switch (envelope['type']) {
      case IdeCommands.initialize:
        emit(
          makeEnvelope(
            type: SdkCommands.initialize,
            pluginId: envelope['pluginId'] as String,
            sessionId: envelope['sessionId'] as String,
            generation: envelope['generation'] as int,
            replyTo: envelope['requestId'] as String,
            sequence: 1,
            payload: {
              'protocolVersion': 1,
              'sdkVersion': 'fixture',
              'capabilities': ['sdk.v1'],
            },
          ),
        );
      case IdeCommands.initialized:
        emit(
          makeEnvelope(
            type: SdkCommands.ready,
            pluginId: envelope['pluginId'] as String,
            sessionId: envelope['sessionId'] as String,
            generation: envelope['generation'] as int,
            replyTo: envelope['requestId'] as String,
            sequence: 2,
            payload: {
              'capabilities': ['sdk.v1'],
            },
          ),
        );
    }
  }

  void emit(Map<String, dynamic> envelope) {
    _messages.add(Uint8List.fromList(utf8.encode(jsonEncode(envelope))));
  }

  List<Map<String, dynamic>> get emitted =>
      sent.where((e) => e['type'] == IdeCommands.eventEmit).toList();

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _states.add(PluginTransportState.closing);
    _states.add(PluginTransportState.closed);
    await _messages.close();
    await _states.close();
  }
}

Future<PluginRunManager> _startManager(
  _Transport transport, {
  Map<String, List<String>> permissions = const {},
  String pluginId = 'events-test',
  String sessionId = 'session-1',
  int generation = 1,
}) async {
  final manager = PluginRunManager(
    transport: transport,
    assetsPath: '.',
    pluginId: pluginId,
    pluginPermissions: permissions,
    sessionId: sessionId,
    generation: generation,
  );
  await manager.connect();
  return manager;
}

void main() {
  test('subscribe then emit routes an event to the plugin transport', () async {
    final transport = _Transport();
    final manager = await _startManager(
      transport,
      permissions: const {
        'serial': ['read'],
      },
    );
    final bus = PluginEventBus(
      deliver: (pluginId, sessionId, generation, event) {
        if (manager.pluginId == pluginId &&
            manager.sessionId == sessionId &&
            manager.generation == generation) {
          manager.sendEvent(
            subscriptionId: event.subscriptionId,
            topic: event.topic,
            payloads: event.payloads,
          );
        }
      },
    );

    final result = bus.subscribe(
      subscriptionId: 'sub-1',
      pluginId: manager.pluginId,
      sessionId: manager.sessionId,
      generation: manager.generation,
      topicName: 'device.connected',
      pluginPermissions: manager.pluginPermissions,
    );
    expect(result.isOk, isTrue);

    bus.emit('device.connected', {'port': 'COM7'});
    await Future<void>.delayed(Duration.zero);

    expect(transport.emitted, hasLength(1));
    final payload = transport.emitted.single['payload'] as Map<String, dynamic>;
    expect(payload['subscriptionId'], 'sub-1');
    expect(payload['topic'], 'device.connected');
    expect(payload['events'], [
      {'port': 'COM7'},
    ]);
    await manager.stop();
  });

  test('subscribe is denied when the plugin lacks the topic permission', () {
    final bus = PluginEventBus(
      deliver: (pluginId, sessionId, generation, event) {},
    );
    final result = bus.subscribe(
      subscriptionId: 'sub-1',
      pluginId: 'events-test',
      sessionId: 'session-1',
      generation: 1,
      topicName: 'runtime.variables.changed',
      pluginPermissions: const {},
    );
    expect(result.isOk, isFalse);
    expect(result.errorCode, 'permission_denied');
  });

  test(
    'events for an old session are not delivered to a new session',
    () async {
      // Two managers for the same plugin, different sessions/generations.
      final oldTransport = _Transport();
      final newTransport = _Transport();
      final oldManager = await _startManager(
        oldTransport,
        permissions: const {
          'serial': ['read'],
        },
        sessionId: 'old',
        generation: 1,
      );
      final newManager = await _startManager(
        newTransport,
        permissions: const {
          'serial': ['read'],
        },
        sessionId: 'new',
        generation: 2,
      );
      final managers = [oldManager, newManager];
      final bus = PluginEventBus(
        deliver: (pluginId, sessionId, generation, event) {
          for (final manager in managers) {
            if (manager.pluginId == pluginId &&
                manager.sessionId == sessionId &&
                manager.generation == generation) {
              manager.sendEvent(
                subscriptionId: event.subscriptionId,
                topic: event.topic,
                payloads: event.payloads,
              );
            }
          }
        },
      );

      // The old session subscribes, then stops; its subscription is cleared.
      bus.subscribe(
        subscriptionId: 'sub-old',
        pluginId: 'events-test',
        sessionId: 'old',
        generation: 1,
        topicName: 'device.connected',
        pluginPermissions: oldManager.pluginPermissions,
      );
      bus.clearSession('events-test', 'old');

      // The new session subscribes and should be the only recipient.
      bus.subscribe(
        subscriptionId: 'sub-new',
        pluginId: 'events-test',
        sessionId: 'new',
        generation: 2,
        topicName: 'device.connected',
        pluginPermissions: newManager.pluginPermissions,
      );
      bus.emit('device.connected', {'port': 'COM9'});
      await Future<void>.delayed(Duration.zero);

      expect(oldTransport.emitted, isEmpty);
      expect(newTransport.emitted, hasLength(1));
      await oldManager.stop();
      await newManager.stop();
    },
  );
}
