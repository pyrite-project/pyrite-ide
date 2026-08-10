import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/serial/active_device_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';

void main() {
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
}
