import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';

void main() {
  group('DeviceSession.executeStreaming (raw-paste)', () {
    test('streams output through the raw-paste protocol', () async {
      final queue = SerialByteQueue();
      final payload = List.filled(100, 'x').join();
      final code = 'print("$payload")';
      final writtenCode = BytesBuilder(copy: false);
      var executionResponseSent = false;

      final session = DeviceSession(
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
        timeout: const Duration(seconds: 1),
        mode: ReplMode.rawPaste,
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

      final session = DeviceSession(
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

      await expectLater(
        session.executeStreaming(
          'raise ValueError("bad")',
          timeout: const Duration(seconds: 1),
          mode: ReplMode.rawPaste,
          onStarted: () => started = true,
          onStdout: (_) {},
          onStderr: (_) {},
        ),
        throwsA(
          isA<DeviceSessionException>().having(
            (error) => error.message,
            'message',
            'Device rejected raw-paste mode',
          ),
        ),
      );

      expect(started, isFalse);
    });
  });

  group('DeviceSession.executeWithRawInput', () {
    test('streams bytes with sparse ack progress', () async {
      final queue = SerialByteQueue();
      final writes = <List<int>>[];
      final payload = Uint8List.fromList(List<int>.generate(10, (i) => i));
      final progress = <int>[];

      var handshakeDone = false;
      var scriptSubmitted = false;
      var uploaded = 0;
      var uploadChunks = 0;

      void writeBytes(List<int> bytes) {
        writes.add(List<int>.from(bytes));

        // Respond to raw-paste handshake: [0x05, 0x41, 0x01]
        if (!handshakeDone &&
            bytes.length == 3 &&
            bytes[0] == 0x05 &&
            bytes[1] == 0x41 &&
            bytes[2] == 0x01) {
          handshakeDone = true;
          queue.add(Uint8List.fromList(const [0x52, 0x01, 0x20, 0x00]));
          return;
        }

        // CTRL-D from _writeRawPasteCode — code execution starts.
        if (!scriptSubmitted && bytes.length == 1 && bytes[0] == 0x04) {
          scriptSubmitted = true;
          // Device sends CTRL-D (end of initial response), then READY.
          queue.add(Uint8List.fromList(const [0x04]));
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
          // Script done: DONE marker, then stdout CTRL-D, stderr CTRL-D, prompt.
          queue.add(Uint8List.fromList([
            ...utf8.encode('DONE'),
            0x04, // end of stdout
            0x04, // end of stderr
            0x3e, // prompt >
          ]));
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
          // Respond to raw-paste handshake: [0x05, 0x41, 0x01]
          if (bytes.length == 3 &&
              bytes[0] == 0x05 &&
              bytes[1] == 0x41 &&
              bytes[2] == 0x01) {
            // Reject raw-paste
            queue.add(Uint8List.fromList(const [0x52, 0x00]));
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
          isA<DeviceSessionException>().having(
            (error) => error.message,
            'message',
            'Device rejected raw-paste mode',
          ),
        ),
      );
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

bool _endsWith(List<int> value, List<int> suffix) {
  if (value.length < suffix.length) return false;
  final start = value.length - suffix.length;
  for (var i = 0; i < suffix.length; i++) {
    if (value[start + i] != suffix[i]) return false;
  }
  return true;
}
