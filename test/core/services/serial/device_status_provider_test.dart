import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/device_status_provider.dart';

const _marker = '__PYRITE_DEVICE_STATUS__';

void main() {
  group('parseDeviceStatusOutput', () {
    test('reads the marker line out of ordinary REPL output', () {
      final status = parseDeviceStatusOutput(
        '>>> \r\n'
        '$_marker{"ram_used": 1024, "ram_total": 4096, '
        '"flash_used": 2048, "flash_total": 8192, '
        '"firmware_version": "v1.22", "platform_model": "esp32"}\r\n',
      );

      expect(status, isNotNull);
      expect(status!.ramUsed, 1024);
      expect(status.ramTotal, 4096);
      expect(status.flashUsed, 2048);
      expect(status.flashTotal, 8192);
      expect(status.firmwareVersion, 'v1.22');
      expect(status.platformModel, 'esp32');
    });

    test('skips a truncated payload and keeps scanning', () {
      // The REPL echoes the script, so a cut-off copy of the payload can land
      // before the complete one; the complete one still has to be read.
      final status = parseDeviceStatusOutput(
        '$_marker{"ram_used": 10, "ram_to\n'
        '$_marker{"ram_used": 11, "ram_total": 22, '
        '"flash_used": 33, "flash_total": 44}\n',
      );

      expect(status, isNotNull);
      expect(status!.ramUsed, 11);
      expect(status.ramTotal, 22);
    });

    test('accepts numeric fields a port reports as floats or strings', () {
      final status = parseDeviceStatusOutput(
        '$_marker{"ram_used": 1.0, "ram_total": "4096", "flash_used": null}\n',
      );

      expect(status, isNotNull);
      expect(status!.ramUsed, 1);
      expect(status.ramTotal, 4096);
      expect(status.flashUsed, 0);
    });

    test('returns null when no marker line is present', () {
      expect(parseDeviceStatusOutput('hello\nworld\n'), isNull);
    });
  });
}
