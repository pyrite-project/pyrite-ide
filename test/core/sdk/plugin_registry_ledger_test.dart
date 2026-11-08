import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_client.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_ledger.dart';

RegistrySource _source(String id, {String version = '1.0.0'}) => RegistrySource(
  pluginId: id,
  origin: 'https://forum.example',
  version: version,
);

PluginAdvisory _advisory(
  String id, {
  String level = 'none',
  String version = '1.0.0',
}) => PluginAdvisory(
  pluginId: id,
  version: version,
  installable: level != 'withdrawn',
  moderation: PluginModeration(level: level, message: 'm'),
);

void main() {
  late Directory support;
  late PluginRegistryLedger ledger;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('registry_ledger_test');
    ledger = PluginRegistryLedger(supportDirectory: () async => support);
  });

  tearDown(() => support.delete(recursive: true));

  test('reads as empty before anything is recorded', () async {
    final snapshot = await ledger.read();

    expect(snapshot.sources, isEmpty);
    expect(snapshot.advisories, isEmpty);
    expect(snapshot.checkedAt, isNull);
  });

  test(
    'remembers installs and the standing they were installed under',
    () async {
      await ledger.recordInstall(
        _source('a'),
        advisory: _advisory('a', level: 'deprecated'),
      );

      final snapshot = await PluginRegistryLedger(
        supportDirectory: () async => support,
      ).read();

      expect(snapshot.sources['a'], _source('a'));
      expect(snapshot.advisories['a']?.moderation.level, 'deprecated');
    },
  );

  test(
    'a newer install replaces what was known about the old release',
    () async {
      await ledger.recordInstall(
        _source('a'),
        advisory: _advisory('a', level: 'advisory'),
      );

      await ledger.recordInstall(_source('a', version: '1.1.0'));

      final snapshot = await ledger.read();
      expect(snapshot.sources['a']?.version, '1.1.0');
      expect(snapshot.advisories, isEmpty);
    },
  );

  test('forgets plugins that are gone', () async {
    await ledger.recordInstall(_source('a'), advisory: _advisory('a'));
    await ledger.recordInstall(_source('b'), advisory: _advisory('b'));

    await ledger.forget(['a']);

    final snapshot = await ledger.read();
    expect(snapshot.sources.keys, ['b']);
    expect(snapshot.advisories.keys, ['b']);
  });

  test('saves a check without touching the recorded sources', () async {
    await ledger.recordInstall(_source('a'));
    final at = DateTime.utc(2026, 11, 8, 12);

    await ledger.saveCheck(
      advisories: {'a': _advisory('a', level: 'withdrawn')},
      checkedAt: at,
    );

    final snapshot = await ledger.read();
    expect(snapshot.sources.keys, ['a']);
    expect(snapshot.advisories['a']?.installable, isFalse);
    expect(snapshot.checkedAt, at);
  });

  test('quick consecutive installs are all kept', () async {
    await Future.wait([
      for (var i = 0; i < 10; i++) ledger.recordInstall(_source('plugin-$i')),
    ]);

    expect((await ledger.read()).sources, hasLength(10));
  });

  test('a corrupt file reads as empty instead of failing', () async {
    File(
      '${support.path}/plugin_registry_ledger.json',
    ).writeAsStringSync('{ not json');

    final snapshot = await ledger.read();

    expect(snapshot.sources, isEmpty);
    await ledger.recordInstall(_source('a'));
    expect((await ledger.read()).sources.keys, ['a']);
  });

  test('damaged entries are dropped and the rest survives', () async {
    File('${support.path}/plugin_registry_ledger.json').writeAsStringSync('''
{"sources": {"good": {"origin": "https://x.example", "version": "1.0.0"}, "bad": 5, "worse": {"origin": 1}},
 "advisories": {"good": {"ext_id": "good", "version": "1.0.0"}, "bad": {"ext_id": 7}}}
''');

    final snapshot = await ledger.read();

    expect(snapshot.sources.keys, ['good']);
    expect(snapshot.advisories.keys, ['good']);
  });
}
