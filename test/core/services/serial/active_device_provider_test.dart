import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/active_device_provider.dart';

void main() {
  group('webReplDeviceLabel', () {
    test('names the host and the port in use', () {
      expect(webReplDeviceLabel('192.168.1.5', 8266), 'WebREPL 192.168.1.5:8266');
    });

    test('honors a port written into the host field', () {
      expect(webReplDeviceLabel('board.local:9000', 8266), 'WebREPL board.local:9000');
    });

    test('degrades instead of throwing when the host was cleared', () {
      // The setting can be emptied while a session is still connected; the
      // label provider must not throw and take the status bar down with it.
      expect(webReplDeviceLabel('   ', 8266), 'WebREPL');
    });

    test('keeps an unparseable host visible for the user to fix', () {
      expect(webReplDeviceLabel(':::', 8266), 'WebREPL :::');
    });
  });
}
