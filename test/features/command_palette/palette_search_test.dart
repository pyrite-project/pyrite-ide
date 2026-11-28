import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/command_palette/palette_entry.dart';
import 'package:pyrite_ide/features/command_palette/palette_search.dart';

PaletteEntry _entry(
  String id, {
  required String title,
  PaletteCategory category = PaletteCategory.command,
  String? subtitle,
  bool enabled = true,
  List<String> keywords = const <String>[],
  String? searchText,
}) => PaletteEntry(
  id: id,
  title: title,
  category: category,
  subtitle: subtitle,
  enabled: enabled,
  keywords: keywords,
  searchText: searchText,
);

List<String> _ids(List<PaletteEntry> entries) => [
  for (final entry in entries) entry.id,
];

void main() {
  group('query parsing', () {
    test('a leading > is a mode switch, not part of the query', () {
      expect(paletteForcesCommands('>'), isTrue);
      expect(paletteForcesCommands('  > open'), isTrue);
      expect(paletteForcesCommands('open > file'), isFalse);
      expect(paletteEffectiveQuery('> open'), 'open');
      expect(paletteEffectiveQuery('  open  '), 'open');
    });
  });

  group('ranking', () {
    test('an empty query keeps everything in mode category order', () {
      final entries = [
        _entry('file', title: 'a.py', category: PaletteCategory.file),
        _entry('setting', title: '外观', category: PaletteCategory.setting),
        _entry('nav', title: '设置', category: PaletteCategory.navigation),
        _entry('command', title: '保存', category: PaletteCategory.command),
      ];

      expect(
        _ids(
          rankPaletteEntries(
            entries,
            query: '',
            mode: PaletteLaunchMode.commands,
          ),
        ),
        ['command', 'nav', 'setting', 'file'],
      );

      expect(
        _ids(
          rankPaletteEntries(entries, query: '', mode: PaletteLaunchMode.files),
        ),
        ['file', 'command', 'nav', 'setting'],
      );
    });

    test('a query keeps only matching entries', () {
      final entries = [
        _entry('open', title: 'Open File'),
        _entry('save', title: 'Save File'),
      ];

      expect(
        _ids(
          rankPaletteEntries(
            entries,
            query: 'save',
            mode: PaletteLaunchMode.commands,
          ),
        ),
        ['save'],
      );
    });

    test('exact beats prefix beats substring', () {
      final entries = [
        _entry('substring', title: 'Revert Save'),
        _entry('exact', title: 'Save'),
        _entry('prefix', title: 'Save As'),
      ];

      expect(
        _ids(
          rankPaletteEntries(
            entries,
            query: 'save',
            mode: PaletteLaunchMode.commands,
          ),
        ),
        ['exact', 'prefix', 'substring'],
      );
    });

    test('a title hit outranks a hit that is only in the subtitle', () {
      final entries = [
        _entry('path', title: 'main.py', subtitle: 'lib/save/widgets.py'),
        _entry('title', title: 'Save Widgets'),
      ];

      expect(
        _ids(
          rankPaletteEntries(
            entries,
            query: 'save',
            mode: PaletteLaunchMode.files,
          ),
        ),
        ['title', 'path'],
      );
    });

    test('initials match as a subsequence', () {
      final entries = [
        _entry('opf', title: 'Open Project File'),
        _entry('other', title: 'Toggle Panel'),
      ];

      expect(
        _ids(
          rankPaletteEntries(
            entries,
            query: 'opf',
            mode: PaletteLaunchMode.commands,
          ),
        ),
        ['opf'],
      );
    });

    test('a > query hides project files', () {
      final entries = [
        _entry('file', title: 'save', category: PaletteCategory.file),
        _entry('command', title: 'save'),
      ];

      expect(
        _ids(
          rankPaletteEntries(
            entries,
            query: '> save',
            mode: PaletteLaunchMode.files,
          ),
        ),
        ['command'],
      );
    });

    test('recently used entries get a boost', () {
      final entries = [
        _entry('alpha', title: 'Open Alpha'),
        _entry('beta', title: 'Open Beta'),
      ];

      expect(
        _ids(
          rankPaletteEntries(
            entries,
            query: 'open',
            mode: PaletteLaunchMode.commands,
            recentIds: const ['beta'],
          ),
        ),
        ['beta', 'alpha'],
      );
    });

    test('disabled entries always sort below enabled ones', () {
      final entries = [
        _entry('disabled', title: 'Save', enabled: false),
        _entry('enabled', title: 'Save As'),
      ];

      expect(
        _ids(
          rankPaletteEntries(
            entries,
            query: 'save',
            mode: PaletteLaunchMode.commands,
          ),
        ),
        ['enabled', 'disabled'],
      );
    });

    test('an empty query lists recents first', () {
      final entries = [_entry('a', title: 'Alpha'), _entry('b', title: 'Beta')];

      expect(
        _ids(
          rankPaletteEntries(
            entries,
            query: '',
            mode: PaletteLaunchMode.commands,
            recentIds: const ['b'],
          ),
        ),
        ['b', 'a'],
      );
    });

    test('precomputed search text is what the ranker reads', () {
      final entries = [
        _entry(
          'file',
          title: 'widget.dart',
          category: PaletteCategory.file,
          searchText: 'lib/ui/widget.dart',
        ),
      ];

      expect(
        _ids(
          rankPaletteEntries(
            entries,
            query: 'ui',
            mode: PaletteLaunchMode.files,
          ),
        ),
        ['file'],
      );
    });

    test('a query with no match returns nothing', () {
      final entries = [_entry('a', title: 'Alpha')];

      expect(
        rankPaletteEntries(
          entries,
          query: 'zzz',
          mode: PaletteLaunchMode.commands,
        ),
        isEmpty,
      );
    });
  });
}
