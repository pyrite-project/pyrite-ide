import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/document_registry.dart';

void main() {
  test('register mints a stable id and re-registering keeps it', () {
    var n = 0;
    final registry = DocumentRegistry(idFactory: () => 'id-${++n}');
    final handle = Object();

    final first = registry.register(handle: handle, filePath: '/a.py');
    final again = registry.register(handle: handle, filePath: '/a.py');

    expect(first.documentId, 'id-1');
    expect(again.documentId, 'id-1');
    expect(registry.length, 1);
  });

  test('reopening a closed handle yields a new id', () {
    var n = 0;
    final registry = DocumentRegistry(idFactory: () => 'id-${++n}');
    final firstHandle = Object();
    final firstId = registry
        .register(handle: firstHandle, filePath: '/a.py')
        .documentId;
    registry.unregister(firstHandle);

    // A close-then-reopen of the same path is a different handle.
    final secondId = registry
        .register(handle: Object(), filePath: '/a.py')
        .documentId;
    expect(secondId, isNot(firstId));
  });

  test('re-registering updates the language when it becomes known', () {
    final registry = DocumentRegistry(idFactory: () => 'id');
    final handle = Object();
    registry.register(handle: handle, filePath: '/a.py');
    final updated = registry.register(
      handle: handle,
      filePath: '/a.py',
      languageId: 'python',
    );
    expect(updated.languageId, 'python');
    expect(registry.byId('id')!.languageId, 'python');
  });

  test('byId resolves and clears on unregister', () {
    final registry = DocumentRegistry(idFactory: () => 'id');
    final handle = Object();
    registry.register(handle: handle, filePath: '/a.py');
    expect(registry.byId('id'), isNotNull);
    registry.unregister(handle);
    expect(registry.byId('id'), isNull);
  });

  test('active tracks the focused handle and clears on unregister', () {
    final registry = DocumentRegistry(idFactory: () => 'id');
    final handle = Object();
    registry.register(handle: handle, filePath: '/a.py');
    registry.setActive(handle);
    expect(registry.active?.documentId, 'id');

    registry.unregister(handle);
    expect(registry.active, isNull);
  });

  test('setActive with an unknown handle clears the active document', () {
    final registry = DocumentRegistry();
    final known = Object();
    registry.register(handle: known, filePath: '/a.py');
    registry.setActive(known);
    registry.setActive(Object());
    expect(registry.active, isNull);
  });

  test('toJson exposes id, path, revision, and active flag', () {
    final registry = DocumentRegistry(idFactory: () => 'id');
    final doc = registry.register(
      handle: Object(),
      filePath: '/a.py',
      languageId: 'python',
    );
    expect(doc.toJson(revision: 5, isActive: true), {
      'documentId': 'id',
      'filePath': '/a.py',
      'languageId': 'python',
      'revision': 5,
      'isActive': true,
    });
  });
}
