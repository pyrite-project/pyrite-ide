import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/raw_paste_session.dart';

void main() {
  group('RawPasteSession.executeWithRawInput', () {
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

        if (!scriptSubmitted && bytes.length == 1 && bytes[0] == 0x04) {
          scriptSubmitted = true;
          queue.add(Uint8List.fromList(utf8.encode('OKREADY')));
          return;
        }

        if (!scriptSubmitted || uploaded >= payload.length) return;

        uploaded += bytes.length;
        uploadChunks += 1;
        if (uploadChunks == 2 && uploaded < payload.length) {
          queue.add(Uint8List.fromList(utf8.encode('+')));
        }
        if (uploaded >= payload.length) {
          queue.add(Uint8List.fromList(utf8.encode('DONE')));
          queue.add(Uint8List.fromList([0x04, 0x04, 0x3e]));
        }
      }

      final session = RawPasteSession(writeBytes: writeBytes, queue: queue);

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
      var scriptSubmitted = false;

      final session = RawPasteSession(
        queue: queue,
        writeBytes: (bytes) {
          if (!scriptSubmitted && bytes.length == 1 && bytes[0] == 0x04) {
            scriptSubmitted = true;
            queue.add(
              Uint8List.fromList([
                ...utf8.encode('OK'),
                0x04,
                ...utf8.encode('SyntaxError: invalid syntax'),
                0x04,
                0x3e,
              ]),
            );
          }
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
        throwsA(
          isA<RawPasteException>().having(
            (error) => error.message,
            'message',
            'SyntaxError: invalid syntax',
          ),
        ),
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
