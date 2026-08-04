import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_metrics.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/protocol.dart';

class _FakePluginTransport implements PluginTransport {
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  final StreamController<PluginTransportState> _states =
      StreamController<PluginTransportState>.broadcast();
  final List<Uint8List> sent = [];
  FutureOr<void> Function(Uint8List message)? onSend;
  bool _closed = false;
  int closeEffects = 0;

  @override
  String get type => 'Fake';

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  Stream<PluginTransportState> get states => _states.stream;

  @override
  Future<void> start() async {
    if (_closed) throw StateError('Fake transport is closed');
    _states.add(PluginTransportState.connecting);
    _states.add(PluginTransportState.ready);
  }

  @override
  Future<void> send(Uint8List message) async {
    if (_closed) throw StateError('Fake transport is closed');
    sent.add(message);
    await onSend?.call(message);
  }

  void emit(Map<String, dynamic> envelope) {
    _messages.add(Uint8List.fromList(utf8.encode(jsonEncode(envelope))));
  }

  void fail(Object error) {
    _messages.addError(error);
    _states.add(PluginTransportState.failed);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    closeEffects++;
    _states.add(PluginTransportState.closing);
    _states.add(PluginTransportState.closed);
    await _messages.close();
    await _states.close();
  }
}

void _configureHandshake(_FakePluginTransport transport) {
  var sequence = 0;
  transport.onSend = (message) {
    final envelope = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
    switch (envelope['type']) {
      case IdeCommands.initialize:
        transport.emit(
          makeEnvelope(
            type: SdkCommands.initialize,
            pluginId: envelope['pluginId'] as String,
            sessionId: envelope['sessionId'] as String,
            generation: envelope['generation'] as int,
            replyTo: envelope['requestId'] as String,
            sequence: ++sequence,
            payload: {
              'protocolVersion': 1,
              'sdkVersion': 'fake-transport',
              'capabilities': ['sdk.v1'],
            },
          ),
        );
        return;
      case IdeCommands.initialized:
        transport.emit(
          makeEnvelope(
            type: SdkCommands.ready,
            pluginId: envelope['pluginId'] as String,
            sessionId: envelope['sessionId'] as String,
            generation: envelope['generation'] as int,
            replyTo: envelope['requestId'] as String,
            sequence: ++sequence,
            payload: {
              'capabilities': ['sdk.v1'],
            },
          ),
        );
        return;
      case IdeCommands.healthPing:
        transport.emit(
          makeEnvelope(
            type: SdkCommands.healthPong,
            pluginId: envelope['pluginId'] as String,
            sessionId: envelope['sessionId'] as String,
            generation: envelope['generation'] as int,
            replyTo: envelope['requestId'] as String,
            sequence: ++sequence,
            payload: {'status': 'ok'},
          ),
        );
        return;
    }
  };
}

void main() {
  test('fake transport exchanges handshake messages and closes once', () async {
    final transport = _FakePluginTransport();
    _configureHandshake(transport);
    final manager = PluginRunManager(
      transport: transport,
      assetsPath: '.',
      pluginId: 'fake-plugin',
    );

    await manager.connect();

    expect(manager.sdkVersion, 'fake-transport');
    expect(
      transport.sent.map(
        (message) =>
            (jsonDecode(utf8.decode(message)) as Map<String, dynamic>)['type'],
      ),
      [IdeCommands.initialize, IdeCommands.initialized],
    );

    await manager.stop();
    await transport.close();
    expect(transport.closeEffects, 1);
  });

  test(
    'legacy empty response ID is replaced before protocol v1 send',
    () async {
      final transport = _FakePluginTransport();
      _configureHandshake(transport);
      final manager = PluginRunManager(
        transport: transport,
        assetsPath: '.',
        pluginId: 'fake-plugin',
      );
      await manager.connect();
      transport.sent.clear();

      manager.sendJson({
        'version': '0.0',
        'id': '',
        'type': SdkCommands.responseOk,
        'payload': {'data': true},
        'reply_to': 'sdk-request-1',
      });
      await pumpEventQueue();

      final outgoing =
          jsonDecode(utf8.decode(transport.sent.single))
              as Map<String, dynamic>;
      expect(outgoing['requestId'], isNotEmpty);
      expect(outgoing['replyTo'], 'sdk-request-1');
      expect(() => PluginProtocol.validateIncoming(outgoing), returnsNormally);

      await manager.stop();
    },
  );

  test('transport errors fail pending manager replies', () async {
    final transport = _FakePluginTransport();
    _configureHandshake(transport);
    final manager = PluginRunManager(
      transport: transport,
      assetsPath: '.',
      pluginId: 'fake-plugin',
    );
    await manager.connect();
    final requestSent = Completer<void>();
    transport.onSend = (message) {
      final envelope = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
      if (envelope['type'] == 'ide.fixture.pending') {
        requestSent.complete();
      }
    };

    final pending = manager.sendAndWaitReply(
      makeEnvelope(type: 'ide.fixture.pending'),
    );
    await requestSent.future;
    transport.fail(StateError('transport failed'));

    await expectLater(
      pending,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'transport failed',
        ),
      ),
    );
    await manager.stop();
  });

  test('transport messages route requests and replies independently', () async {
    final transport = _FakePluginTransport();
    final requestHandled = Completer<Map<String, dynamic>>();
    final handlerResponse = Completer<Map<String, dynamic>>();
    final manager = PluginRunManager(transport: transport, assetsPath: '.');

    manager.registerHandler('sdk.fixture.echo', (envelope, respond) {
      requestHandled.complete(envelope);
      respond(
        makeEnvelope(
          type: SdkCommands.responseOk,
          payload: {'data': envelope['payload']},
          replyTo: envelope['id'] as String,
        ),
      );
    }, publiclyAccessible: true);

    var sequence = 0;
    transport.onSend = (message) {
      final envelope = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
      if (envelope['type'] == IdeCommands.initialize) {
        transport.emit(
          makeEnvelope(
            type: SdkCommands.initialize,
            pluginId: envelope['pluginId'] as String,
            sessionId: envelope['sessionId'] as String,
            generation: envelope['generation'] as int,
            replyTo: envelope['requestId'] as String,
            sequence: ++sequence,
            payload: {
              'protocolVersion': 1,
              'capabilities': ['sdk.v1'],
            },
          ),
        );
      } else if (envelope['type'] == IdeCommands.initialized) {
        transport.emit(
          makeEnvelope(
            type: SdkCommands.ready,
            pluginId: envelope['pluginId'] as String,
            sessionId: envelope['sessionId'] as String,
            generation: envelope['generation'] as int,
            replyTo: envelope['requestId'] as String,
            sequence: ++sequence,
            payload: {
              'capabilities': ['sdk.v1'],
            },
          ),
        );
        transport.emit(
          makeEnvelope(
            type: 'sdk.fixture.echo',
            requestId: 'fixture-handler-request',
            pluginId: envelope['pluginId'] as String,
            sessionId: envelope['sessionId'] as String,
            generation: envelope['generation'] as int,
            sequence: ++sequence,
            payload: {'value': 42},
          ),
        );
      } else if (envelope['type'] == 'ide.fixture.request') {
        transport.emit(
          makeEnvelope(
            type: IdeCommands.responseOk,
            pluginId: envelope['pluginId'] as String,
            sessionId: envelope['sessionId'] as String,
            generation: envelope['generation'] as int,
            sequence: ++sequence,
            payload: {'data': 'reply-routed'},
            replyTo: envelope['requestId'] as String,
          ),
        );
      } else if (envelope['replyTo'] == 'fixture-handler-request') {
        handlerResponse.complete(envelope);
      }
    };

    try {
      await manager.connect();
      final reply = await manager
          .sendAndWaitReply(
            makeEnvelope(
              type: 'ide.fixture.request',
              payload: {'value': 'request'},
            ),
          )
          .timeout(const Duration(seconds: 2));

      expect(
        (await requestHandled.future.timeout(
          const Duration(seconds: 2),
        ))['payload'],
        {'value': 42},
      );
      expect(
        (await handlerResponse.future.timeout(
          const Duration(seconds: 2),
        ))['payload'],
        {
          'data': {'value': 42},
        },
      );
      expect(reply['payload'], {'data': 'reply-routed'});
      await expectLater(
        manager.sendAndWaitReply(
          makeEnvelope(type: 'ide.fixture.timeout'),
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
      final sent = transport.sent
          .map(
            (message) =>
                jsonDecode(utf8.decode(message)) as Map<String, dynamic>,
          )
          .toList();
      final timedOutRequest = sent.firstWhere(
        (envelope) => envelope['type'] == 'ide.fixture.timeout',
      );
      expect(timedOutRequest['deadline'], isA<int>());
      expect(
        sent.any(
          (envelope) =>
              envelope['type'] == IdeCommands.requestCancel &&
              envelope['payload']['requestId'] == timedOutRequest['requestId'],
        ),
        isTrue,
      );
    } finally {
      await manager.stop();
    }
  });

  test(
    'control and view patch queues preserve global sequence order',
    () async {
      final transport = _FakePluginTransport();
      _configureHandshake(transport);
      final manager = PluginRunManager(
        transport: transport,
        assetsPath: '.',
        pluginId: 'ordered-plugin',
      );
      final handled = <int>[];
      void handler(
        Map<String, dynamic> envelope,
        void Function(Map<String, dynamic>) respond,
      ) {
        handled.add(envelope['sequence'] as int);
      }

      manager.registerHandler(
        'sdk.fixture.control',
        handler,
        publiclyAccessible: true,
      );
      manager.registerHandler(
        SdkCommands.viewPatch,
        handler,
        publiclyAccessible: true,
      );

      try {
        await manager.connect();
        for (var sequence = 3; sequence <= 34; sequence++) {
          transport.emit(
            makeEnvelope(
              type: sequence.isEven
                  ? SdkCommands.viewPatch
                  : 'sdk.fixture.control',
              pluginId: manager.pluginId,
              sessionId: manager.sessionId,
              generation: manager.generation,
              sequence: sequence,
            ),
          );
        }
        for (var i = 0; i < 200 && handled.length < 32; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }

        expect(handled, [
          for (var sequence = 3; sequence <= 34; sequence++) sequence,
        ]);
        expect(manager.controlQueueDepth, 0);
        expect(manager.viewPatchQueueDepth, 0);
      } finally {
        await manager.stop();
      }
    },
  );

  test('one thousand small messages drain with bounded queue depth', () async {
    final transport = _FakePluginTransport();
    _configureHandshake(transport);
    final metrics = PluginSessionMetrics(
      pluginId: 'burst-plugin',
      sessionId: 'burst-session',
      generation: 1,
    );
    final manager = PluginRunManager(
      transport: transport,
      assetsPath: '.',
      pluginId: 'burst-plugin',
      sessionId: 'burst-session',
      metrics: metrics,
    );
    var handled = 0;
    manager.registerHandler(
      'sdk.fixture.burst',
      (envelope, respond) => handled += 1,
      publiclyAccessible: true,
    );

    try {
      await manager.connect();
      for (var index = 0; index < 1000; index++) {
        transport.emit(
          makeEnvelope(
            type: 'sdk.fixture.burst',
            pluginId: manager.pluginId,
            sessionId: manager.sessionId,
            generation: manager.generation,
            sequence: index + 3,
            payload: {'index': index},
          ),
        );
      }
      for (var i = 0; i < 400 && handled < 1000; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(handled, 1000);
      expect(metrics.controlQueueHighWater, lessThanOrEqualTo(256));
      expect(manager.controlQueueDepth, 0);
    } finally {
      await manager.stop();
    }
  });

  test('malformed queue sequence does not stall later messages', () async {
    final transport = _FakePluginTransport();
    _configureHandshake(transport);
    final output = <String>[];
    final manager = PluginRunManager(
      transport: transport,
      assetsPath: '.',
      pluginId: 'malformed-plugin',
      onOutput: output.add,
    );
    final handled = Completer<void>();
    manager.registerHandler(
      'sdk.fixture.after-malformed',
      (envelope, respond) => handled.complete(),
      publiclyAccessible: true,
    );

    try {
      await manager.connect();
      transport.emit({
        ...makeEnvelope(
          type: SdkCommands.viewPatch,
          pluginId: manager.pluginId,
          sessionId: manager.sessionId,
          generation: manager.generation,
          sequence: 3,
        ),
        'sequence': 'bad',
      });
      transport.emit(
        makeEnvelope(
          type: 'sdk.fixture.after-malformed',
          pluginId: manager.pluginId,
          sessionId: manager.sessionId,
          generation: manager.generation,
          sequence: 3,
        ),
      );

      await handled.future.timeout(const Duration(seconds: 2));
      expect(output.any((line) => line.contains('Invalid sequence')), isTrue);
    } finally {
      await manager.stop();
    }
  });

  test('large JSON envelope is decoded through the deferred path', () async {
    final transport = _FakePluginTransport();
    _configureHandshake(transport);
    final manager = PluginRunManager(
      transport: transport,
      assetsPath: '.',
      pluginId: 'large-json-plugin',
    );
    final handled = Completer<int>();
    manager.registerHandler(
      'sdk.fixture.large-json',
      (envelope, respond) =>
          handled.complete((envelope['payload']['text'] as String).length),
      publiclyAccessible: true,
    );

    try {
      await manager.connect();
      transport.emit(
        makeEnvelope(
          type: 'sdk.fixture.large-json',
          pluginId: manager.pluginId,
          sessionId: manager.sessionId,
          generation: manager.generation,
          sequence: 3,
          payload: {'text': 'x' * (300 * 1024)},
        ),
      );

      expect(
        await handled.future.timeout(const Duration(seconds: 5)),
        300 * 1024,
      );
    } finally {
      await manager.stop();
    }
  });

  test(
    'legacy protocol plugin receives an explicit incompatibility error',
    () async {
      final transport = _FakePluginTransport();
      final manager = PluginRunManager(transport: transport, assetsPath: '.');

      transport.onSend = (message) {
        final envelope =
            jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
        if (envelope['type'] == IdeCommands.initialize) {
          transport.emit({
            'version': '0.0',
            'id': 'legacy-message',
            'type': 'sdk.page.push',
            'payload': <String, dynamic>{},
            'data': null,
            'reply_to': null,
            'timestamp': 1700000000000,
          });
        }
      };

      try {
        await expectLater(
          manager.connect(),
          throwsA(
            isA<PluginProtocolException>().having(
              (error) => error.message,
              'message',
              contains('protocolVersion'),
            ),
          ),
        );
      } finally {
        await manager.stop();
      }
    },
  );

  test('health ping records a successful round trip', () async {
    final transport = _FakePluginTransport();
    _configureHandshake(transport);
    final metrics = PluginSessionMetrics(
      pluginId: 'health-plugin',
      sessionId: 'health-session',
      generation: 1,
    );
    final manager = PluginRunManager(
      transport: transport,
      assetsPath: '.',
      pluginId: metrics.pluginId,
      sessionId: metrics.sessionId,
      metrics: metrics,
    );

    try {
      await manager.connect();
      final latency = await manager.ping();
      expect(latency, isA<Duration>());
      expect(metrics.healthOk, isTrue);
      expect(metrics.lastHealthAt, isNotNull);
      expect(metrics.lastHealthLatencyMs, isNotNull);
    } finally {
      await manager.stop();
    }
  });

  test('repeated failures pause view patches until resumed', () async {
    final transport = _FakePluginTransport();
    _configureHandshake(transport);
    final metrics = PluginSessionMetrics(
      pluginId: 'paused-plugin',
      sessionId: 'paused-session',
      generation: 1,
    );
    final manager = PluginRunManager(
      transport: transport,
      assetsPath: '.',
      pluginId: metrics.pluginId,
      sessionId: metrics.sessionId,
      metrics: metrics,
    );
    var patches = 0;
    manager.registerHandler(
      SdkCommands.viewPatch,
      (envelope, respond) => patches += 1,
      publiclyAccessible: true,
    );

    try {
      await manager.connect();
      for (var index = 0; index < 8; index++) {
        metrics.recordError('failure $index');
      }
      transport.emit(
        makeEnvelope(
          type: SdkCommands.viewPatch,
          pluginId: manager.pluginId,
          sessionId: manager.sessionId,
          generation: manager.generation,
          sequence: 3,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(patches, 0);
      final sent = transport.sent
          .map(
            (bytes) => jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
          )
          .toList();
      expect(
        sent.any(
          (envelope) =>
              envelope['type'] == SdkCommands.responseError &&
              envelope['payload']['code'] == 'delivery_paused',
        ),
        isTrue,
      );

      metrics.resumeEventDelivery();
      transport.emit(
        makeEnvelope(
          type: SdkCommands.viewPatch,
          pluginId: manager.pluginId,
          sessionId: manager.sessionId,
          generation: manager.generation,
          sequence: 4,
        ),
      );
      for (var index = 0; index < 20 && patches == 0; index++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(patches, 1);
    } finally {
      await manager.stop();
    }
  });
}
