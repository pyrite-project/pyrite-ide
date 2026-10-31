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
      // 设备侧计的是 Base64 传输行携带的 payload 字节，不是写出的行长度：
      // 每行是 "<base64>\n"，4 字节 payload 编码成 8 个字符 + 换行 = 9 字节。
      // 旧实现用 bytes.length 累加，第 2 行时 uploaded=9 已经越过 10 字节的
      // payload，于是既不注入 '+'，也不再发 DONE，第 2 次 ACK 等待必然超时。
      // 这里改成解析收到的 Base64 行，按解码后的 payload 字节累加。
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

        // 传输阶段写出的一律是 Base64 文本行。非 Base64 行（例如控制字节）
        // 不计入 payload 进度。
        final line = utf8.decode(bytes, allowMalformed: true).trim();
        if (line.isEmpty) return;
        final Uint8List chunk;
        try {
          chunk = base64Decode(line);
        } on FormatException {
          return;
        }
        if (chunk.isEmpty) return;

        uploaded += chunk.length;
        uploadChunks += 1;
        if (uploadChunks == 2 && uploaded < payload.length) {
          queue.add(Uint8List.fromList(utf8.encode('+')));
        }
        if (uploaded >= payload.length) {
          // Script done: the device answers with DONE, then the raw-REPL
          // trailer, which `executeWithRawInput` consumes as
          // stdout-EOT / stderr-EOT / prompt. 之前这份 mock 只注入了 DONE，
          // 少了后面这三个字节，`executeWithRawInput` 会在读 stdout 的 EOT
          // 时一直等下去；生产端协议（a49aa21 起的 device_executor.dart）
          // 明确会继续读 EOT+EOT+prompt，所以这是测试过期，不是产品 bug。
          queue.add(
            Uint8List.fromList([
              ...utf8.encode('DONE'),
              0x04, // end of stdout
              0x04, // end of stderr (empty)
              0x3e, // prompt ">"
            ]),
          );
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

    test('splits large chunks into short paced stdin lines', () async {
      // 长行会把设备端 USB CDC 接收缓冲冲爆（GC/flash 写造成 VM 停顿的瞬间
      // 驱动丢字节，设备端报 "incorrect padding"），所以每个 chunk 必须拆成
      // ≤256 字符的短行、行间留出间歇，而 ACK 仍按 chunk 粒度等待。
      final queue = SerialByteQueue();
      final writes = <List<int>>[];
      final payload = Uint8List.fromList(
        List<int>.generate(4096, (i) => (i * 7 + 3) & 0xFF),
      );
      const chunkSize = 2048;

      var decodedTotal = 0;
      var scriptSubmitted = false;

      void finishTransfer() {
        queue.add(
          Uint8List.fromList([...utf8.encode('DONE'), 0x04, 0x04, 0x3e]),
        );
      }

      void writeBytes(List<int> bytes) {
        writes.add(List<int>.from(bytes));

        if (!scriptSubmitted && bytes.length == 1 && bytes[0] == 0x04) {
          scriptSubmitted = true;
          queue.add(Uint8List.fromList(utf8.encode('READY')));
          return;
        }
        if (!scriptSubmitted || decodedTotal >= payload.length) return;

        final line = utf8.decode(bytes, allowMalformed: true).trim();
        if (line.isEmpty) return;
        final Uint8List chunk;
        try {
          chunk = base64Decode(line);
        } on FormatException {
          return;
        }
        if (chunk.isEmpty) return;

        decodedTotal += chunk.length;
        if (decodedTotal % chunkSize == 0) {
          // One '+' per completed chunk boundary (including the last one),
          // like the device script with ackEvery=1.
          queue.add(Uint8List.fromList(utf8.encode('+')));
        }
        if (decodedTotal >= payload.length) {
          finishTransfer();
        }
      }

      final session = DeviceSession(writeBytes: writeBytes, queue: queue);

      await session.executeWithRawInput(
        'print("receiver")',
        payload,
        startupTimeout: const Duration(seconds: 1),
        completionTimeout: const Duration(seconds: 5),
        readyMarker: utf8.encode('READY'),
        doneMarker: utf8.encode('DONE'),
        chunkSize: chunkSize,
        ackEvery: 1,
      );

      expect(decodedTotal, payload.length);

      // 每个数据行都是一行 base64 文本 + 换行，且不超过 256 个 base64 字符。
      final dataWrites = writes
          .skip(1)
          .where((bytes) => bytes.length > 1 || bytes[0] != 0x04)
          .toList();
      expect(dataWrites, isNotEmpty);
      for (final bytes in dataWrites) {
        expect(bytes.last, 0x0A, reason: 'line must end with a newline');
        expect(
          bytes.length - 1,
          lessThanOrEqualTo(256),
          reason: 'base64 lines must stay within the device buffer',
        );
        expect(
          () => base64Decode(utf8.decode(bytes.sublist(0, bytes.length - 1))),
          returnsNormally,
        );
      }
      // 每个 chunk 的行数与解码总长：2048B -> 2732 chars -> 11 行。
      final base64Chars = ((chunkSize + 2) ~/ 3) * 4;
      expect(
        dataWrites.length,
        (payload.length / chunkSize).ceil() * ((base64Chars + 255) ~/ 256),
      );
    });

    test('surfaces device write errors during the ACK wait', () async {
      final queue = SerialByteQueue();
      final payload = Uint8List.fromList(List<int>.generate(8, (i) => i));

      var scriptSubmitted = false;
      var decodedTotal = 0;

      void writeBytes(List<int> bytes) {
        if (!scriptSubmitted && bytes.length == 1 && bytes[0] == 0x04) {
          scriptSubmitted = true;
          queue.add(Uint8List.fromList(utf8.encode('READY')));
          return;
        }
        if (!scriptSubmitted || decodedTotal >= payload.length) return;

        final line = utf8.decode(bytes, allowMalformed: true).trim();
        if (line.isEmpty) return;
        final Uint8List chunk;
        try {
          chunk = base64Decode(line);
        } on FormatException {
          return;
        }
        decodedTotal += chunk.length;
        // 设备端写入失败：不发 '+'，直接报告错误。ACK 等待必须立即抛出
        // 真实原因，而不是耗尽 completionTimeout 后报笼统的 ACK 超时。
        queue.add(
          Uint8List.fromList(
            utf8.encode(
              '[DEV-LOG] ERROR: boom\nPYRITE_WRITE_ERR:boom\nPYRITE_WRITE_DONE',
            ),
          ),
        );
      }

      final session = DeviceSession(writeBytes: writeBytes, queue: queue);

      await expectLater(
        session.executeWithRawInput(
          'print("receiver")',
          payload,
          startupTimeout: const Duration(seconds: 1),
          completionTimeout: const Duration(seconds: 2),
          readyMarker: utf8.encode('READY'),
          doneMarker: utf8.encode('DONE'),
          chunkSize: 8,
          ackEvery: 1,
        ),
        throwsA(
          isA<DeviceSessionException>().having(
            (e) => e.message,
            'message',
            contains('PYRITE_WRITE_ERR:boom'),
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
