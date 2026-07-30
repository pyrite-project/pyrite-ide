import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';

void main() {
  group('DeviceSession.executeWithRawInput', () {
    test('streams bytes with sparse ack progress', () async {
      final queue = SerialByteQueue();
      final writes = <List<int>>[];
      final payload = Uint8List.fromList(List<int>.generate(10, (i) => i));
      final progress = <int>[];

      var scriptSubmitted = false;
      var uploaded = 0;
      var uploadChunks = 0;

      void writeBytes(List<int> bytes) {
        writes.add(List<int>.from(bytes));

        // CTRL-D from executeWithRawInput — code execution starts.
        if (!scriptSubmitted && bytes.length == 1 && bytes[0] == 0x04) {
          scriptSubmitted = true;
          // Device sends READY marker.
          queue.add(Uint8List.fromList(utf8.encode('READY')));
          return;
        }

        if (!scriptSubmitted || uploaded >= payload.length) return;

        uploaded += bytes.length;
        uploadChunks += 1;
        if (uploadChunks == 2 && uploaded < payload.length) {
          queue.add(Uint8List.fromList(utf8.encode('+')));
        }
        if (uploaded >= payload.length) {
          // Script done: DONE marker.
          queue.add(Uint8List.fromList(utf8.encode('DONE')));
        }
      }

      final session = DeviceSession(writeBytes: writeBytes, queue: queue);

      await session.executeWithRawInput(
        'print("receiver")',
        payload,
        startupTimeout: const Duration(seconds: 1),
        completionTimeout: const Duration(seconds: 1),
        readyMarker: utf8.encode('READY'),
        doneMarker: utf8.encode('DONE'),
        chunkSize: 4,
        ackEvery: 2,
        onProgress: (sent, total) {
          expect(total, payload.length);
          progress.add(sent);
        },
      );

      expect(progress, [4, 8, 10]);
      expect(uploaded, payload.length);
      expect(writes.any((bytes) => _endsWith(bytes, const [0x04])), isTrue);
    });

    test('reports receiver errors before READY', () async {
      final queue = SerialByteQueue();

      final session = DeviceSession(
        queue: queue,
        writeBytes: (bytes) {
          // Simulate error before READY marker.
        },
      );

      await expectLater(
        session.executeWithRawInput(
          'invalid python',
          Uint8List(0),
          startupTimeout: const Duration(seconds: 1),
          completionTimeout: const Duration(seconds: 1),
          readyMarker: utf8.encode('READY'),
          doneMarker: utf8.encode('DONE'),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}

bool _endsWith(List<int> value, List<int> suffix) {
  if (value.length < suffix.length) return false;
  final start = value.length - suffix.length;
  for (var i = 0; i < suffix.length; i++) {
    if (value[start + i] != suffix[i]) return false;
  }
  return true;
}
