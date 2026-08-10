import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/file/file_rename.dart';
import 'package:pyrite_ide/core/services/file/local_backend.dart' as local;

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'pyrite_local_rename_test_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('renaming a file refuses to overwrite an existing file', () async {
    final source = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}a.py',
    );
    final target = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}b.py',
    );
    await source.writeAsString('source');
    await target.writeAsString('target');

    await expectLater(
      local.renameFile(source.path, 'b.py'),
      throwsA(
        isA<FileRenameTargetExistsException>().having(
          (error) => error.targetPath,
          'targetPath',
          target.path,
        ),
      ),
    );

    expect(await source.readAsString(), 'source');
    expect(await target.readAsString(), 'target');
  });

  test(
    'renaming a file returns the new path and preserves its content',
    () async {
      final source = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}a.py',
      );
      await source.writeAsString('print(1)');

      final targetPath = await local.renameFile(source.path, 'b.py');

      expect(await source.exists(), isFalse);
      expect(await File(targetPath).readAsString(), 'print(1)');
    },
  );

  test('renaming a folder refuses to overwrite an existing folder', () async {
    final source = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}source',
    );
    final target = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}target',
    );
    await source.create();
    await target.create();
    await File(
      '${source.path}${Platform.pathSeparator}source.py',
    ).writeAsString('source');
    await File(
      '${target.path}${Platform.pathSeparator}target.py',
    ).writeAsString('target');

    await expectLater(
      local.renameDir(source.path, 'target'),
      throwsA(isA<FileRenameTargetExistsException>()),
    );

    expect(await source.exists(), isTrue);
    expect(await target.exists(), isTrue);
    expect(
      await File('${source.path}${Platform.pathSeparator}source.py').exists(),
      isTrue,
    );
    expect(
      await File('${target.path}${Platform.pathSeparator}target.py').exists(),
      isTrue,
    );
  });
}
