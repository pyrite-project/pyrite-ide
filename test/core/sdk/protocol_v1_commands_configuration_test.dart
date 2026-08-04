import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/protocol.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/protocol/protocol_v1_commands_configuration.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('command and configuration envelopes validate', () {
    var sequence = 0;
    for (final entry in fixture.entries) {
      final raw = Map<String, dynamic>.from(entry.value as Map);
      final validated = PluginProtocol.validateIncoming(
        raw,
        lastSequence: sequence,
      );
      expect(validated['type'], raw['type']);
      sequence = validated['sequence'] as int;
    }
  });

  test('fixture types cover execute get set list and changed', () {
    expect(fixture['commandExecute']['type'], 'ide.command.execute');
    expect(fixture['configurationGet']['type'], 'sdk.configuration.get');
    expect(fixture['configurationSet']['type'], 'sdk.configuration.set');
    expect(fixture['configurationList']['type'], 'sdk.configuration.list');
    expect(fixture['configurationChanged']['type'], 'ide.event.emit');
    expect(
      fixture['configurationChanged']['payload']['topic'],
      'configuration.changed',
    );
  });
}
