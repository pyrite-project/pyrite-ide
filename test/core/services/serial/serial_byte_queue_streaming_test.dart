import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';

void main() {
  test(
    'readUntilStreaming times out on silence, not on total runtime',
    () async {
      final queue = SerialByteQueue();
      final received = <int>[];
      const terminator = 0x03;

      // Ten chunks 30 ms apart: the read lasts about 330 ms while never sitting
      // idle for the 100 ms timeout.
      final timer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
        queue.add(Uint8List.fromList([0x61]));
        if (timer.tick >= 10) {
          timer.cancel();
          queue.add(Uint8List.fromList([terminator]));
        }
      });
      addTearDown(timer.cancel);

      await queue.readUntilStreaming(
        const [terminator],
        timeout: const Duration(milliseconds: 100),
        onData: received.addAll,
      );

      expect(received, hasLength(10));
      expect(queue.availableLength, 0);
    },
  );

  test('readUntilStreaming still fails after a silent device', () async {
    final queue = SerialByteQueue();

    await expectLater(
      queue.readUntilStreaming(
        const [0x03],
        timeout: const Duration(milliseconds: 30),
        onData: (_) {},
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
