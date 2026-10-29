import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/file/file_rename.dart';
import 'package:pyrite_ide/core/services/file/local_backend.dart';

/// Whether the volume holding [dir] treats path casing as insignificant.
///
/// Case-only renames are only meaningful there; on a case-sensitive volume
/// `Foo.py` and `foo.py` are two different files and the collision check is
/// supposed to fire.
Future<bool> _isCaseInsensitive(Directory dir) async {
  final probe = File(path.join(dir.path, 'CaseProbe'));
  await probe.writeAsString('');
  final found = await File(path.join(dir.path, 'caseprobe')).exists();
  await probe.delete();
  return found;
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pyrite_rename_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('renames a file to a different name', () async {
    final source = File(path.join(temp.path, 'a.py'));
    await source.writeAsString('print(1)');

    final renamed = await renameFile(source.path, 'b.py');

    expect(path.basename(renamed), 'b.py');
    expect(await File(renamed).readAsString(), 'print(1)');
    expect(await source.exists(), isFalse);
  });

  test('refuses to overwrite an existing sibling', () async {
    final source = File(path.join(temp.path, 'a.py'));
    final existing = File(path.join(temp.path, 'b.py'));
    await source.writeAsString('a');
    await existing.writeAsString('b');

    await expectLater(
      renameFile(source.path, 'b.py'),
      throwsA(isA<FileRenameTargetExistsException>()),
    );
    expect(await existing.readAsString(), 'b');
  });

  test('allows a case-only rename where casing is insignificant', () async {
    final caseInsensitive = await _isCaseInsensitive(temp);
    final source = File(path.join(temp.path, 'Foo.py'));
    await source.writeAsString('x');

    if (!caseInsensitive) {
      // Case-sensitive volume: `foo.py` really is a free name, so the rename is
      // an ordinary one and still has to succeed.
      final renamed = await renameFile(source.path, 'foo.py');
      expect(path.basename(renamed), 'foo.py');
      return;
    }

    // The target "exists" here because it is the source under another
    // spelling; refusing that made case-only renames impossible.
    final renamed = await renameFile(source.path, 'foo.py');
    expect(path.basename(renamed), 'foo.py');
    expect(
      temp.listSync().map((entity) => path.basename(entity.path)),
      ['foo.py'],
    );
  });
}
