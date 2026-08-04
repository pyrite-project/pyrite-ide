import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';

ViewInstanceId _instance({String instanceId = 'i1'}) => ViewInstanceId(
  pluginId: 'p',
  sessionId: 's',
  viewId: 'outline',
  instanceId: instanceId,
);

List<Map<String, dynamic>> _nodes(ViewModel model) =>
    model.nodes.map((n) => Map<String, dynamic>.from(n)).toList();

void main() {
  test('instancesForPlugin returns only matching live models', () {
    final store = ViewModelStore();
    final matching = _instance();
    const other = ViewInstanceId(
      pluginId: 'other',
      sessionId: 's',
      viewId: 'outline',
      instanceId: 'i2',
    );
    store.installSnapshot(instance: matching, revision: 1, nodes: const []);
    store.installSnapshot(instance: other, revision: 1, nodes: const []);

    expect(store.instancesForPlugin('p'), [matching]);
  });

  group('snapshot + patch ops', () {
    late ViewModelStore store;
    late ViewInstanceId instance;

    setUp(() {
      store = ViewModelStore();
      instance = _instance();
      store.installSnapshot(
        instance: instance,
        revision: 1,
        nodes: [
          {'id': 'a', 'label': 'A'},
          {'id': 'b', 'label': 'B'},
        ],
      );
    });

    test('insert/update/remove/move apply in one transaction', () {
      final result = store.applyPatch(
        instance: instance,
        baseRevision: 1,
        nextRevision: 2,
        ops: [
          const PatchOp(
            kind: PatchOpKind.insert,
            id: 'c',
            index: 2,
            data: {'label': 'C'},
          ),
          const PatchOp(
            kind: PatchOpKind.update,
            id: 'a',
            data: {'label': 'A2'},
          ),
          const PatchOp(kind: PatchOpKind.remove, id: 'b'),
          const PatchOp(kind: PatchOpKind.move, id: 'c', index: 0),
        ],
      );
      expect(result.isOk, isTrue);
      expect(result.revision, 2);
      final model = store.model(instance)!;
      expect(_nodes(model), [
        {'id': 'c', 'label': 'C'},
        {'id': 'a', 'label': 'A2'},
      ]);
    });

    test('a bad op rolls back the whole transaction', () {
      final result = store.applyPatch(
        instance: instance,
        baseRevision: 1,
        nextRevision: 2,
        ops: [
          const PatchOp(
            kind: PatchOpKind.update,
            id: 'a',
            data: {'label': 'CHANGED'},
          ),
          // 'zzz' does not exist -> whole patch must roll back.
          const PatchOp(kind: PatchOpKind.remove, id: 'zzz'),
        ],
      );
      expect(result.isOk, isFalse);
      expect(result.rejection, PatchRejection.invalidOperation);
      final model = store.model(instance)!;
      // Revision unchanged and 'a' NOT modified: no partial state.
      expect(model.revision, 1);
      expect(model.nodes.first['label'], 'A');
    });

    test('revision gap is rejected and asks for resync', () {
      final result = store.applyPatch(
        instance: instance,
        baseRevision: 5, // model is at 1
        nextRevision: 6,
        ops: [const PatchOp(kind: PatchOpKind.remove, id: 'a')],
      );
      expect(result.rejection, PatchRejection.revisionGap);
      expect(store.model(instance)!.revision, 1);
    });

    test('duplicate insert id is rejected without partial state', () {
      final result = store.applyPatch(
        instance: instance,
        baseRevision: 1,
        nextRevision: 2,
        ops: [
          const PatchOp(
            kind: PatchOpKind.insert,
            id: 'a',
            data: {'label': 'dup'},
          ),
        ],
      );
      expect(result.rejection, PatchRejection.invalidOperation);
      expect(store.model(instance)!.nodes.length, 2);
    });

    test('state becomes empty when the last node is removed', () {
      store.applyPatch(
        instance: instance,
        baseRevision: 1,
        nextRevision: 2,
        ops: [
          const PatchOp(kind: PatchOpKind.remove, id: 'a'),
          const PatchOp(kind: PatchOpKind.remove, id: 'b'),
        ],
      );
      expect(store.model(instance)!.state, ViewState.empty);
    });
  });

  group('resync + close + isolation', () {
    test('a fresh snapshot resets revision and content', () {
      final store = ViewModelStore();
      final instance = _instance();
      store.installSnapshot(instance: instance, revision: 9, nodes: []);
      expect(store.model(instance)!.revision, 9);
      expect(store.model(instance)!.state, ViewState.empty);

      store.installSnapshot(
        instance: instance,
        revision: 1,
        nodes: [
          {'id': 'x'},
        ],
      );
      expect(store.model(instance)!.revision, 1);
      expect(store.model(instance)!.nodes.single['id'], 'x');
    });

    test('patch to a never-snapshotted instance asks for snapshot', () {
      final store = ViewModelStore();
      final result = store.applyPatch(
        instance: _instance(),
        baseRevision: 0,
        nextRevision: 1,
        ops: const [],
      );
      expect(result.rejection, PatchRejection.noSnapshot);
    });

    test('a closed view rejects further patches', () {
      final store = ViewModelStore();
      final instance = _instance();
      store.installSnapshot(instance: instance, revision: 1, nodes: []);
      store.close(instance);
      final result = store.applyPatch(
        instance: instance,
        baseRevision: 1,
        nextRevision: 2,
        ops: const [],
      );
      // After close the instance is removed, so it reads as noSnapshot.
      expect(result.isOk, isFalse);
    });

    test('two instances of the same view do not share state', () {
      final store = ViewModelStore();
      final a = _instance(instanceId: 'a');
      final b = _instance(instanceId: 'b');
      store.installSnapshot(
        instance: a,
        revision: 1,
        nodes: [
          {'id': 'a-node'},
        ],
      );
      store.installSnapshot(
        instance: b,
        revision: 1,
        nodes: [
          {'id': 'b-node'},
        ],
      );
      store.applyPatch(
        instance: a,
        baseRevision: 1,
        nextRevision: 2,
        ops: [const PatchOp(kind: PatchOpKind.insert, id: 'a2', data: {})],
      );
      expect(store.model(a)!.nodes.length, 2);
      expect(store.model(b)!.nodes.length, 1);
      expect(store.model(b)!.revision, 1);
    });

    test('clearSession drops only the matching session', () {
      final store = ViewModelStore();
      store.installSnapshot(
        instance: const ViewInstanceId(
          pluginId: 'p',
          sessionId: 'old',
          viewId: 'v',
          instanceId: 'i',
        ),
        revision: 1,
        nodes: [],
      );
      store.installSnapshot(
        instance: const ViewInstanceId(
          pluginId: 'p',
          sessionId: 'new',
          viewId: 'v',
          instanceId: 'i',
        ),
        revision: 1,
        nodes: [],
      );
      store.clearSession('p', 'old');
      expect(store.length, 1);
    });
  });

  group('PatchOp.fromJson', () {
    test('parses ops and rejects unknown/missing fields', () {
      final op = PatchOp.fromJson({
        'op': 'insert',
        'id': 'x',
        'index': 3,
        'data': {'label': 'X'},
      });
      expect(op.kind, PatchOpKind.insert);
      expect(op.index, 3);

      expect(
        () => PatchOp.fromJson({'op': 'frobnicate', 'id': 'x'}),
        throwsA(isA<ViewProtocolException>()),
      );
      expect(
        () => PatchOp.fromJson({'op': 'remove'}),
        throwsA(isA<ViewProtocolException>()),
      );
    });
  });
}
