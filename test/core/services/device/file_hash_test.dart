import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/device/file_hash.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pyrite_file_hash_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('crc32OfBytes', () {
    test('matches the standard CRC-32 check values', () {
      expect(crc32OfBytes([]), 0x00000000);
      expect(crc32OfBytes('123456789'.codeUnits), 0xCBF43926);
      expect(
        crc32OfBytes('The quick brown fox jumps over the lazy dog'.codeUnits),
        0x414FA339,
      );
    });

    test('distinguishes same-length payloads', () {
      expect(
        crc32OfBytes('print(1)'.codeUnits),
        isNot(crc32OfBytes('print(2)'.codeUnits)),
      );
    });
  });

  group('crc32OfFile', () {
    test('returns the same value as hashing the bytes directly', () async {
      final file = File(path.join(tempDir.path, 'main.py'));
      await file.writeAsString('print(1)');
      expect(await crc32OfFile(file.path), crc32OfBytes('print(1)'.codeUnits));
    });

    test('returns null for a missing file', () async {
      expect(await crc32OfFile(path.join(tempDir.path, 'missing.py')), isNull);
    });
  });

  group('bytesIdentical', () {
    test('requires equal length and content', () {
      expect(bytesIdentical([1, 2, 3], [1, 2, 3]), isTrue);
      expect(bytesIdentical([1, 2, 3], [1, 2, 4]), isFalse);
      expect(bytesIdentical([1, 2], [1, 2, 3]), isFalse);
      expect(bytesIdentical(<int>[], <int>[]), isTrue);
    });
  });
}
