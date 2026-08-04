import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
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
                  'protocol_v1_events.json',
                ),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });

  test('events subscribe/emit/unsubscribe envelopes validate under v1', () {
    for (final key in const [
      'sdkEventsSubscribe',
      'sdkEventsSubscribeResponse',
      'ideEventEmit',
      'sdkEventsUnsubscribe',
    ]) {
      final envelope = PluginProtocol.validateIncoming(
        fixture[key] as Map<String, dynamic>,
      );
      expect(envelope['protocolVersion'], 1);
    }
  });

  test('fixture command names match the wire constants', () {
    expect(
      (fixture['sdkEventsSubscribe'] as Map<String, dynamic>)['type'],
      SdkCommands.eventsSubscribe,
    );
    expect(
      (fixture['sdkEventsUnsubscribe'] as Map<String, dynamic>)['type'],
      SdkCommands.eventsUnsubscribe,
    );
    expect(
      (fixture['ideEventEmit'] as Map<String, dynamic>)['type'],
      IdeCommands.eventEmit,
    );
  });

  test('emit fixture carries subscriptionId, topic, and events list', () {
    final payload =
        (fixture['ideEventEmit'] as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    expect(payload['subscriptionId'], 'sub-1');
    expect(payload['topic'], 'editor.document.changed');
    expect(payload['events'], isA<List<dynamic>>());
  });
}
