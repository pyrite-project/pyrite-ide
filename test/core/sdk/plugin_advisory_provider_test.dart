import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_advisory_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_client.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_ledger.dart';
import 'package:pyrite_ide/core/sdk/types.dart';

const _forum = 'https://forum.example';
const _other = 'https://other.example';

RegistrySource _source(
  String id, {
  String version = '1.0.0',
  String origin = _forum,
}) => RegistrySource(pluginId: id, origin: origin, version: version);

PluginAdvisory _advisory(
  String id, {
  String level = 'none',
  String? severity,
  String version = '1.0.0',
  bool installable = true,
}) => PluginAdvisory(
  pluginId: id,
  version: version,
  installable: installable,
  moderation: PluginModeration(
    level: level,
    severity: severity,
    message: level,
  ),
);

Plugin _plugin(String id, {String version = '1.0.0'}) =>
    Plugin(id: id, name: id, version: version);

class _FakeClient extends PluginRegistryClient {
  final Map<String, List<PluginAdvisory>> answers = {};
  final Set<String> unreachable = {};
  final List<(String, List<String>)> requests = [];

  @override
  Future<List<PluginAdvisory>> fetchAdvisories(
    String origin,
    List<({String pluginId, String version})> releases,
  ) async {
    requests.add((
      origin,
      [for (final r in releases) '${r.pluginId}@${r.version}'],
    ));
    if (unreachable.contains(origin)) {
      throw const PluginRegistryException(
        PluginRegistryErrorCode.unreachable,
        'offline',
      );
    }
    return answers[origin] ?? const [];
  }
}

void main() {
  late Directory support;
  late PluginRegistryLedger ledger;
  late _FakeClient client;
  late Map<String, Plugin> installed;
  late DateTime clock;
  late List<List<PluginAdvisory>> alerts;
  late PluginAdvisoryNotifier notifier;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('advisory_provider_test');
    ledger = PluginRegistryLedger(supportDirectory: () async => support);
    client = _FakeClient();
    installed = {};
    clock = DateTime.utc(2026, 11, 8, 12);
    alerts = [];
    notifier = PluginAdvisoryNotifier(
      installedPlugins: () => installed,
      client: client,
      ledger: ledger,
      now: () => clock,
    )..onNewAlerts = alerts.add;
  });

  tearDown(() async {
    notifier.dispose();
    await support.delete(recursive: true);
  });

  Future<void> install(
    String id, {
    String version = '1.0.0',
    String origin = _forum,
  }) async {
    installed[id] = _plugin(id, version: version);
    await ledger.recordInstall(_source(id, version: version, origin: origin));
  }

  test('shows the answers remembered from earlier sessions', () async {
    await install('a');
    await ledger.saveCheck(
      advisories: {'a': _advisory('a', level: 'deprecated')},
      checkedAt: clock,
    );

    await notifier.reload();

    expect(notifier.state.flaggedFor('a')?.moderation.level, 'deprecated');
    expect(notifier.state.checkedAt, clock);
  });

  test(
    'asks each registry once about exactly the releases installed from it',
    () async {
      await install('a');
      await install('@my-org/b', version: '2.0.0');
      await install('c', origin: _other);

      await notifier.check();

      expect(client.requests, hasLength(2));
      final forum = client.requests.firstWhere((r) => r.$1 == _forum).$2;
      expect(forum, unorderedEquals(['a@1.0.0', '@my-org/b@2.0.0']));
      expect(client.requests.firstWhere((r) => r.$1 == _other).$2, ['c@1.0.0']);
    },
  );

  test('skips plugins that were replaced by another release', () async {
    await install('a');
    installed['a'] = _plugin('a', version: '1.5.0');

    await notifier.check();

    expect(client.requests, isEmpty);
  });

  test('forgets plugins that were uninstalled', () async {
    await install('a');
    await install('b');
    installed.remove('a');

    await notifier.check();

    expect((await ledger.read()).sources.keys, ['b']);
  });

  test(
    'stores what the registry says and tells the user about new problems',
    () async {
      await install('a');
      client.answers[_forum] = [
        _advisory('a', level: 'advisory', severity: 'high'),
      ];

      await notifier.check();

      expect(notifier.state.flaggedFor('a')?.moderation.severity, 'high');
      expect(alerts, hasLength(1));
      expect(alerts.single.single.pluginId, 'a');
      expect(
        (await ledger.read()).advisories['a']?.moderation.level,
        'advisory',
      );
    },
  );

  test('does not repeat an alert for an unchanged problem', () async {
    await install('a');
    client.answers[_forum] = [_advisory('a', level: 'deprecated')];
    await notifier.check();
    alerts.clear();

    await notifier.check();

    expect(alerts, isEmpty);
    expect(notifier.state.flaggedFor('a'), isNotNull);
  });

  test('alerts again when the problem gets worse', () async {
    await install('a');
    client.answers[_forum] = [_advisory('a', level: 'deprecated')];
    await notifier.check();
    alerts.clear();

    client.answers[_forum] = [
      _advisory('a', level: 'withdrawn', installable: false),
    ];
    await notifier.check();

    expect(alerts, hasLength(1));
    expect(notifier.state.flaggedFor('a')?.installable, isFalse);
  });

  test('clears a warning the registry lifted, without alerting', () async {
    await install('a');
    client.answers[_forum] = [
      _advisory('a', level: 'advisory', severity: 'low'),
    ];
    await notifier.check();
    alerts.clear();

    client.answers[_forum] = [_advisory('a')];
    await notifier.check();

    expect(notifier.state.flaggedFor('a'), isNull);
    expect(alerts, isEmpty);
  });

  test(
    'an unreachable registry keeps the old warning and retries later',
    () async {
      await install('a');
      client.answers[_forum] = [_advisory('a', level: 'deprecated')];
      await notifier.check();
      final firstCheck = notifier.state.checkedAt;
      clock = clock.add(const Duration(hours: 7));

      client.unreachable.add(_forum);
      await notifier.check();

      expect(notifier.state.flaggedFor('a'), isNotNull);
      expect(notifier.state.checkedAt, firstCheck);
      expect(notifier.state.checking, isFalse);
    },
  );

  test('one registry being down does not hide another one answering', () async {
    await install('a');
    await install('c', origin: _other);
    client.unreachable.add(_forum);
    client.answers[_other] = [
      _advisory('c', level: 'advisory', severity: 'high'),
    ];

    await notifier.check();

    expect(notifier.state.flaggedFor('c'), isNotNull);
    expect(notifier.state.checkedAt, clock);
  });

  test(
    'releases the registry does not mention keep their last standing',
    () async {
      await install('a');
      client.answers[_forum] = [_advisory('a', level: 'deprecated')];
      await notifier.check();

      client.answers[_forum] = const [];
      await notifier.check();

      expect(notifier.state.flaggedFor('a'), isNotNull);
    },
  );

  test('splits large installs into several requests', () async {
    for (var i = 0; i < 150; i++) {
      await install('plugin-$i');
    }

    await notifier.check();

    expect(client.requests.map((r) => r.$2.length), unorderedEquals([100, 50]));
  });

  test(
    'with nothing installed from a registry there is no network traffic',
    () async {
      installed['local'] = _plugin('local');

      await notifier.check();

      expect(client.requests, isEmpty);
      expect(notifier.state.checkedAt, clock);
    },
  );

  group('checkIfDue', () {
    test('checks the first time, then waits for the interval', () async {
      await install('a');

      await notifier.checkIfDue();
      await notifier.checkIfDue();
      expect(client.requests, hasLength(1));

      clock = clock.add(advisoryCheckInterval - const Duration(minutes: 1));
      await notifier.checkIfDue();
      expect(client.requests, hasLength(1));

      clock = clock.add(const Duration(minutes: 2));
      await notifier.checkIfDue();
      expect(client.requests, hasLength(2));
    });

    test('does not start a second check while one is running', () async {
      await install('a');

      await Future.wait([notifier.check(), notifier.check()]);

      expect(client.requests, hasLength(1));
    });
  });
}
