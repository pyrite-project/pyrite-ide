import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/editor_document_host.dart';
import 'package:pyrite_ide/core/sdk/environment_provider.dart';

void main() {
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
