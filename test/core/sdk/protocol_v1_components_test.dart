import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/component_schema.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/protocol.dart';

Map<String, dynamic> _asMap(Object? value) =>
    (value as Map).map((k, v) => MapEntry(k.toString(), v));

void main() {
  late Map<String, dynamic> fixture;
  late ComponentRegistry registry;

  setUpAll(() {
    fixture =
        jsonDecode(
              File(
                path.join(
                  'test',
                  'fixtures',
                  'protocol',
                  'protocol_v1_components.json',
                ),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });

  setUp(() => registry = ComponentRegistry());

  test('fixture schema version matches the host', () {
    expect(fixture['schemaVersion'], componentSchemaVersion);
  });

  test('the acceptance page validates against the component registry', () {
    final result = registry.validate(_asMap(fixture['acceptancePage']));
    expect(
      result.isValid,
      isTrue,
      reason: result.diagnostics.map((d) => d.toString()).join('; '),
    );
  });

  test('the AppBar/Scaffold and Canvas v2 pages validate', () {
    for (final key in const ['appBarScaffoldPage', 'canvasPage']) {
      final result = registry.validate(_asMap(fixture[key]));
      expect(
        result.isValid,
        isTrue,
        reason: '$key: ${result.diagnostics.join('; ')}',
      );
    }
  });

  test('every invalid tree is rejected with the expected path and reason', () {
    final cases = fixture['invalidTrees'] as List;
    expect(cases, isNotEmpty);
    for (final entry in cases) {
      final testCase = _asMap(entry);
      final why = testCase['why'];
      final result = registry.validate(_asMap(testCase['node']));

      expect(result.isValid, isFalse, reason: 'should be invalid: $why');
      final matched = result.diagnostics.any(
        (d) =>
            d.path == testCase['expectedPath'] &&
            d.message.contains(testCase['expectedMessage'] as String),
      );
      expect(
        matched,
        isTrue,
        reason:
            '$why: expected "${testCase['expectedMessage']}" at '
            '"${testCase['expectedPath']}", got '
            '${result.diagnostics.map((d) => d.toString()).toList()}',
      );
    }
  });

  test('the component event envelope validates under protocol v1', () {
    final envelope = PluginProtocol.validateIncoming(
      _asMap(fixture['ideViewEvent']),
    );
    expect(envelope['protocolVersion'], 1);
    expect(envelope['type'], IdeCommands.viewEvent);
  });

  test('the component invoke envelope validates under protocol v1', () {
    final envelope = PluginProtocol.validateIncoming(
      _asMap(fixture['sdkComponentInvoke']),
    );
    expect(envelope['type'], SdkCommands.viewComponentInvoke);
    final payload = _asMap(envelope['payload']);
    expect(payload['componentId'], 'results');
    expect(payload['method'], 'reveal_item');
    expect(_asMap(payload['arguments'])['id'], 'b');
  });

  test(
    'Canvas invoke and semantic event envelopes validate under protocol v1',
    () {
      for (final key in const ['canvasInvokePushOps', 'canvasInvokeHitTest']) {
        final envelope = PluginProtocol.validateIncoming(_asMap(fixture[key]));
        expect(envelope['type'], SdkCommands.viewComponentInvoke, reason: key);
      }
      for (final key in const ['canvasDragEvent', 'canvasTapEvent']) {
        final envelope = PluginProtocol.validateIncoming(_asMap(fixture[key]));
        expect(envelope['type'], IdeCommands.viewEvent, reason: key);
      }
    },
  );

  test('the event fixture targets a component declared in the page', () {
    final payload = _asMap(_asMap(fixture['ideViewEvent'])['payload']);
    expect(payload['componentId'], 'results');
    expect(payload['event'], 'select');

    // The event name must be one the VirtualList component actually declares.
    final spec = registry.lookup('VirtualList')!;
    expect(spec.events.containsKey(payload['event']), isTrue);
    expect(_asMap(payload['payload'])['itemId'], 'b');
  });
}
