import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/device_runtime_backend.dart';
import 'package:pyrite_ide/core/sdk/runtime_inspection.dart';

const _marker = '__PYRITE_RUNTIME__';

class _Emissions {
  final List<String> topics = [];

  void emit(String topic, Map<String, dynamic> payload) {
    topics.add(topic);
  }
}

void main() {
  late _Emissions emissions;
  late RuntimeInspectionService service;
  late DeviceScriptRunner runner;
  late List<String> scripts;
  late String Function(String script)? handler;
  late bool busy;

  DeviceRuntimeBackend build() => DeviceRuntimeBackend(
    service: service,
    runScript: runner,
    isBusy: () => busy,
  );

  setUp(() {
    emissions = _Emissions();
    service = RuntimeInspectionService(emit: emissions.emit);
    scripts = [];
    handler = null;
    busy = false;
    runner = (script) async {
      scripts.add(script);
      if (handler == null) {
        throw StateError('no script handler installed');
      }
      return handler!(script);
    };
  });

  test('scopes lists globals without touching the device', () async {
    service.createSession('device');
    final backend = build();
    final page = await backend.scopes('device');
    expect(page, isNotNull);
    expect(page!.items.single['id'], 'globals');
    expect(page.items.single['name'], 'globals');
    expect(page.total, 1);
    expect(scripts, isEmpty);
  });

  test('scopes declines when another transaction is busy', () async {
    service.createSession('device');
    busy = true;
    final backend = build();
    expect(await backend.scopes('device'), isNull);
    expect(scripts, isEmpty);
  });

  test(
    'variables parses device JSON and mints generation-carrying references',
    () async {
      service.createSession('device');
      handler = (script) {
        expect(script, contains('__pyrite_globals_page(0, 100)'));
        expect(script, contains(_marker));
        return 'hello\n$_marker{"items": ['
            '{"name": "x", "type": "int", "repr": "5", "hasChildren": false, "reference": null},'
            '{"name": "lst", "type": "list", "repr": "[1, 2]", "hasChildren": true, "reference": "3"}'
            '], "total": 2, "start": 0}\n';
      };
      final backend = build();
      final page = await backend.variables(
        'device',
        'globals',
        start: 0,
        count: 100,
      );
      expect(page, isNotNull);
      expect(page!.total, 2);
      expect(page.start, 0);
      expect(page.items, hasLength(2));

      final plain = page.items[0];
      expect(plain['name'], 'x');
      expect(plain['type'], 'int');
      expect(plain['hasChildren'], false);
      expect(plain['reference'], isNull);

      final expandable = page.items[1];
      expect(expandable['hasChildren'], true);
      final token = expandable['reference'] as String;
      expect(token, 'runtime-device:generation-1:obj-3');
      expect(service.validate(token), ReferenceStatus.valid);
    },
  );

  test('globals page script resets the registry and truncates reprs', () async {
    service.createSession('device');
    handler = (_) => '$_marker{"items": [], "total": 0, "start": 0}';
    final backend = build();
    await backend.variables('device', 'globals', start: 0, count: 100);
    final script = scripts.single;
    expect(script, contains("if start == 0:"));
    expect(script, contains("g['__pyrite_refs'] = {}"));
    expect(script, contains("r[:1997] + '...'"));
  });

  test('variables forwards the page offset into the device script', () async {
    service.createSession('device');
    handler = (script) {
      expect(script, contains('__pyrite_globals_page(100, 100)'));
      return '$_marker{"items": [], "total": 250, "start": 100}';
    };
    final backend = build();
    final page = await backend.variables(
      'device',
      'globals',
      start: 100,
      count: 100,
    );
    expect(page!.total, 250);
    expect(page.start, 100);
  });

  test(
    'variables for an unknown scope returns an empty page without a script',
    () async {
      service.createSession('device');
      final backend = build();
      final page = await backend.variables('device', 'locals');
      expect(page!.items, isEmpty);
      expect(page.total, 0);
      expect(scripts, isEmpty);
    },
  );

  test('variables declines without running any script while busy', () async {
    service.createSession('device');
    busy = true;
    final backend = build();
    expect(await backend.variables('device', 'globals'), isNull);
    expect(scripts, isEmpty);
  });

  test('children resolves the object id from a valid reference token', () async {
    service.createSession('device');
    final token = service.reference('device', '5')!.encode();
    handler = (script) {
      expect(script, contains("__pyrite_children_page('5', 0, 100)"));
      return '$_marker{"items": ['
          '{"name": "0", "type": "int", "repr": "1", "hasChildren": false, "reference": null}'
          '], "total": 3, "start": 0}';
    };
    final backend = build();
    final page = await backend.children(token, start: 0, count: 100);
    expect(page, isNotNull);
    expect(page!.total, 3);
    expect(page.items.single['name'], '0');
  });

  test(
    'children of nested objects mint fresh references in the same session',
    () async {
      service.createSession('device');
      final token = service.reference('device', '5')!.encode();
      handler = (script) {
        expect(script, contains("__pyrite_children_page('5', 0, 100)"));
        return '$_marker{"items": ['
            '{"name": "inner", "type": "dict", "repr": "{}", "hasChildren": true, "reference": "9"}'
            '], "total": 1, "start": 0}';
      };
      final backend = build();
      final page = await backend.children(token, start: 0, count: 100);
      final childToken = page!.items.single['reference'] as String;
      expect(childToken, 'runtime-device:generation-1:obj-9');
      expect(service.validate(childToken), ReferenceStatus.valid);
    },
  );

  test(
    'children declines a malformed reference without running a script',
    () async {
      service.createSession('device');
      final backend = build();
      expect(await backend.children('not-a-reference'), isNull);
      expect(scripts, isEmpty);
    },
  );

  test('objectInfo returns type, repr and minted attribute references', () async {
    service.createSession('device');
    final token = service.reference('device', '7')!.encode();
    handler = (script) {
      expect(script, contains("__pyrite_info('7')"));
      return '$_marker{"type": "list", "repr": "[1]", "attributes": ['
          '{"name": "0", "type": "int", "repr": "1", "hasChildren": false, "reference": null},'
          '{"name": "nested", "type": "list", "repr": "[2]", "hasChildren": true, "reference": "11"}'
          ']}';
    };
    final backend = build();
    final info = await backend.objectInfo(token);
    expect(info, isNotNull);
    expect(info!['reference'], token);
    expect(info['type'], 'list');
    final attributes = info['attributes'] as List;
    expect(attributes, hasLength(2));
    final nested = attributes[1] as Map<String, dynamic>;
    expect(nested['reference'], 'runtime-device:generation-1:obj-11');
    expect(
      service.validate(nested['reference'] as String),
      ReferenceStatus.valid,
    );
  });

  test('a backend restart makes previously minted references stale', () async {
    service.createSession('device');
    handler = (_) =>
        '$_marker{"items": ['
        '{"name": "lst", "type": "list", "repr": "[]", "hasChildren": true, "reference": "3"}'
        '], "total": 1, "start": 0}';
    final backend = build();
    final page = await backend.variables('device', 'globals');
    final token = page!.items.single['reference'] as String;
    expect(service.validate(token), ReferenceStatus.valid);

    service.restartBackend('device');
    expect(service.validate(token), ReferenceStatus.stale);
    final fresh = service.reference('device', '3')!.encode();
    expect(fresh, 'runtime-device:generation-2:obj-3');
    expect(service.validate(fresh), ReferenceStatus.valid);
  });

  test('device failure yields null so the API reports unavailable', () async {
    service.createSession('device');
    handler = (_) => 'garbage without a marker line';
    final backend = build();
    expect(await backend.variables('device', 'globals'), isNull);
  });
}
