import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/search/search_service.dart';

void main() {
  group('SearchOptions.toRegExp', () {
    test('plain text is escaped and case-insensitive by default', () {
      final regex = const SearchOptions(pattern: 'foo.bar').toRegExp();
      expect(regex.isCaseSensitive, isFalse);
      // The dot is literal, so it matches the literal "foo.bar".
      expect(regex.hasMatch('FOO.BAR'), isTrue);
      // But not a differing character in the dot position.
      expect(regex.hasMatch('fooxbar'), isFalse);
    });

    test('case sensitive respects the flag', () {
      final regex = const SearchOptions(
        pattern: 'Foo',
        caseSensitive: true,
      ).toRegExp();
      expect(regex.hasMatch('foo'), isFalse);
      expect(regex.hasMatch('Foo'), isTrue);
    });

    test('regex mode treats the pattern as a regular expression', () {
      final regex = const SearchOptions(
        pattern: r'f.o',
        isRegExp: true,
      ).toRegExp();
      expect(regex.hasMatch('fXo'), isTrue);
    });

    test('whole word only applies in plain-text mode', () {
      final regex = const SearchOptions(
        pattern: 'bar',
        wholeWord: true,
      ).toRegExp();
      expect(regex.hasMatch('foobar'), isFalse);
      expect(regex.hasMatch('bar'), isTrue);
      // With regex mode, whole-word wrapping is skipped.
      final regexRe = const SearchOptions(
        pattern: 'bar',
        isRegExp: true,
        wholeWord: true,
      ).toRegExp();
      expect(regexRe.hasMatch('foobar'), isTrue);
    });

    test('multiLine anchors at line boundaries', () {
      // Anchors are regex syntax, so they only carry meaning in regex mode —
      // plain-text mode escapes the caret.
      final regex = const SearchOptions(
        pattern: '^bar',
        isRegExp: true,
      ).toRegExp(multiLine: true);
      expect(regex.hasMatch('foo\nbar'), isTrue);
      expect(
        const SearchOptions(
          pattern: '^bar',
          isRegExp: true,
        ).toRegExp().hasMatch('foo\nbar'),
        isFalse,
      );
    });
  });

  group('matchFiles', () {
    test('groups several hits on one line into ordered ranges', () {
      final files = [
        (path: '/p/a.txt', content: 'foo bar foo baz\nnothing\nfoo!'),
      ];

      final results = matchFiles(files, const SearchOptions(pattern: 'foo'));

      expect(results, hasLength(1));
      final matches = results.first.matches;
      expect(matches, hasLength(2));
      expect(matches[0].lineIndex, 0);
      expect(matches[0].lineText, 'foo bar foo baz');
      expect(matches[0].ranges, [(0, 3), (8, 11)]);
      expect(matches[1].lineIndex, 2);
      expect(matches[1].lineText, 'foo!');
      expect(matches[1].ranges, [(0, 3)]);
    });

    test('anchors keep per-line semantics over whole content', () {
      final files = [(path: '/p/a.txt', content: 'alpha\nbeta alpha\n')];

      final results = matchFiles(
        files,
        const SearchOptions(pattern: '^alpha', isRegExp: true),
      );

      expect(results, hasLength(1));
      expect(results.first.matches, hasLength(1));
      expect(results.first.matches.first.lineIndex, 0);
    });

    test('files without matches are omitted', () {
      final files = [
        (path: '/p/a.txt', content: 'nothing here'),
        (path: '/p/b.txt', content: 'a needle'),
      ];

      final results = matchFiles(files, const SearchOptions(pattern: 'needle'));

      expect(results.map((r) => r.filePath), ['/p/b.txt']);
      expect(results.first.matches.first.ranges, [(2, 8)]);
    });
  });

  group('scanProject', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('pyrite_scan_');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    test('normalizes CRLF line endings into the cache', () async {
      await File(path.join(temp.path, 'a.txt')).writeAsString('a\r\nb\r\nc');

      final files = await scanProject(temp);

      expect(files, hasLength(1));
      expect(files.single.content, 'a\nb\nc');
    });
  });

  group('searchInDirectory', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('pyrite_search_');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    test('finds matches across nested files', () async {
      await File(
        path.join(temp.path, 'a.txt'),
      ).writeAsString('hello world\nfoo bar baz\n');
      await File(
        path.join(temp.path, 'b.dart'),
      ).writeAsString('class Foo {}\n  world;\n');
      final sub = Directory(path.join(temp.path, 'sub'))..createSync();
      await File(path.join(sub.path, 'c.txt')).writeAsString('world again');

      final results = await searchInDirectory(
        temp,
        const SearchOptions(pattern: 'world'),
      );

      expect(results.length, 3);
      var total = 0;
      for (final file in results) {
        total += file.matchCount;
      }
      expect(total, 3);
    });

    test('skips files inside a .git directory', () async {
      final gitDir = Directory(path.join(temp.path, '.git'))..createSync();
      await File(path.join(gitDir.path, 'config')).writeAsString('world');

      final results = await searchInDirectory(
        temp,
        const SearchOptions(pattern: 'world'),
      );

      expect(results.any((r) => r.filePath.contains('.git')), isFalse);
    });

    test('skips binary files', () async {
      final binary = File(path.join(temp.path, 'img.bin'));
      await binary.writeAsBytes([0, 1, 2, 0, 3, 4]);

      final results = await searchInDirectory(
        temp,
        const SearchOptions(pattern: 'anything'),
      );

      expect(results, isEmpty);
    });

    test('empty pattern yields no results', () async {
      final results = await searchInDirectory(temp, const SearchOptions());
      expect(results, isEmpty);
    });

    test('returns nothing when cancelled early', () async {
      await File(path.join(temp.path, 'a.txt')).writeAsString('needle here');
      final token = SearchCancelToken()..cancelled = true;

      final results = await searchInDirectory(
        temp,
        const SearchOptions(pattern: 'needle'),
        cancel: token,
      );

      expect(results, isEmpty);
    });
  });

  group('replaceAllInResults', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('pyrite_replace_');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    test('replaces every occurrence and writes back to disk', () async {
      final file = File(path.join(temp.path, 'a.txt'));
      await file.writeAsString('foo bar foo\n');

      final results = await searchInDirectory(
        temp,
        const SearchOptions(pattern: 'foo', replaceText: 'baz'),
      );
      final replaced = await replaceAllInResults(
        results,
        const SearchOptions(pattern: 'foo', replaceText: 'baz'),
      );

      expect(replaced, 2);
      expect(await file.readAsString(), 'baz bar baz\n');
    });

    test('honors regex group references', () async {
      final file = File(path.join(temp.path, 'a.txt'));
      await file.writeAsString('color: red');

      final results = await searchInDirectory(
        temp,
        const SearchOptions(pattern: r'color: (\w+)', isRegExp: true),
      );
      final replaced = await replaceAllInResults(
        results,
        const SearchOptions(
          pattern: r'color: (\w+)',
          isRegExp: true,
          replaceText: r'tint: $1',
        ),
      );

      expect(replaced, 1);
      expect(await file.readAsString(), 'tint: red');
    });
  });

  group('replaceOneOccurrence', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('pyrite_replace_one_');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    test('replaces only the nth occurrence', () async {
      final file = File(path.join(temp.path, 'a.txt'));
      await file.writeAsString('one two one two');

      final ok = await replaceOneOccurrence(
        file.path,
        const SearchOptions(pattern: 'two', replaceText: 'X'),
        1,
      );

      expect(ok, isTrue);
      expect(await file.readAsString(), 'one two one X');
    });

    test('keeps CRLF endings of untouched lines', () async {
      final file = File(path.join(temp.path, 'a.txt'));
      await file.writeAsString('foo\r\nfoo\r\n');

      final ok = await replaceOneOccurrence(
        file.path,
        const SearchOptions(pattern: 'foo', replaceText: 'bar'),
        1,
      );

      expect(ok, isTrue);
      expect(await file.readAsString(), 'foo\r\nbar\r\n');
    });

    test('returns false when the occurrence does not exist', () async {
      final file = File(path.join(temp.path, 'a.txt'));
      await file.writeAsString('one two');

      final ok = await replaceOneOccurrence(
        file.path,
        const SearchOptions(pattern: 'two', replaceText: 'X'),
        5,
      );

      expect(ok, isFalse);
      expect(await file.readAsString(), 'one two');
    });

    test('expands regex group references in regex mode', () async {
      final file = File(path.join(temp.path, 'a.txt'));
      await file.writeAsString('color: red\ncolor: blue');

      final ok = await replaceOneOccurrence(
        file.path,
        const SearchOptions(
          pattern: r'color: (\w+)',
          isRegExp: true,
          replaceText: r'tint: $1',
        ),
        1,
      );

      expect(ok, isTrue);
      expect(await file.readAsString(), 'color: red\ntint: blue');
    });
  });
}
