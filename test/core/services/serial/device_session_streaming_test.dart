import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';

void main() {
  test(
    'paste mode tolerates a prompt before the delayed WebREPL banner',
    () async {
      final queue = SerialByteQueue();
      final writes = <List<int>>[];
      queue.add(Uint8List.fromList(utf8.encode('>>> ')));

      void writeBytes(List<int> bytes) {
        writes.add(List<int>.from(bytes));
        if (bytes.length == 1 && bytes.single == 0x05) {
          queue.add(Uint8List.fromList(utf8.encode('>>> ')));
          Timer(const Duration(milliseconds: 1), () {
            queue.add(
              Uint8List.fromList(
                utf8.encode(
                  'paste mode; Ctrl-C to cancel, Ctrl-D to finish\r\n=== ',
                ),
              ),
            );
          });
        }
      }

      final session = DeviceSession(queue: queue, writeBytes: writeBytes);
      await session.enterRepl(
        ReplMode.paste,
        timeout: const Duration(seconds: 1),
      );

      expect(
        writes.any((bytes) => bytes.length == 1 && bytes.single == 0x05),
        isTrue,
      );
    },
  );

  test('raw streaming consumes protocol acknowledgement and framing', () async {
    final queue = SerialByteQueue();
    final writes = <List<int>>[];

    void writeBytes(List<int> bytes) {
      writes.add(List<int>.from(bytes));
      if (bytes.length == 1 && bytes.single == 0x01) {
        queue.add(
          Uint8List.fromList(utf8.encode('raw REPL; CTRL-B to exit\r\n>')),
        );
      } else if (bytes.length == 1 && bytes.single == 0x04) {
        queue.add(
          Uint8List.fromList([
            ...utf8.encode('OKhello\r\n'),
            0x04,
            ...utf8.encode('traceback\r\n'),
            0x04,
            0x3e,
          ]),
        );
      }
    }

    final stdout = <int>[];
    final stderr = <int>[];
    final session = DeviceSession(queue: queue, writeBytes: writeBytes);

    await session.enterRepl(ReplMode.rawRepl);
    await session.executeStreaming(
      'print("hello")',
      mode: ReplMode.rawRepl,
      onStarted: () {},
      onStdout: stdout.addAll,
      onStderr: stderr.addAll,
    );

    expect(utf8.decode(stdout), 'hello\r\n');
    expect(utf8.decode(stderr), 'traceback\r\n');
    expect(utf8.decode(stdout), isNot(contains('OK')));
    expect(
      writes.any((bytes) => bytes.length == 1 && bytes[0] == 0x01),
      isTrue,
    );
  });

  test(
    'softReset sends CTRL-B + CTRL-D and waits for the reboot banner',
    () async {
      final queue = SerialByteQueue();
      final writes = <List<int>>[];

      void writeBytes(List<int> bytes) {
        writes.add(List<int>.from(bytes));
        if (bytes.length == 1 && bytes.single == 0x04) {
          Timer(const Duration(milliseconds: 1), () {
            queue.add(
              Uint8List.fromList(utf8.encode('MPY: soft reboot\r\n>>> ')),
            );
          });
        }
      }

      final session = DeviceSession(queue: queue, writeBytes: writeBytes);
      await session.softReset(timeout: const Duration(seconds: 2));

      expect(
        writes.any((bytes) => bytes.length == 1 && bytes.single == 0x02),
        isTrue,
      );
      expect(
        writes.any((bytes) => bytes.length == 1 && bytes.single == 0x04),
        isTrue,
      );
    },
  );

  test(
    'softReset falls back to the prompt when the banner is missing',
    () async {
      final queue = SerialByteQueue();

      void writeBytes(List<int> bytes) {
        if (bytes.length == 1 && bytes.single == 0x04) {
          // A quietly resetting build only answers with a fresh prompt.
          Timer(const Duration(milliseconds: 1), () {
            queue.add(Uint8List.fromList(utf8.encode('>>> ')));
          });
        }
      }

      final session = DeviceSession(queue: queue, writeBytes: writeBytes);
      await session.softReset(timeout: const Duration(milliseconds: 200));
    },
  );

  test('paste execution sends conservative WebREPL-sized blocks', () async {
    final queue = SerialByteQueue();
    final writes = <List<int>>[];
    queue.add(Uint8List.fromList(utf8.encode('>>> ')));

    void writeBytes(List<int> bytes) {
      writes.add(List<int>.from(bytes));
      if (bytes.length == 1 && bytes.single == 0x05) {
        queue.add(Uint8List.fromList(utf8.encode('paste mode\r\n=== ')));
      } else if (bytes.length == 1 && bytes.single == 0x04) {
        queue.add(
          Uint8List.fromList(
            utf8.encode(
              '__PYRITE_NORMAL_REPL_START__\r\n'
              '__PYRITE_NORMAL_REPL_END__\r\n>>> ',
            ),
          ),
        );
      } else {
        final echo = <int>[];
        for (var index = 0; index < bytes.length; index++) {
          final byte = bytes[index];
          echo.add(byte);
          if (byte == 0x0A && index > 0 && bytes[index - 1] == 0x0D) {
            echo.add(0x0A);
            echo.addAll(const [0x3D, 0x3D, 0x3D, 0x20]);
          }
        }
        queue.add(Uint8List.fromList(echo));
      }
    }

    final session = DeviceSession(
      queue: queue,
      writeBytes: writeBytes,
      waitForPasteEcho: true,
    );
    await session.enterRepl(ReplMode.paste);
    await session.executeStreaming(
      'value = "${List.filled(500, 'x').join()}"',
      mode: ReplMode.paste,
      onStarted: () {},
      onStdout: (_) {},
      onStderr: (_) {},
    );

    final payloads = writes.where((bytes) => bytes.length > 1).toList();
    expect(payloads.length, greaterThan(1));
    expect(payloads.every((bytes) => bytes.length <= 127), isTrue);
  });

  test('an empty raw attempt returns and releases the lock instead of waiting '
      'for a frame the device never sends', () async {
    final queue = SerialByteQueue();
    final mutex = ReplMutex();
    final writes = <List<int>>[];

    // An empty raw line makes MicroPython print OK and leave the raw REPL
    // (PYEXEC_FORCED_EXIT) without the stdout/stderr EOT framing.
    void writeBytes(List<int> bytes) {
      writes.add(List<int>.from(bytes));
      if (bytes.length == 1 && bytes.single == 0x04) {
        queue.add(Uint8List.fromList(utf8.encode('OK')));
      }
    }

    final session = DeviceSession(queue: queue, writeBytes: writeBytes);
    var started = 0;
    final execution = mutex.runExclusive(
      () => session.executeStreaming(
        '',
        timeout: const Duration(milliseconds: 200),
        mode: ReplMode.rawRepl,
        onStarted: () => started++,
        onStdout: (_) {},
        onStderr: (_) {},
      ),
    );

    await execution.timeout(const Duration(seconds: 2));
    expect(started, 1);
    expect(writes, isEmpty);
    expect(mutex.isLocked, isFalse);
    expect(await mutex.runExclusive(() async => 'acquired'), 'acquired');
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('raw streaming gives up when the device never frames stdout', () async {
    final queue = SerialByteQueue();
    final mutex = ReplMutex();

    void writeBytes(List<int> bytes) {
      if (bytes.length == 1 && bytes.single == 0x04) {
        // The command is acknowledged but execution never terminates.
        queue.add(Uint8List.fromList(utf8.encode('OK')));
      }
    }

    final session = DeviceSession(queue: queue, writeBytes: writeBytes);
    final execution = mutex.runExclusive(
      () => session.executeStreaming(
        'print(1)',
        timeout: const Duration(milliseconds: 150),
        mode: ReplMode.rawRepl,
        onStarted: () {},
        onStdout: (_) {},
        onStderr: (_) {},
      ),
    );

    await expectLater(execution, throwsA(isA<TimeoutException>()));
    expect(mutex.isLocked, isFalse);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('empty raw commands return without writing to the device', () async {
    final queue = SerialByteQueue();
    final writes = <List<int>>[];

    void writeBytes(List<int> bytes) {
      writes.add(List<int>.from(bytes));
    }

    final session = DeviceSession(queue: queue, writeBytes: writeBytes);
    final output = await session
        .executeCommand(
          '  \r\n\t',
          timeout: const Duration(milliseconds: 200),
          mode: ReplMode.rawRepl,
        )
        .timeout(const Duration(seconds: 2));

    expect(output, isEmpty);
    expect(writes, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 5)));

  testWidgets(
    'an empty source completes without opening a device transaction',
    (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, child) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      var started = false;
      await runPythonOnDeviceStreaming(
        capturedRef,
        '  \n\t',
        onStarted: () => started = true,
        onStdout: (_) {},
        onStderr: (_) {},
      ).timeout(const Duration(seconds: 2));

      expect(started, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}
