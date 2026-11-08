import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/file/file_sort.dart';

void main() {
  int compare({
    required bool firstIsFolder,
    required String firstName,
    required bool secondIsFolder,
    required String secondName,
    FileSortMode mode = FileSortMode.byName,
  }) {
    return compareFileTreeEntries(
      firstIsFolder: firstIsFolder,
      firstName: firstName,
      secondIsFolder: secondIsFolder,
      secondName: secondName,
      mode: mode,
    );
  }

  List<String> sorted(
    List<({bool isFolder, String name})> entries,
    FileSortMode mode,
  ) {
    final copy = [...entries];
    copy.sort(
      (a, b) => compare(
        firstIsFolder: a.isFolder,
        firstName: a.name,
        secondIsFolder: b.isFolder,
        secondName: b.name,
        mode: mode,
      ),
    );
    return [for (final entry in copy) entry.name];
  }

  test('folders sort before files in both modes', () {
    for (final mode in FileSortMode.values) {
      expect(
        compare(
          firstIsFolder: true,
          firstName: 'zebra',
          secondIsFolder: false,
          secondName: 'alpha',
          mode: mode,
        ),
        lessThan(0),
      );
      expect(
        compare(
          firstIsFolder: false,
          firstName: 'alpha',
          secondIsFolder: true,
          secondName: 'zebra',
          mode: mode,
        ),
        greaterThan(0),
      );
    }
  });

  test('folders stay alphabetical under the type mode', () {
    expect(
      sorted([
        (isFolder: true, name: 'zlib'),
        (isFolder: true, name: 'Assets'),
      ], FileSortMode.byType),
      ['Assets', 'zlib'],
    );
  });

  test('names compare case-insensitively', () {
    expect(
      compare(
        firstIsFolder: false,
        firstName: 'Apple',
        secondIsFolder: false,
        secondName: 'banana',
      ),
      lessThan(0),
    );
    expect(
      compare(
        firstIsFolder: false,
        firstName: 'apple',
        secondIsFolder: false,
        secondName: 'Banana',
      ),
      lessThan(0),
    );
  });

  test('a case-only difference keeps a stable order', () {
    expect(
      compare(
        firstIsFolder: false,
        firstName: 'README',
        secondIsFolder: false,
        secondName: 'readme',
      ),
      lessThan(0),
    );
    expect(
      compare(
        firstIsFolder: false,
        firstName: 'readme',
        secondIsFolder: false,
        secondName: 'README',
      ),
      greaterThan(0),
    );
  });

  test('the name mode sorts a mixed listing alphabetically', () {
    expect(
      sorted([
        (isFolder: false, name: 'main.py'),
        (isFolder: true, name: 'lib'),
        (isFolder: false, name: 'boot.py'),
        (isFolder: true, name: 'Assets'),
        (isFolder: false, name: 'README.md'),
      ], FileSortMode.byName),
      ['Assets', 'lib', 'boot.py', 'main.py', 'README.md'],
    );
  });

  test('the type mode groups by extension, then by name', () {
    expect(
      sorted([
        (isFolder: false, name: 'main.py'),
        (isFolder: true, name: 'lib'),
        (isFolder: false, name: 'boot.py'),
        (isFolder: true, name: 'Assets'),
        (isFolder: false, name: 'README.md'),
        (isFolder: false, name: 'notes.txt'),
        (isFolder: false, name: 'data.json'),
        (isFolder: false, name: 'app.mpy'),
        (isFolder: false, name: 'README'),
      ], FileSortMode.byType),
      [
        'Assets',
        'lib',
        'README',
        'data.json',
        'README.md',
        'app.mpy',
        'boot.py',
        'main.py',
        'notes.txt',
      ],
    );
  });

  test('extensions compare case-insensitively', () {
    expect(
      compare(
        firstIsFolder: false,
        firstName: 'A.PY',
        secondIsFolder: false,
        secondName: 'b.json',
        mode: FileSortMode.byType,
      ),
      greaterThan(0),
    );
  });

  test('the mode name round-trips through its persisted spelling', () {
    expect(FileSortMode.byName.jsonName, 'name');
    expect(FileSortMode.byType.jsonName, 'type');
    expect(FileSortMode.fromJsonName('type'), FileSortMode.byType);
    expect(FileSortMode.fromJsonName('name'), FileSortMode.byName);
    expect(FileSortMode.fromJsonName(null), FileSortMode.byName);
    expect(FileSortMode.fromJsonName('unknown'), FileSortMode.byName);
  });
}
