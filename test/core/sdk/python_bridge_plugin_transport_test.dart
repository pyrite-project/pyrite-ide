import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/python_bridge_plugin_transport.dart';

class _FakePythonBridgeChannel implements PluginPythonBridgeChannel {
  _FakePythonBridgeChannel(this.port);

  @override
  final int port;
  final StreamController<Uint8List> controller =
      StreamController<Uint8List>.broadcast();
  final List<Uint8List> sent = [];
  final List<String> signaledLabels = [];
  bool Function(Uint8List message)? onSend;
  int closeEffects = 0;

  @override
  Stream<Uint8List> get messages => controller.stream;

  @override
  bool send(Uint8List message) {
    final accepted = onSend?.call(message) ?? true;
    if (accepted) sent.add(Uint8List.fromList(message));
    return accepted;
  }

  @override
  void signalDartSession(String channelLabel) {
    signaledLabels.add(channelLabel);
  }

  @override
  void close() {
    if (closeEffects != 0) return;
    closeEffects++;
    unawaited(controller.close());
  }
}

void main() {
  test('start exposes port and session label then closes once', () async {
    final channel = _FakePythonBridgeChannel(42);
    final transport = PythonBridgePluginTransport(
      channelLabel: 'plugin.example',
      channel: channel,
    );
    final states = <PluginTransportState>[];
    final subscription = transport.states.listen(states.add);

    await transport.start();
    await transport.close();
    await transport.close();
    await subscription.cancel();

    expect(transport.port, 42);
    expect(
      transport.startupEnvironment,
      containsPair('PYRITE_IDE_DART_SESSION_TOKEN', isNotEmpty),
    );
    expect(
      transport.startupEnvironment,
      containsPair('PYRITE_IDE_PLUGIN_BRIDGE_PORT', '42'),
    );
    expect(
      transport.startupEnvironment,
      containsPair('PYRITE_IDE_PLUGIN_BRIDGE_LABEL', 'plugin.example'),
    );
    expect(channel.signaledLabels, ['plugin.example']);
    expect(channel.closeEffects, 1);
    expect(states, [
      PluginTransportState.connecting,
      PluginTransportState.ready,
      PluginTransportState.closing,
      PluginTransportState.closed,
    ]);
  });

  test('send retries only until the Python handler becomes ready', () async {
    final channel = _FakePythonBridgeChannel(1);
    var attempts = 0;
    channel.onSend = (_) => ++attempts == 3;
    final transport = PythonBridgePluginTransport(
      channelLabel: 'plugin.slow',
      channel: channel,
      retryInterval: const Duration(milliseconds: 1),
      sendTimeout: const Duration(milliseconds: 50),
    );
    await transport.start();

    await transport.send(Uint8List.fromList([1]));

    expect(attempts, 3);
    expect(channel.sent.single, [1]);
    await transport.close();
  });

  test('send fails at its deadline when no handler registers', () async {
    final channel = _FakePythonBridgeChannel(1)..onSend = (_) => false;
    final transport = PythonBridgePluginTransport(
      channelLabel: 'plugin.missing',
      channel: channel,
      retryInterval: const Duration(milliseconds: 1),
      sendTimeout: const Duration(milliseconds: 5),
    );
    await transport.start();

    await expectLater(
      transport.send(Uint8List(0)),
      throwsA(isA<TimeoutException>()),
    );
    await transport.close();
  });

  test(
    'an exited Python channel closes the transport and rejects sends',
    () async {
      final channel = _FakePythonBridgeChannel(1);
      final transport = PythonBridgePluginTransport(
        channelLabel: 'plugin.exited',
        channel: channel,
      );
      await transport.start();
      final closed = transport.states.firstWhere(
        (state) => state == PluginTransportState.closed,
      );

      await channel.controller.close();

      await closed;
      await expectLater(
        transport.send(Uint8List.fromList([1])),
        throwsStateError,
      );
      await transport.close();
    },
  );

  test(
    'empty through 1 MB payloads remain byte-exact in both directions',
    () async {
      final channel = _FakePythonBridgeChannel(7);
      final transport = PythonBridgePluginTransport(
        channelLabel: 'plugin.payloads',
        channel: channel,
      );
      await transport.start();
      final received = <Uint8List>[];
      final subscription = transport.messages.listen(received.add);
      final sizes = [0, 1, 1024, 64 * 1024, 1024 * 1024];

      for (final size in sizes) {
        final payload = Uint8List.fromList(
          List<int>.generate(size, (index) => index & 0xff),
        );
        await transport.send(payload);
        channel.controller.add(Uint8List.fromList(payload));
      }
      await pumpEventQueue();

      expect(channel.sent, hasLength(sizes.length));
      expect(received, hasLength(sizes.length));
      for (var index = 0; index < sizes.length; index++) {
        expect(channel.sent[index], received[index]);
        expect(received[index], hasLength(sizes[index]));
      }
      await subscription.cancel();
      await transport.close();
    },
  );

  test(
    'three plugin channels do not cross-route interleaved messages',
    () async {
      final channels = List.generate(
        3,
        (index) => _FakePythonBridgeChannel(index + 10),
      );
      final transports = List.generate(
        3,
        (index) => PythonBridgePluginTransport(
          channelLabel: 'plugin.$index',
          channel: channels[index],
        ),
      );
      await Future.wait(transports.map((transport) => transport.start()));
      final received = List.generate(3, (_) => <int>[]);
      final subscriptions = List.generate(
        3,
        (index) => transports[index].messages.listen(
          (message) => received[index].add(message.single),
        ),
      );

      channels[2].controller.add(Uint8List.fromList([20]));
      channels[0].controller.add(Uint8List.fromList([0]));
      channels[1].controller.add(Uint8List.fromList([10]));
      channels[2].controller.add(Uint8List.fromList([21]));
      await pumpEventQueue();

      expect(received, [
        [0],
        [10],
        [20, 21],
      ]);
      await Future.wait(
        subscriptions.map((subscription) => subscription.cancel()),
      );
      await Future.wait(transports.map((transport) => transport.close()));
    },
  );

  test('one hundred channels can be created and disposed', () async {
    final channels = List.generate(
      100,
      (index) => _FakePythonBridgeChannel(index + 1),
    );
    for (var index = 0; index < channels.length; index++) {
      final transport = PythonBridgePluginTransport(
        channelLabel: 'plugin.$index',
        channel: channels[index],
      );
      await transport.start();
      await transport.close();
    }

    expect(channels.every((channel) => channel.closeEffects == 1), isTrue);
  });
}
