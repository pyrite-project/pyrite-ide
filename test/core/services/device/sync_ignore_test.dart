import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/device/sync_ignore.dart';

void main() {
  group('SyncIgnoreRules.parse', () {
    test('skips comments, blank lines and stray whitespace', () {
      final rules = SyncIgnoreRules.parse(
        '# build output\n'
        '\n'
        '   \n'
        '  build/  \n'
        'main.py\n'
        '# vendor\n'
        'vendor\n',
      );

      expect(rules.patterns.map((pattern) => pattern.pattern), [
        'build',
        'main.py',
        'vendor',
      ]);
    });

    test('tolerates CRLF, a BOM and Windows separators', () {
      final rules = SyncIgnoreRules.parse('\uFEFFlib\\gen\r\n.secrets\r\n');

      expect(rules.shouldIgnore('lib/gen/a.py'), isTrue);
      expect(rules.shouldIgnore('.secrets'), isTrue);
    });

    test('strips leading ./ and / because every path is root relative', () {
      final rules = SyncIgnoreRules.parse('./lib/gen/\n/secrets\n');

      expect(rules.shouldIgnore('lib/gen/a.py'), isTrue);
      expect(rules.shouldIgnore('secrets/token'), isTrue);
    });

    test('drops lines that carry no path at all', () {
      final rules = SyncIgnoreRules.parse('# only comments\n/\n./\n\n');

      expect(rules.isEmpty, isTrue);
    });
  });

  group('SyncIgnoreRules.shouldIgnore', () {
    test('matches an exact file', () {
      final rules = SyncIgnoreRules.parse('boot.py\n');

      expect(rules.shouldIgnore('boot.py'), isTrue);
      expect(rules.shouldIgnore('boot.pyc'), isFalse);
    });

    test('a directory pattern covers everything below it', () {
      final rules = SyncIgnoreRules.parse('build\n');

      expect(rules.shouldIgnore('build'), isTrue);
      expect(rules.shouldIgnore('build/out.bin'), isTrue);
      expect(rules.shouldIgnore('build/lib/deep.o'), isTrue);
      expect(rules.shouldIgnore('rebuild/out.bin'), isFalse);
    });

    test('a pattern without a slash matches at any depth', () {
      final rules = SyncIgnoreRules.parse('__pycache__\n');

      expect(rules.shouldIgnore('__pycache__/m.pyc'), isTrue);
      expect(rules.shouldIgnore('lib/__pycache__/m.pyc'), isTrue);
    });

    test('a pattern with a slash is anchored to the root', () {
      final rules = SyncIgnoreRules.parse('lib/gen\n');

      expect(rules.shouldIgnore('lib/gen/a.py'), isTrue);
      expect(rules.shouldIgnore('other/lib/gen/a.py'), isFalse);
    });

    test('single star stays inside one segment', () {
      final rules = SyncIgnoreRules.parse('lib/*.py\n');

      expect(rules.shouldIgnore('lib/a.py'), isTrue);
      expect(rules.shouldIgnore('lib/sub/a.py'), isFalse);
    });

    test('double star spans segments', () {
      final rules = SyncIgnoreRules.parse('**/*.pyc\n');

      expect(rules.shouldIgnore('a.pyc'), isTrue);
      expect(rules.shouldIgnore('lib/sub/a.pyc'), isTrue);
    });

    test('question mark matches one character', () {
      final rules = SyncIgnoreRules.parse('log?.txt\n');

      expect(rules.shouldIgnore('log1.txt'), isTrue);
      expect(rules.shouldIgnore('log10.txt'), isFalse);
    });

    test('the ignore file itself is always ignored', () {
      const rules = SyncIgnoreRules.empty();

      expect(rules.shouldIgnore(syncIgnoreFileName), isTrue);
      expect(rules.shouldIgnore('lib/$syncIgnoreFileName'), isFalse);
    });

    test('normalizes the separator of the queried path', () {
      final rules = SyncIgnoreRules.parse('build\n');

      expect(rules.shouldIgnore(r'build\out.bin'), isTrue);
    });
  });

  group('loadSyncIgnoreRules', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pyrite_ignore_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('a missing file yields no rules', () async {
      final rules = await loadSyncIgnoreRules(tempDir.path);

      expect(rules.isEmpty, isTrue);
      // The file itself is still excluded even when it does not exist yet.
      expect(rules.shouldIgnore(syncIgnoreFileName), isTrue);
    });

    test('reads the rules from the workspace root', () async {
      await File(
        path.join(tempDir.path, syncIgnoreFileName),
      ).writeAsString('# keep the board clean\nvendor\n*.pyc\n');

      final rules = await loadSyncIgnoreRules(tempDir.path);

      expect(rules.isNotEmpty, isTrue);
      expect(rules.shouldIgnore('vendor/lib.py'), isTrue);
      expect(rules.shouldIgnore('main.pyc'), isTrue);
      expect(rules.shouldIgnore('main.py'), isFalse);
    });
  });
}
