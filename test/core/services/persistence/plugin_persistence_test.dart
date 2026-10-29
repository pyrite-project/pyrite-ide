import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/persistence/plugin_persistence.dart';

void main() {
  group('PluginPersistedData.listFromJson', () {
    test('keeps every usable entry', () {
      final entries = PluginPersistedData.listFromJson([
        {'id': 'a.plugin', 'name': 'A'},
        {'id': 'b.plugin', 'name': 'B', 'status': 'disabled'},
      ]);

      expect(entries.map((entry) => entry.id), ['a.plugin', 'b.plugin']);
      expect(entries[1].status, 'disabled');
    });

    test('skips entries that cannot name a plugin', () {
      // One unreadable entry used to make the loader throw, and the caller
      // treats that as "no metadata at all": every plugin would lose its
      // recorded status and permission grants.
      final entries = PluginPersistedData.listFromJson([
        {'id': 'a.plugin', 'name': 'A'},
        'junk',
        {'name': 'no id'},
        {'id': 42, 'name': 'number id'},
        {'id': 'b.plugin', 'name': 'B', 'platforms': ['linux', 7]},
      ]);

      expect(entries.map((entry) => entry.id), ['a.plugin', '42', 'b.plugin']);
      expect(entries.last.platforms, ['linux']);
    });

    test('a non-list value yields no entries', () {
      expect(PluginPersistedData.listFromJson(null), isEmpty);
      expect(PluginPersistedData.listFromJson('nope'), isEmpty);
    });
  });
}
