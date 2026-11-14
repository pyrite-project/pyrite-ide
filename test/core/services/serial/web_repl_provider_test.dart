import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/serial/active_device_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_socket.dart';
import 'package:pyrite_ide/core/services/settings.dart';

/// A WebSocket the test drives frame by frame.
class _FakeWebReplSocket implements WebReplSocket {
  final StreamController<Object> _controller = StreamController<Object>();
  final List<String> sent = <String>[];
  int closeCount = 0;
  bool _closed = false;

  bool get hasListener => _controller.hasListener;

  @override
  Stream<Object> get stream => _controller.stream;

  void emit(Object data) {
    if (!_closed) _controller.add(data);
  }

  @override
  void sendText(String text) => sent.add(text);

  @override
  Future<void> sendBinary(List<int> data) async {}

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    closeCount++;
    // A single-subscription controller that was never listened to never
    // completes its close future, so do not await it here.
    unawaited(_controller.close());
  }
}

/// A connector whose handshakes stay pending until the test completes them.
class _PendingConnector {
  final List<Completer<WebReplSocket>> pending = <Completer<WebReplSocket>>[];

  Future<WebReplSocket> connect(Uri uri) {
    final completer = Completer<WebReplSocket>();
    pending.add(completer);
    return completer.future;
  }
}

ProviderContainer _createContainer(_PendingConnector connector) {
  return ProviderContainer(
    overrides: [
      webReplHost.overrideWith((ref) => '192.168.31.25'),
      webReplPort.overrideWith((ref) => 8266),
      webReplPassword.overrideWith((ref) => 'secret'),
      webReplSocketConnectorProvider.overrideWithValue(connector.connect),
    ],
  );
}

void main() {
  late List<String> output;

  setUp(() {
    output = <String>[];
    replOutputSink = output.add;
  });

  tearDown(() {
    replOutputSink = null;
  });

  test('builds the root WebREPL websocket URL from an IP address', () {
    expect(
      buildWebReplUri('192.168.31.25', 8266),
      Uri.parse('ws://192.168.31.25:8266/'),
    );
  });

  test('normalizes an HTTP device URL to the WebREPL websocket URL', () {
    expect(
      buildWebReplUri('https://192.168.31.25', 8266),
      Uri.parse('ws://192.168.31.25:8266/'),
    );
  });

  test('keeps an explicitly configured port', () {
    expect(
      buildWebReplUri('ws://192.168.31.25:9000/', 8266),
      Uri.parse('ws://192.168.31.25:9000/'),
    );
  });

  test('prefers WebREPL when both transports report connected', () {
    expect(
      resolveActiveDeviceTransport(
        serialConnected: true,
        webReplState: WebReplState.connected,
      ),
      ActiveDeviceTransport.webRepl,
    );
  });

  test('uses serial when WebREPL is disconnected', () {
    expect(
      resolveActiveDeviceTransport(
        serialConnected: true,
        webReplState: WebReplState.disconnected,
      ),
      ActiveDeviceTransport.serial,
    );
  });

  test('reports disconnected when neither transport is connected', () {
    expect(
      resolveActiveDeviceTransport(
        serialConnected: false,
        webReplState: WebReplState.error,
      ),
      ActiveDeviceTransport.disconnected,
    );
  });

  test(
    'can construct the unified transport provider without a dependency cycle',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(activeDeviceTransportProvider),
        ActiveDeviceTransport.disconnected,
      );
    },
  );

  test(
    'rejects a second connect while the first handshake is pending',
    () async {
      final connector = _PendingConnector();
      final container = _createContainer(connector);
      addTearDown(container.dispose);
      final notifier = container.read(webReplProvider.notifier);

      final first = notifier.connect();
      final second = notifier.connect();
      await pumpEventQueue();

      expect(
        connector.pending,
        hasLength(1),
        reason: 'a second tap must not open a second WebSocket',
      );

      final socket = _FakeWebReplSocket();
      connector.pending.single.complete(socket);
      await pumpEventQueue();

      socket.emit('Password: ');
      await pumpEventQueue();
      expect(socket.sent, contains('secret\n'));

      socket.emit('>>> ');
      await pumpEventQueue();
      await first;
      await second;

      expect(notifier.isConnected, isTrue);
      expect(identical(notifier.activeChannel, socket), isTrue);
      expect(socket.closeCount, 0);
      expect(socket.hasListener, isTrue);

      socket.emit('print(1)\r\n');
      await pumpEventQueue();
      expect(output.where((chunk) => chunk == 'print(1)\r\n'), hasLength(1));
    },
  );

  test('closes a socket whose handshake outlives disconnect', () async {
    final connector = _PendingConnector();
    final container = _createContainer(connector);
    addTearDown(container.dispose);
    final notifier = container.read(webReplProvider.notifier);

    final superseded = notifier.connect();
    await pumpEventQueue();
    expect(connector.pending, hasLength(1));

    await notifier.disconnect();

    final late = _FakeWebReplSocket();
    connector.pending.single.complete(late);
    await superseded;
    await pumpEventQueue();

    expect(late.closeCount, 1);
    expect(late.hasListener, isFalse);
    expect(notifier.activeChannel, isNull);
    expect(container.read(webReplProvider).state, WebReplState.disconnected);

    final replacementAttempt = notifier.connect();
    await pumpEventQueue();
    expect(connector.pending, hasLength(2));

    final replacement = _FakeWebReplSocket();
    connector.pending[1].complete(replacement);
    await pumpEventQueue();
    replacement.emit('>>> ');
    await pumpEventQueue();
    await replacementAttempt;

    expect(notifier.isConnected, isTrue);
    expect(identical(notifier.activeChannel, replacement), isTrue);
    expect(replacement.hasListener, isTrue);
    expect(late.closeCount, 1);
  });

  test('a stale handshake cannot replace the active connection', () async {
    final connector = _PendingConnector();
    final container = _createContainer(connector);
    addTearDown(container.dispose);
    final notifier = container.read(webReplProvider.notifier);

    final staleAttempt = notifier.connect();
    await pumpEventQueue();
    await notifier.disconnect();

    final activeAttempt = notifier.connect();
    await pumpEventQueue();
    expect(connector.pending, hasLength(2));

    final active = _FakeWebReplSocket();
    connector.pending[1].complete(active);
    await pumpEventQueue();
    active.emit('>>> ');
    await pumpEventQueue();
    await activeAttempt;
    expect(notifier.isConnected, isTrue);

    final stale = _FakeWebReplSocket();
    connector.pending[0].complete(stale);
    await staleAttempt;
    await pumpEventQueue();

    expect(stale.closeCount, 1);
    expect(stale.hasListener, isFalse);
    expect(identical(notifier.activeChannel, active), isTrue);
    expect(active.closeCount, 0);
    expect(active.hasListener, isTrue);
    expect(notifier.isConnected, isTrue);

    active.emit('still here\r\n');
    await pumpEventQueue();
    expect(output.where((chunk) => chunk == 'still here\r\n'), hasLength(1));
  });

  test('disconnect closes the active socket and its subscription', () async {
    final connector = _PendingConnector();
    final container = _createContainer(connector);
    addTearDown(container.dispose);
    final notifier = container.read(webReplProvider.notifier);

    final attempt = notifier.connect();
    await pumpEventQueue();
    final socket = _FakeWebReplSocket();
    connector.pending.single.complete(socket);
    await pumpEventQueue();
    socket.emit('>>> ');
    await pumpEventQueue();
    await attempt;
    expect(notifier.isConnected, isTrue);

    await notifier.disconnect();
    await pumpEventQueue();

    expect(socket.closeCount, 1);
    expect(socket.hasListener, isFalse);
    expect(notifier.activeChannel, isNull);
    expect(container.read(webReplProvider).state, WebReplState.disconnected);
  });
}
