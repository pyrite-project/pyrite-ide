import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/file/board_backend.dart';
import 'package:pyrite_ide/core/services/file/file_transfer_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';

void main() {
  group('BoardFileEntry metadata', () {
    test('exposes size and a usable mtime as DateTime', () {
      final entry = BoardFileEntry(
        path: '/main.py',
        name: 'main.py',
        type: BoardFileEntryType.file,
        size: 42,
        modifiedSeconds: 1700000000,
      );

      expect(entry.isFolder, isFalse);
      expect(entry.size, 42);
      expect(
        entry.modified,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );
    });

    test('zero or negative mtime is treated as "no timestamp"', () {
      // MicroPython ports on RTC-only clocks report 0, which must not become
      // 1970 in the sync diff.
      for (final seconds in [0, -1]) {
        final entry = BoardFileEntry(
          path: '/a.py',
          name: 'a.py',
          type: BoardFileEntryType.file,
          modifiedSeconds: seconds,
        );
        expect(entry.modified, isNull, reason: 'seconds=$seconds');
      }
    });

    test('missing metadata stays null instead of defaulting to 0', () {
      const entry = BoardFileEntry(
        path: '/lib',
        name: 'lib',
        type: BoardFileEntryType.folder,
      );

      expect(entry.size, isNull);
      expect(entry.modifiedSeconds, isNull);
      expect(entry.modified, isNull);
    });
  });

  group('DeviceFreeSpace', () {
    test('unknown sentinel never claims a reported value', () {
      expect(DeviceFreeSpace.unknown.reported, isFalse);
      expect(DeviceFreeSpace.unknown.freeBytes, isNull);
    });

    test('a reported value keeps both fields', () {
      const space = DeviceFreeSpace(freeBytes: 4096, reported: true);

      expect(space.reported, isTrue);
      expect(space.freeBytes, 4096);
    });
  });

  group('transfer mode resolution still holds after the changes', () {
    test('paste REPL forces chunked regardless of preference', () {
      // Guards the backend contract that the new statvfs entry points sit next
      // to; a regression here would silently change every upload.
      expect(
        resolveFileTransferMode(ReplMode.paste, FileTransferMode.streaming),
        FileTransferMode.chunked,
      );
    });
  });
}
