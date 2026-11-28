import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/sdk/editor_document_host.dart';
import 'package:pyrite_ide/core/sdk/environment_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:tabbed_view/tabbed_view.dart';

/// A controller stand-in exposing only what the document host reads while it
/// syncs the tab model.
class _StubEditorController implements CodeForgeController {
  _StubEditorController(this._text);

  String _text;
  final List<VoidCallback> _listeners = [];

  @override
  String get text => _text;

  @override
  set text(String value) => _text = value;

  @override
  int get contentVersion => 0;

  @override
  bool readOnly = false;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a renamed tab rebases the document registry and handle paths', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const oldPath = '/proj/a.py';
    const newPath = '/proj/lib/a.py';
    final editor = _StubEditorController('print(1)');
    final tab = TabData(
      text: 'a.py',
      value: TabDataValue(
        type: 'file',
        filePath: oldPath,
        file: File(oldPath),
        editorController: editor,
      ),
    );
    final group = container.read(tabbedViewControllerProvider);
    group.addTab(tab);
    group.selectedIndex = group.tabs.length - 1;

    final host = container.read(editorDocumentHostProvider);
    final documentId = host.activeDocumentId!;
    expect(host.registry.byId(documentId)!.filePath, oldPath);

    container
        .read(tabbedViewControllerProvider.notifier)
        .renameLocalOpenPath(oldPath, newPath);

    final renamed = host.registry.byId(documentId)!;
    expect(renamed.documentId, documentId);
    expect(renamed.filePath, newPath);
    // The handle is the read-only access path; it must follow the tab too.
    expect((renamed.handle as dynamic).filePath, newPath);
  });

  test('reveal waits for a compact-layout editor to mount', () async {
    var preparationCount = 0;
    var waitCount = 0;
    var mounted = false;
    var revealed = false;

    await retryEditorReveal(
      maxAttempts: 3,
      reveal: () {
        if (!mounted) throw StateError('Editor is not initialized');
        revealed = true;
      },
      onEditorUnavailable: () => preparationCount++,
      waitForRetry: () async {
        waitCount++;
        mounted = true;
      },
    );

    expect(preparationCount, 1);
    expect(waitCount, 1);
    expect(revealed, isTrue);
  });

  test('reveal times out cleanly when the editor never mounts', () async {
    await expectLater(
      retryEditorReveal(
        maxAttempts: 2,
        reveal: () => throw StateError('Editor is not initialized'),
        waitForRetry: () async {},
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('only compact layouts navigate to the dedicated editor route', () {
    expect(layoutNeedsDedicatedEditorRoute(LayoutMode.mobile), isTrue);
    expect(layoutNeedsDedicatedEditorRoute(LayoutMode.tablet), isTrue);
    expect(layoutNeedsDedicatedEditorRoute(LayoutMode.desktop), isFalse);
  });
}
