import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/raw_paste_session.dart';

void main() {
  group('RawPasteSession.executeStreaming', () {
    test('streams output through the raw-paste protocol', () async {
      final queue = SerialByteQueue();
      final payload = List.filled(100, 'x').join();
      final code = 'print("$payload")';
      final writtenCode = BytesBuilder(copy: false);
      var executionResponseSent = false;

      final session = RawPasteSession(
        queue: queue,
        writeBytes: (bytes) {
          final copy = List<int>.of(bytes);
          if (_equals(copy, const [0x05, 0x41, 0x01])) {
            queue.add(Uint8List.fromList(const [0x52, 0x01, 0x20, 0x00]));
          } else if (_equals(copy, const [0x04]) && !executionResponseSent) {
            executionResponseSent = true;
            queue.add(
              Uint8List.fromList([
                0x04,
                ...utf8.encode('hello\r\n'),
                0x04,
                0x04,
                0x3e,
              ]),
            );
          } else {
            writtenCode.add(copy);
            queue.add(Uint8List.fromList(const [0x01]));
          }
        },
      );

      var started = false;
      final stdout = BytesBuilder(copy: false);
      final stderr = BytesBuilder(copy: false);

      await session.executeStreaming(
        code,
        startupTimeout: const Duration(seconds: 1),
        onStarted: () => started = true,
        onStdout: stdout.add,
        onStderr: stderr.add,
      );

      expect(started, isTrue);
      expect(utf8.decode(stdout.takeBytes()), 'hello\r\n');
      expect(stderr.length, 0);
      expect(utf8.decode(writtenCode.takeBytes()), code);
    });

    test('falls back to standard raw REPL and reports stderr', () async {
      final queue = SerialByteQueue();
      var executionResponseSent = false;

      final session = RawPasteSession(
        queue: queue,
        writeBytes: (bytes) {
          final copy = List<int>.of(bytes);
          if (_equals(copy, const [0x05, 0x41, 0x01])) {
            queue.add(Uint8List.fromList(const [0x52, 0x00]));
          } else if (_equals(copy, const [0x04]) && !executionResponseSent) {
            executionResponseSent = true;
            queue.add(
              Uint8List.fromList([
                ...utf8.encode('OK'),
                0x04,
                ...utf8.encode('ValueError: bad'),
                0x04,
                0x3e,
              ]),
            );
          }
        },
      );

      var started = false;
      final stderr = BytesBuilder(copy: false);

      await expectLater(
        session.executeStreaming(
          'raise ValueError("bad")',
          startupTimeout: const Duration(seconds: 1),
          onStarted: () => started = true,
          onStdout: (_) {},
          onStderr: stderr.add,
        ),
        throwsA(
          isA<RawPasteException>().having(
            (error) => error.message,
            'message',
            'ValueError: bad',
          ),
        ),
      );

      expect(started, isTrue);
      expect(utf8.decode(stderr.takeBytes()), 'ValueError: bad');
    });
  });
}

bool _equals(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
