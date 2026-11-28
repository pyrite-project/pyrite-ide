import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart' as git;
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/search/project_file_index.dart';

void main() {
  late Directory root;

  setUp(() async {
    // libgit2 reports a repository's workdir with symlinks resolved, so a
    // temp path under `/var` would never look like it contains `/private/var`.
    final created = await Directory.systemTemp.createTemp(
      'pyrite_project_index_',
    );
    root = Directory(await created.resolveSymbolicLinks());
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> writeFile(String relative, [String contents = '']) async {
    final file = File(p.join(root.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
    return file;
  }

  List<String> relativePaths(List<ProjectFileEntry> entries) => [
    for (final entry in entries) entry.relativePath,
  ];

  test('walks nested directories and reports relative paths', () async {
    await writeFile('main.py');
    await writeFile('lib/ui/widget.dart');

    final entries = await scanProjectFiles(root);

    expect(relativePaths(entries), ['lib/ui/widget.dart', 'main.py']);
    expect(entries.first.name, 'widget.dart');
    expect(entries.first.path, p.join(root.path, 'lib', 'ui', 'widget.dart'));
  });

  test('uses forward slashes in relative paths on every platform', () async {
    await writeFile('a/b/c.txt');

    final entries = await scanProjectFiles(root);

    expect(entries.single.relativePath, 'a/b/c.txt');
  });

  test('skips the .git directory', () async {
    await writeFile('.git/config');
    await writeFile('main.py');

    final entries = await scanProjectFiles(root);

    expect(relativePaths(entries), ['main.py']);
  });

  test('honours .gitignore rules inside a repository', () async {
    final repo = git.Repository.init(path: root.path);
    try {
      await writeFile('.gitignore', 'build/\n*.log\n');
      await writeFile('build/generated.dart');
      await writeFile('debug.log');
      await writeFile('main.py');

      final entries = await scanProjectFiles(root);

      expect(relativePaths(entries), containsAll(<String>['main.py']));
      expect(relativePaths(entries), isNot(contains('build/generated.dart')));
      expect(relativePaths(entries), isNot(contains('debug.log')));
    } finally {
      repo.free();
    }
  });

  test('stops at the limit and still returns a deterministic order', () async {
    for (var i = 0; i < 10; i++) {
      await writeFile('file$i.txt');
    }

    final entries = await scanProjectFiles(root, limit: 3);

    expect(entries.length, lessThanOrEqualTo(3));
    final sorted = [...relativePaths(entries)]..sort();
    expect(relativePaths(entries), sorted);
  });

  test('does not follow symbolic links', () async {
    final target = Directory(p.join(root.path, 'target'))..createSync();
    File(p.join(target.path, 'inside.txt')).writeAsStringSync('');
    final link = Link(p.join(root.path, 'link'));
    await link.create(target.path);
    await writeFile('main.py');

    final entries = await scanProjectFiles(root);

    expect(relativePaths(entries), contains('main.py'));
    expect(relativePaths(entries), contains('target/inside.txt'));
    expect(relativePaths(entries), isNot(contains('link/inside.txt')));
  });

  test('returns nothing for a missing root', () async {
    final missing = Directory(p.join(root.path, 'nope'));

    expect(await scanProjectFiles(missing), isEmpty);
  });

  test('a non-positive limit indexes nothing', () async {
    await writeFile('main.py');

    expect(await scanProjectFiles(root, limit: 0), isEmpty);
  });
}
