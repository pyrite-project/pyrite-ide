import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';

void main() {
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
}
