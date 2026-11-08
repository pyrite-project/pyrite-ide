import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/command_palette/palette_recent.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  List<String> ids() => container.read(recentPaletteIdsProvider);

  test('starts empty', () {
    expect(ids(), isEmpty);
  });

  test('records newest first', () {
    final notifier = container.read(recentPaletteIdsProvider.notifier);
    notifier.record('a');
    notifier.record('b');

    expect(ids(), ['b', 'a']);
  });

  test(
    're-recording an entry moves it to the front instead of duplicating',
    () {
      final notifier = container.read(recentPaletteIdsProvider.notifier);
      notifier.record('a');
      notifier.record('b');
      notifier.record('a');

      expect(ids(), ['a', 'b']);
    },
  );

  test('keeps at most the cap, dropping the oldest', () {
    final notifier = container.read(recentPaletteIdsProvider.notifier);
    for (var i = 0; i < maxRecentPaletteEntries + 3; i++) {
      notifier.record('id$i');
    }

    expect(ids().length, maxRecentPaletteEntries);
    expect(ids().first, 'id${maxRecentPaletteEntries + 2}');
    expect(ids(), isNot(contains('id0')));
  });

  test('ignores empty ids', () {
    final notifier = container.read(recentPaletteIdsProvider.notifier);
    notifier.record('');

    expect(ids(), isEmpty);
  });

  test('clear forgets everything', () {
    final notifier = container.read(recentPaletteIdsProvider.notifier);
    notifier.record('a');
    notifier.clear();

    expect(ids(), isEmpty);
  });
}
