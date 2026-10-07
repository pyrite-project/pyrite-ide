import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/file_open_codec.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('file_open_codec_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  File write(String name, List<int> bytes) {
    final file = File('${tempDir.path}/$name')..createSync();
    file.writeAsBytesSync(bytes);
    return file;
  }

  group('prepareFileForEditing', () {
    test('classifies clean UTF-8 text as text', () async {
      final file = write('hello.py', utf8.encode('print("你好")\n'));
      final prepared = await prepareFileForEditing(file);
      expect(prepared, isA<TextFilePrepared>());
      expect(prepared.text, 'print("你好")\n');
      expect(prepared.readOnly, isFalse);
    });

    test(
      'classifies NUL-carrying bytes as binary and forces read-only',
      () async {
        final file = write('blob.bin', [0x4D, 0x5A, 0x00, 0x90, 0x00, 0x03]);
        final prepared = await prepareFileForEditing(file);
        expect(prepared, isA<BinaryFilePrepared>());
        expect(prepared.readOnly, isTrue);
      },
    );

    test('classifies non-UTF-8 text without NULs as undecodable', () async {
      final file = write('gbk.txt', gbk.encode('你好，世界'));
      final prepared = await prepareFileForEditing(file);
      expect(prepared, isA<UndecodableFilePrepared>());
    });

    test('honors a UTF-16 LE BOM before the NUL heuristic', () async {
      const expected = '你好';
      final units = expected.codeUnits;
      final bytes = BytesBuilder()
        ..add([0xFF, 0xFE])
        ..add([units[0] & 0xFF, units[0] >> 8, units[1] & 0xFF, units[1] >> 8]);
      final file = write('utf16le.txt', bytes.toBytes());
      final prepared = await prepareFileForEditing(file);
      expect(prepared, isA<TextFilePrepared>());
      expect(prepared.text, expected);
    });

    test('marks oversized files read-only but still decodes them', () async {
      final big = utf8.encode('# ${'x' * 100}\n' * 60 * 1024);
      final file = write('big.py', big);
      final prepared = await prepareFileForEditing(file);
      expect(prepared, isA<LargeFilePrepared>());
      expect(prepared.readOnly, isTrue);
      expect(prepared.text.length, greaterThan(0));
    });
  });

  group('decodeWithEncoding', () {
    test('decodes GBK bytes', () {
      const expected = '你好，世界';
      expect(
        decodeWithEncoding(Uint8List.fromList(gbk.encode(expected)), 'gbk'),
        expected,
      );
    });

    test('decodes UTF-16 LE and BE', () {
      const expected = 'AB你';
      final le = BytesBuilder();
      for (final unit in expected.codeUnits) {
        le.add([unit & 0xFF, unit >> 8]);
      }
      expect(
        decodeWithEncoding(le.toBytes(), 'utf16le'),
        expected,
        reason: 'no-BOM UTF-16 LE text decodes via the retry path',
      );

      final be = BytesBuilder();
      for (final unit in expected.codeUnits) {
        be.add([unit >> 8, unit & 0xFF]);
      }
      expect(decodeWithEncoding(be.toBytes(), 'utf16be'), expected);
    });

    test('Latin-1 accepts every byte', () {
      final all = Uint8List.fromList(List.generate(256, (i) => i));
      expect(decodeWithEncoding(all, 'latin1'), isNotNull);
    });

    test('unknown encoding returns null', () {
      expect(decodeWithEncoding(Uint8List.fromList([1, 2]), 'klingon'), isNull);
    });
  });

  group('prepareFileForEditing reports the encoding to write back', () {
    test('a plain UTF-8 file comes back as utf8 with no BOM', () async {
      final file = write('plain.py', utf8.encode('print("hi")\n'));
      final prepared = await prepareFileForEditing(file) as TextFilePrepared;
      expect(prepared.encoding, 'utf8');
      expect(prepared.byteOrderMark, isFalse);
    });

    test('a UTF-8 BOM is remembered so a save does not strip it', () async {
      final file = write('bom.py', [
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('x = 1\n'),
      ]);
      final prepared = await prepareFileForEditing(file) as TextFilePrepared;
      expect(prepared.text, 'x = 1\n');
      expect(prepared.encoding, 'utf8');
      expect(prepared.byteOrderMark, isTrue);
    });

    test('each UTF-16 byte order is reported with its own encoding', () async {
      const expected = '你好';
      final le = <int>[
        0xFF,
        0xFE,
        for (final u in expected.codeUnits) ...[u & 0xFF, u >> 8],
      ];
      final lePrepared =
          await prepareFileForEditing(write('le.txt', le)) as TextFilePrepared;
      expect(lePrepared.text, expected);
      expect(lePrepared.encoding, 'utf16le');
      expect(lePrepared.byteOrderMark, isTrue);

      final be = <int>[
        0xFE,
        0xFF,
        for (final u in expected.codeUnits) ...[u >> 8, u & 0xFF],
      ];
      final bePrepared =
          await prepareFileForEditing(write('be.txt', be)) as TextFilePrepared;
      expect(bePrepared.text, expected);
      expect(bePrepared.encoding, 'utf16be');
      expect(bePrepared.byteOrderMark, isTrue);
    });

    test('a binary file carries no encoding', () async {
      final file = write('blob.bin', [0x4D, 0x5A, 0x00, 0x90]);
      final prepared = await prepareFileForEditing(file) as BinaryFilePrepared;
      expect(prepared.encoding, isNull);
      expect(prepared.byteOrderMark, isFalse);
    });
  });

  group('encodeFileText', () {
    test('UTF-8 without a BOM emits no BOM', () {
      expect(
        encodeFileText('x = 1\n', encoding: 'utf8', byteOrderMark: false),
        utf8.encode('x = 1\n'),
      );
    });

    test('UTF-8 with a BOM prepends it', () {
      expect(encodeFileText('x = 1\n', encoding: 'utf8', byteOrderMark: true), [
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('x = 1\n'),
      ]);
    });

    test('GBK round-trips through the decoder it came from', () {
      const expected = '你好，世界';
      final bytes = encodeFileText(
        expected,
        encoding: 'gbk',
        byteOrderMark: false,
      );
      expect(gbk.decode(bytes), expected);
      // The whole point of carrying the encoding: UTF-8 would have produced
      // three bytes per character and silently transcoded the file.
      expect(bytes.length, lessThan(utf8.encode(expected).length));
    });

    test('UTF-16 LE round-trips including characters outside the BMP', () {
      const expected = 'A你\u{1F600}';
      final bytes = encodeFileText(
        expected,
        encoding: 'utf16le',
        byteOrderMark: true,
      );
      expect(bytes.take(2), [0xFF, 0xFE]);
      expect(
        decodeWithEncoding(Uint8List.fromList(bytes), 'utf16le'),
        expected,
      );
    });

    test('UTF-16 BE round-trips with the big-endian BOM', () {
      const expected = 'A你\u{1F600}';
      final bytes = encodeFileText(
        expected,
        encoding: 'utf16be',
        byteOrderMark: true,
      );
      expect(bytes.take(2), [0xFE, 0xFF]);
      expect(
        decodeWithEncoding(Uint8List.fromList(bytes), 'utf16be'),
        expected,
      );
    });

    test('Latin-1 round-trips every byte value it can represent', () {
      const expected = 'café';
      final bytes = encodeFileText(
        expected,
        encoding: 'latin1',
        byteOrderMark: false,
      );
      expect(bytes, expected.codeUnits);
    });

    test(
      'an unencodable character falls back to UTF-8 rather than throwing',
      () {
        // A Chinese character has no Latin-1 byte. Losing the file to an
        // exception at save time is worse than writing a transcoded copy.
        final bytes = encodeFileText(
          '你',
          encoding: 'latin1',
          byteOrderMark: false,
        );
        expect(bytes, utf8.encode('你'));
      },
    );

    test('an unknown encoding falls back to UTF-8', () {
      expect(
        encodeFileText('x', encoding: 'klingon', byteOrderMark: false),
        utf8.encode('x'),
      );
    });

    test('a null encoding with a BOM request still writes UTF-8 + BOM', () {
      expect(encodeFileText('x', encoding: null, byteOrderMark: true), [
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('x'),
      ]);
    });
  });
}
