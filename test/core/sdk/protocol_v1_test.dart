import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/protocol.dart';

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
                  'protocol_v1_handshake.json',
                ),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });

  test('v1 handshake fixture validates in order', () {
    final first = PluginProtocol.validateIncoming(
      fixture['ideInitialize'] as Map<String, dynamic>,
    );
    expect(first['type'], 'ide.initialize');
    final second = PluginProtocol.validateIncoming(
      fixture['ideInitialized'] as Map<String, dynamic>,
      lastSequence: 1,
    );
    expect(second['type'], 'ide.initialized');
  });

  test('unsupported version and duplicate sequence are rejected', () {
    final invalidVersion = Map<String, dynamic>.from(
      fixture['ideInitialize'] as Map<String, dynamic>,
    )..['protocolVersion'] = 0;
    expect(
      () => PluginProtocol.validateIncoming(invalidVersion),
      throwsA(isA<PluginProtocolException>()),
    );

    expect(
      () => PluginProtocol.validateIncoming(
        fixture['ideInitialized'] as Map<String, dynamic>,
        lastSequence: 2,
      ),
      throwsA(isA<PluginProtocolException>()),
    );
  });

  test('deadline request and cancellation fixture validate in order', () {
    final request = PluginProtocol.validateIncoming(
      fixture['ideTimedRequest'] as Map<String, dynamic>,
      lastSequence: 2,
    );
    expect(request['deadline'], 1700000005104);
    final cancel = PluginProtocol.validateIncoming(
      fixture['ideRequestCancel'] as Map<String, dynamic>,
      lastSequence: 3,
    );
    expect(cancel['payload']['requestId'], request['requestId']);
  });
}
