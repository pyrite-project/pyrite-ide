import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/repl_completion_controller.dart';

void main() {
  test('extracts a global token and its replacement range', () {
    final context = ReplCompletionContext.fromText('value = pri', 11);

    expect(context.token, 'pri');
    expect(context.replaceStart, 8);
    expect(context.replaceEnd, 11);
    expect(context.isMemberAccess, isFalse);
    expect(context.shouldQueryRuntime, isTrue);
  });

  test('queries runtime globals only after an automatic trigger', () {
    expect(ReplCompletionContext.fromText('a', 1).shouldQueryRuntime, isFalse);
    expect(ReplCompletionContext.fromText('ab', 2).shouldQueryRuntime, isTrue);
    expect(
      ReplCompletionContext.fromText('a', 1, manual: true).shouldQueryRuntime,
      isTrue,
    );
  });

  test('extracts a member owner without replacing the owner', () {
    final context = ReplCompletionContext.fromText('machine.P', 9);

    expect(context.owner, 'machine');
    expect(context.token, 'P');
    expect(context.replaceStart, 8);
    expect(context.isMemberAccess, isTrue);
  });

  test('returns static global and MicroPython member candidates', () async {
    final globals = await ReplCompletionCatalog.complete(
      ReplCompletionContext.fromText('pri', 3),
    );
    final members = await ReplCompletionCatalog.complete(
      ReplCompletionContext.fromText('machine.P', 9),
    );

    expect(globals.map((item) => item.label), contains('print'));
    expect(members.map((item) => item.label), containsAll(['Pin', 'PWM']));
    expect(members.every((item) => item.replaceStart == 8), isTrue);
  });

  test('drops a completion response after a newer request', () async {
    final first = Completer<List<ReplCompletionItem>>();
    final second = Completer<List<ReplCompletionItem>>();
    var requests = 0;
    final controller = ReplCompletionController(
      provider: (_) => requests++ == 0 ? first.future : second.future,
    );
    addTearDown(controller.dispose);

    final firstRequest = controller.request(
      ReplCompletionContext.fromText('a', 1),
    );
    final secondRequest = controller.request(
      ReplCompletionContext.fromText('ab', 2),
    );
    second.complete([_candidate('about')]);
    await secondRequest;
    first.complete([_candidate('abs')]);
    await firstRequest;

    expect(controller.items.single.label, 'about');
  });

  test('wraps keyboard selection through the candidate list', () async {
    final controller = ReplCompletionController(
      provider: (_) async => [_candidate('a'), _candidate('b')],
    );
    addTearDown(controller.dispose);
    await controller.request(ReplCompletionContext.fromText('a', 1));

    controller.move(-1);
    expect(controller.selected?.label, 'b');
    controller.move(1);
    expect(controller.selected?.label, 'a');
  });

  test('finds the active callable and parameter in nested input', () {
    final context = ReplSignatureContext.fromText(
      'result = print(inner(1, 2), ',
      28,
      triggerCharacter: ',',
    );

    expect(context, isNotNull);
    expect(context!.callable, 'print');
    expect(context.activeParameter, 1);
  });

  test('does not count commas inside strings as parameters', () {
    final context = ReplSignatureContext.fromText('print("a,b", ', 13);

    expect(context?.activeParameter, 1);
  });

  test(
    'returns a local MicroPython signature when LSP is unavailable',
    () async {
      final context = ReplSignatureContext.fromText(
        'machine.Pin(',
        12,
        triggerCharacter: '(',
      );

      final hint = await ReplSignatureCatalog.find(context!);
      expect(hint?.label, contains('machine.Pin(id'));
    },
  );
}

ReplCompletionItem _candidate(String label) => ReplCompletionItem(
  label: label,
  insertText: label,
  replaceStart: 0,
  replaceEnd: 1,
  kind: ReplCompletionKind.text,
  source: ReplCompletionSource.staticCatalog,
);
