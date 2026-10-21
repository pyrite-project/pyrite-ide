import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/device/board_identity.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';

void main() {
  group('identifyBoard: VID/PID matching', () {
    test('RP2040 Pico MicroPython CDC maps to rp2040', () {
      final identity = identifyBoard(0x2E8A, 0x0005, 'Raspberry Pi Pico');

      expect(identity.family, BoardFamily.rp2040);
      expect(identity.likelyBaud, 115200);
      expect(identity.resetStrategy, BoardResetStrategy.reopenPort);
      expect(identity.confidence, BoardIdentityConfidence.exact);
      expect(identity.label, contains('Pico'));
    });

    test('Espressif USB-Serial/JTAG maps to ESP32-S3 native USB', () {
      final identity = identifyBoard(0x303A, 0x1001, null);

      expect(identity.family, BoardFamily.esp32s3);
      expect(identity.resetStrategy, BoardResetStrategy.reopenPort);
      expect(identity.confidence, BoardIdentityConfidence.exact);
    });

    test('Espressif ESP32-S2 USB-OTG maps to esp32s2', () {
      final identity = identifyBoard(0x303A, 0x0002, null);

      expect(identity.family, BoardFamily.esp32s2);
    });

    test('MicroPython STM32 PIDs map to stm32 with DTR pulse', () {
      for (final pid in [0x9800, 0x9801, 0x9802, 0x9803]) {
        final identity = identifyBoard(micropythonStmVid, pid, null);
        expect(identity.family, BoardFamily.stm32, reason: 'pid=0x$pid');
        expect(identity.resetStrategy, BoardResetStrategy.dtrPulse);
        expect(identity.likelyBaud, 115200);
      }
    });

    test('RP2040 BOOTSEL has no host-side reset', () {
      final identity = identifyBoard(0x2E8A, 0x0003, null);

      expect(identity.family, BoardFamily.rp2040);
      expect(identity.resetStrategy, BoardResetStrategy.none);
      expect(identity.hardwareResetStrategy, HardwareResetStrategy.disabled);
    });

    test('unknown Espressif PID still resolves to the ESP32 family', () {
      // Espressif allocates a PID per chip; anything else on their VID must
      // still produce native-USB defaults instead of "unknown".
      final identity = identifyBoard(0x303A, 0x9999, 'Espressif Device');

      expect(identity.family, BoardFamily.esp32);
      expect(identity.resetStrategy, BoardResetStrategy.reopenPort);
    });
  });

  group('identifyBoard: description matching', () {
    test('matches ESP32-C3 by description when ids are missing', () {
      final identity = identifyBoard(null, null, 'USB JTAG/serial (ESP32-C3)');

      expect(identity.family, BoardFamily.esp32c3);
      expect(identity.confidence, BoardIdentityConfidence.description);
    });

    test('C6 family is matched independently from C3', () {
      expect(
        identifyBoard(null, null, 'ESP32-C6 dev board').family,
        BoardFamily.esp32c6,
      );
    });

    test('ESP8266 keywords cover common board names', () {
      expect(
        identifyBoard(null, null, 'NodeMCU V3').family,
        BoardFamily.esp8266,
      );
    });

    test('longest keyword wins (ESP32-S3 over ESP32)', () {
      final identity = identifyBoard(null, null, 'ESP32-S3-WROOM-1');
      expect(identity.family, BoardFamily.esp32s3);
    });

    test('K230 CanMV is recognised by description', () {
      final identity = identifyBoard(null, null, 'CanMV K230 USB Serial');
      expect(identity.family, BoardFamily.k230);
    });
  });

  group('identifyBoard: transport-only and unknown', () {
    test('FTDI bridge keeps an unknown family but sane reset defaults', () {
      final identity = identifyBoard(0x0403, 0x6001, 'FT232R USB UART');

      expect(identity.family, BoardFamily.unknown);
      expect(identity.confidence, BoardIdentityConfidence.transportOnly);
      expect(identity.resetStrategy, BoardResetStrategy.esp32);
    });

    test('CP210x and CH34x bridges are recognised by VID', () {
      expect(
        identifyBoard(0x10C4, 0xEA60, '').confidence,
        BoardIdentityConfidence.transportOnly,
      );
      expect(
        identifyBoard(0x1A86, 0x7523, '').confidence,
        BoardIdentityConfidence.transportOnly,
      );
    });

    test('nothing known returns an explicit unknown identity', () {
      final identity = identifyBoard(null, null, null);

      expect(identity.family, BoardFamily.unknown);
      expect(identity.confidence, BoardIdentityConfidence.unknown);
      expect(identity.isKnown, isFalse);
      expect(identity.likelyBaud, defaultBoardBaud);
    });

    test('null description does not throw', () {
      expect(() => identifyBoard(1, 2, null), returnsNormally);
    });
  });

  group('board table integrity', () {
    test('exact VID/PID rows are unique', () {
      final seen = <String>{};
      for (final row in boardTable) {
        if (row.vid == null || row.pid == null) continue;
        final key = '${row.vid}-${row.pid}';
        expect(seen.add(key), isTrue, reason: 'duplicate VID/PID $key');
      }
    });

    test('every row has a positive baud rate and a label', () {
      for (final row in boardTable) {
        expect(row.likelyBaud, greaterThan(0), reason: row.label);
        expect(row.label.trim(), isNotEmpty);
      }
    });

    test('every board family except unknown is covered by the table', () {
      final families = boardTable.map((row) => row.family).toSet();
      for (final family in BoardFamily.values) {
        if (family == BoardFamily.unknown) continue;
        expect(
          families,
          contains(family),
          reason: 'no table row for ${family.name}',
        );
      }
    });
  });

  group('hardware reset mapping', () {
    test('reopenPort never maps to a control-line reset', () {
      const identity = BoardIdentity(
        family: BoardFamily.esp32s3,
        label: 'test',
        likelyBaud: 115200,
        resetStrategy: BoardResetStrategy.reopenPort,
      );

      expect(identity.hardwareResetStrategy, HardwareResetStrategy.disabled);
    });

    test('ESP32 family maps to the esp32 sequence', () {
      const identity = BoardIdentity(
        family: BoardFamily.esp32,
        label: 'test',
        likelyBaud: 115200,
        resetStrategy: BoardResetStrategy.esp32,
      );

      expect(identity.hardwareResetStrategy, HardwareResetStrategy.esp32);
    });
  });
}
