import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/api/runtime_api.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/protocol.dart';
import 'package:pyrite_ide/core/sdk/runtime_inspection.dart';

void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() {
    fixture =
        jsonDecode(
              File(
                path.join(
                  'test',
                  'fixtures',
                  'protocol',
                  'protocol_v1_runtime.json',
                ),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });

  test('runtime envelopes validate under protocol v1', () {
    for (final key in const [
      'sdkRuntimeVariables',
      'sdkRuntimeVariablesResponse',
      'sdkRuntimeChildren',
      'ideProgramPaused',
      'ideBackendRestarted',
    ]) {
      final envelope = PluginProtocol.validateIncoming(
        fixture[key] as Map<String, dynamic>,
      );
      expect(envelope['protocolVersion'], 1);
    }
  });

  test('fixture command names match the wire constants', () {
    expect(
      (fixture['sdkRuntimeVariables'] as Map<String, dynamic>)['type'],
      SdkRuntimeCommands.variables,
    );
    expect(
      (fixture['sdkRuntimeChildren'] as Map<String, dynamic>)['type'],
      SdkRuntimeCommands.children,
    );
    expect(
      (fixture['ideProgramPaused'] as Map<String, dynamic>)['type'],
      IdeCommands.eventEmit,
    );
  });

  test('emit fixtures target runtime lifecycle topics', () {
    final paused =
        (fixture['ideProgramPaused'] as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    expect(paused['topic'], RuntimeTopics.programPaused);

    final restarted =
        (fixture['ideBackendRestarted'] as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    expect(restarted['topic'], RuntimeTopics.backendRestarted);
  });

  test(
    'variable reference in the fixture is a parseable runtime reference',
    () {
      final data =
          ((fixture['sdkRuntimeVariablesResponse']
                      as Map<String, dynamic>)['payload']
                  as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final variable = (data['items'] as List).single as Map<String, dynamic>;
      final ref = RuntimeReference.tryParse(variable['reference'] as String);
      expect(ref, isNotNull);
      expect(ref!.sessionId, 'device');
      expect(ref.generation, 4);
      expect(ref.objectId, '42');
      // The restart event bumps to generation 5, which would make this stale.
      final restarted =
          (((fixture['ideBackendRestarted'] as Map<String, dynamic>)['payload']
                          as Map<String, dynamic>)['events']
                      as List)
                  .single
              as Map<String, dynamic>;
      expect(restarted['generation'], greaterThan(ref.generation));
    },
  );
}
