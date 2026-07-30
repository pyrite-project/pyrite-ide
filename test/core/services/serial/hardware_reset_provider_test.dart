import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';

void main() {
  test('ESP32 reset releases GPIO0 throughout the EN pulse', () async {
    final events = <String>[];

    await applyHardwareResetSequence(
      HardwareResetStrategy.esp32,
      setDtr: (active) async => events.add('DTR=$active'),
      setRts: (active) async => events.add('RTS=$active'),
      delay: (duration) async => events.add('wait=${duration.inMilliseconds}'),
    );

    expect(events, <String>[
      'DTR=false',
      'RTS=false',
      'wait=50',
      'RTS=true',
      'wait=150',
      'RTS=false',
    ]);
    expect(events, isNot(contains('DTR=true')));
  });

  test(
    'single-line reset strategies release the line after the pulse',
    () async {
      Future<List<String>> run(HardwareResetStrategy strategy) async {
        final events = <String>[];
        await applyHardwareResetSequence(
          strategy,
          setDtr: (active) async => events.add('DTR=$active'),
          setRts: (active) async => events.add('RTS=$active'),
          delay: (duration) async =>
              events.add('wait=${duration.inMilliseconds}'),
        );
        return events;
      }

      expect(await run(HardwareResetStrategy.dtrPulse), <String>[
        'DTR=false',
        'wait=50',
        'DTR=true',
        'wait=120',
        'DTR=false',
      ]);
      expect(await run(HardwareResetStrategy.rtsPulse), <String>[
        'RTS=false',
        'wait=50',
        'RTS=true',
        'wait=120',
        'RTS=false',
      ]);
    },
  );
}
