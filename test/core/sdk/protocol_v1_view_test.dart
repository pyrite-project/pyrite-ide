import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/protocol.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';

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
                  'protocol_v1_view.json',
                ),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });

  test('view envelopes validate under protocol v1', () {
    for (final key in const [
      'sdkViewSnapshot',
      'sdkViewPatch',
      'ideViewAck',
      'ideViewNack',
      'ideViewResync',
      'ideViewVisibilityChanged',
    ]) {
      final envelope = PluginProtocol.validateIncoming(
        fixture[key] as Map<String, dynamic>,
      );
      expect(envelope['protocolVersion'], 1);
    }
  });

  test('fixture message names match the wire constants', () {
    expect(
      (fixture['sdkViewSnapshot'] as Map<String, dynamic>)['type'],
      SdkCommands.viewSnapshot,
    );
    expect(
      (fixture['sdkViewPatch'] as Map<String, dynamic>)['type'],
      SdkCommands.viewPatch,
    );
    expect(
      (fixture['ideViewAck'] as Map<String, dynamic>)['type'],
      IdeCommands.viewAck,
    );
    expect(
      (fixture['ideViewNack'] as Map<String, dynamic>)['type'],
      IdeCommands.viewNack,
    );
    expect(
      (fixture['ideViewResync'] as Map<String, dynamic>)['type'],
      IdeCommands.viewResync,
    );
    expect(
      (fixture['ideViewVisibilityChanged'] as Map<String, dynamic>)['type'],
      IdeCommands.viewVisibilityChanged,
    );
  });

  test('the fixture snapshot and patch apply against a real store', () {
    final store = ViewModelStore();
    final snapshotPayload =
        (fixture['sdkViewSnapshot'] as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    const instance = ViewInstanceId(
      pluginId: 'outline-view',
      sessionId: 'session-42',
      viewId: 'outline',
      instanceId: 'inst-1',
    );
    store.installSnapshot(
      instance: instance,
      revision: snapshotPayload['revision'] as int,
      nodes: [
        for (final n in snapshotPayload['nodes'] as List)
          (n as Map).map((k, v) => MapEntry(k.toString(), v)),
      ],
    );

    final patchPayload =
        (fixture['sdkViewPatch'] as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    final result = store.applyPatch(
      instance: instance,
      baseRevision: patchPayload['baseRevision'] as int,
      nextRevision: patchPayload['revision'] as int,
      ops: [
        for (final op in patchPayload['ops'] as List)
          PatchOp.fromJson(
            (op as Map).map((k, v) => MapEntry(k.toString(), v)),
          ),
      ],
    );

    expect(result.isOk, isTrue);
    expect(result.revision, 2);
    // insert n3 -> update n1 -> move n3 to front -> remove n2.
    final model = store.model(instance)!;
    expect(model.nodes.map((n) => n['id']), ['n3', 'n1']);
    expect(model.nodes.last['label'], 'Widget2');
  });

  test('the nack fixture reports a revision gap and the resync carries the '
      'host revision', () {
    final nack =
        (fixture['ideViewNack'] as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    expect(nack['reason'], PatchRejection.revisionGap.name);

    final resync =
        (fixture['ideViewResync'] as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    expect(resync['revision'], 2);
    expect(
      (resync['instance'] as Map<String, dynamic>)['instanceId'],
      'inst-1',
    );
  });
}
