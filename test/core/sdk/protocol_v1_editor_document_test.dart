import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/api/document_api.dart';
import 'package:pyrite_ide/core/sdk/document_service.dart';
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
                  'protocol_v1_editor_document.json',
                ),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });

  test('editor document envelopes validate under protocol v1', () {
    for (final key in const [
      'sdkActiveDocumentGet',
      'sdkDocumentSymbols',
      'sdkDocumentSymbolsResponse',
      'sdkDocumentReveal',
      'ideActiveDocumentChanged',
      'ideDocumentChanged',
    ]) {
      final envelope = PluginProtocol.validateIncoming(
        fixture[key] as Map<String, dynamic>,
      );
      expect(envelope['protocolVersion'], 1);
    }
  });

  test('fixture command names match the wire constants', () {
    expect(
      (fixture['sdkActiveDocumentGet'] as Map<String, dynamic>)['type'],
      SdkEditorDocumentCommands.activeDocumentGet,
    );
    expect(
      (fixture['sdkDocumentSymbols'] as Map<String, dynamic>)['type'],
      SdkEditorDocumentCommands.documentSymbols,
    );
    expect(
      (fixture['sdkDocumentReveal'] as Map<String, dynamic>)['type'],
      SdkEditorDocumentCommands.documentReveal,
    );
    expect(
      (fixture['ideActiveDocumentChanged'] as Map<String, dynamic>)['type'],
      IdeCommands.eventEmit,
    );
  });

  test('emit fixtures target the document lifecycle topics', () {
    final active =
        (fixture['ideActiveDocumentChanged'] as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    expect(active['topic'], DocumentTopics.activeChanged);

    final changed =
        (fixture['ideDocumentChanged'] as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    expect(changed['topic'], DocumentTopics.changed);
    // document.changed carries incremental changes, not the full body.
    final events = changed['events'] as List<dynamic>;
    expect((events.single as Map<String, dynamic>)['changes'], [
      {'start': 120, 'end': 128},
    ]);
  });

  test('symbols response is tagged with revision and staleness', () {
    final data =
        ((fixture['sdkDocumentSymbolsResponse']
                    as Map<String, dynamic>)['payload']
                as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    expect(data['revision'], 18);
    expect(data['stale'], false);
    expect((data['symbols'] as List).single['name'], 'Widget');
  });
}
