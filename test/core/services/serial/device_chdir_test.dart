import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';

/// Scripted raw-REPL device: CTRL-A answers with the raw banner, any write
/// ending in CTRL-D answers with [response] framed as
/// stdout-EOT + stderr-EOT + raw prompt.
DeviceSession scriptedRawSession({
  required List<int> writes,
  required List<int> response,
  required SerialByteQueue queue,
}) {
  void writeBytes(List<int> bytes) {
    writes.addAll(bytes);
    if (bytes.length == 1 && bytes.single == 0x01) {
      // CTRL-A enters raw REPL.
      queue.add(
        Uint8List.fromList(utf8.encode('raw REPL; CTRL-B to exit\r\n>')),
      );
      return;
    }
    // executeRawCommand sends the code and its terminating CTRL-D as one
    // write (chunked only past 255 bytes).
    if (bytes.isNotEmpty && bytes.last == 0x04) {
      Timer(const Duration(milliseconds: 1), () {
        queue.add(
          Uint8List.fromList([...response, 0x04, 0x04, ...utf8.encode('>')]),
        );
      });
    }
  }

  return DeviceSession(queue: queue, writeBytes: writeBytes);
}

void main() {
  test(
    'setDeviceWorkingDirectory sends os.chdir and accepts the success marker',
    () async {
      final queue = SerialByteQueue();
      final writes = <int>[];
      final session = scriptedRawSession(
        writes: writes,
        response: utf8.encode('OK$kDeviceChdirOkMarker\r\n'),
        queue: queue,
      );

      await session.enterRepl(ReplMode.rawRepl);
      await setDeviceWorkingDirectory(session, '/apps', mode: ReplMode.rawRepl);

      final written = utf8.decode(writes);
      expect(written, contains("os.chdir('/apps')"));
      expect(written, contains(kDeviceChdirOkMarker));
    },
  );

  test(
    'setDeviceWorkingDirectory throws with the device traceback on failure',
    () async {
      final queue = SerialByteQueue();
      final writes = <int>[];
      final session = scriptedRawSession(
        writes: writes,
        response: utf8.encode('OK\r\nOSError: [Errno 2] ENOENT\r\n'),
        queue: queue,
      );

      await session.enterRepl(ReplMode.rawRepl);
      await expectLater(
        setDeviceWorkingDirectory(session, '/missing', mode: ReplMode.rawRepl),
        throwsA(
          isA<DeviceSessionException>().having(
            (error) => error.message,
            'message',
            contains('ENOENT'),
          ),
        ),
      );
    },
  );

  test('quotes directory names with single quotes safely', () async {
    final queue = SerialByteQueue();
    final writes = <int>[];
    final session = scriptedRawSession(
      writes: writes,
      response: utf8.encode('OK$kDeviceChdirOkMarker\r\n'),
      queue: queue,
    );

    await session.enterRepl(ReplMode.rawRepl);
    await setDeviceWorkingDirectory(session, "/it's", mode: ReplMode.rawRepl);

    expect(utf8.decode(writes), contains("os.chdir('/it\\'s')"));
  });
}
