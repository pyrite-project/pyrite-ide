import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/document_service.dart';

class _Emission {
  _Emission(this.topic, this.payload);
  final String topic;
  final Map<String, dynamic> payload;
}

void main() {
  late List<_Emission> emissions;
  late PluginDocumentService service;

  setUp(() {
    emissions = [];
    service = PluginDocumentService(
      emit: (topic, payload) => emissions.add(_Emission(topic, payload)),
    );
  });

  DocumentSnapshot snap(
    Object handle, {
    String path = '/a.py',
    bool saved = true,
    bool active = false,
    int revision = 1,
    String? lang = 'python',
  }) => DocumentSnapshot(
    handle: handle,
    filePath: path,
    isSaved: saved,
    isActive: active,
    languageId: lang,
    revision: revision,
  );

  List<String> topics() => emissions.map((e) => e.topic).toList();

  test('opening a document emits opened and activeDocument.changed', () {
    final h = Object();
    service.syncDocuments([snap(h, active: true)]);
    expect(topics(), [DocumentTopics.opened, DocumentTopics.activeChanged]);
    final opened = emissions.first.payload;
    expect(opened['filePath'], '/a.py');
    expect(opened['languageId'], 'python');
  });

  test('a dirty->clean transition emits saved', () {
    final h = Object();
    service.syncDocuments([snap(h, active: true, saved: false)]);
    emissions.clear();
    service.syncDocuments([snap(h, active: true, saved: true, revision: 2)]);
    expect(topics(), contains(DocumentTopics.saved));
    final saved = emissions.firstWhere((e) => e.topic == DocumentTopics.saved);
    expect(saved.payload['revision'], 2);
  });

  test('removing a document emits closed', () {
    final h = Object();
    service.syncDocuments([snap(h, active: true)]);
    emissions.clear();
    service.syncDocuments([]);
    expect(topics(), contains(DocumentTopics.closed));
  });

  test('switching active document emits activeDocument.changed once', () {
    final a = Object();
    final b = Object();
    service.syncDocuments([
      snap(a, path: '/a.py', active: true),
      snap(b, path: '/b.py'),
    ]);
    emissions.clear();
    service.syncDocuments([
      snap(a, path: '/a.py'),
      snap(b, path: '/b.py', active: true),
    ]);
    final active = emissions
        .where((e) => e.topic == DocumentTopics.activeChanged)
        .toList();
    expect(active, hasLength(1));
    expect(active.single.payload['filePath'], '/b.py');
  });

  test('content change emits incremental changes, not full body', () {
    final h = Object();
    service.syncDocuments([snap(h, active: true)]);
    emissions.clear();
    service.notifyContentChanged(
      h,
      revision: 5,
      changedRange: (start: 3, end: 7),
    );
    expect(topics(), [DocumentTopics.changed]);
    final payload = emissions.single.payload;
    expect(payload['revision'], 5);
    expect(payload['changes'], [
      {'start': 3, 'end': 7},
    ]);
    expect(payload.containsKey('text'), isFalse);
  });

  test('selection change emits selection.changed with offsets', () {
    final h = Object();
    service.syncDocuments([snap(h, active: true)]);
    emissions.clear();
    service.notifySelectionChanged(h, start: 2, end: 9);
    expect(topics(), [DocumentTopics.selectionChanged]);
    expect(emissions.single.payload['selection'], {'start': 2, 'end': 9});
  });

  test('content/selection changes for an unknown handle are ignored', () {
    service.notifyContentChanged(Object(), revision: 1);
    service.notifySelectionChanged(Object(), start: 0, end: 0);
    expect(emissions, isEmpty);
  });
}
