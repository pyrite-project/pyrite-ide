import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/services/editor/repl_completion_controller.dart';
import 'package:pyrite_ide/core/services/editor/repl_history_store.dart';
import 'package:pyrite_ide/core/services/editor/repl_input_controller.dart';

void main() {
  group('ReplInputController', () {
    test('keeps an input surface available while a program is running', () {
      final controller = ReplInputController();
      addTearDown(controller.dispose);

      controller.setMode(ReplInteractionMode.passthrough);

      expect(controller.hasVisibleInput, isTrue);
      expect(controller.isInlineEditable, isFalse);
    });

    late ReplInputController controller;

    setUp(() {
      controller = ReplInputController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('recognizes complete and incomplete Python input', () {
      controller.text.text = 'print(1)';
      expect(controller.canSubmit, isTrue);

      controller.text.text = 'if ready:';
      expect(controller.canSubmit, isFalse);

      controller.text.text = 'print(';
      expect(controller.canSubmit, isFalse);

      controller.text.text = "print('ready')";
      expect(controller.canSubmit, isTrue);
    });

    test('adds indentation after a block opener', () {
      controller.text.text = 'if ready:';
      controller.text.selection = const TextSelection(
        baseOffset: 9,
        extentOffset: 9,
      );

      controller.insertIndentedNewline();

      expect(controller.text.text, 'if ready:\n    ');
    });

    test('backspace removes one leading indentation unit', () {
      controller.text.value = const TextEditingValue(
        text: 'for i in range(5):\n        ',
        selection: TextSelection.collapsed(offset: 27),
      );

      expect(controller.deleteIndentationUnit(), isTrue);
      expect(controller.text.text, 'for i in range(5):\n    ');
      expect(controller.text.selection.baseOffset, 23);
    });

    test('backspace leaves spaces inside source text to the editor', () {
      controller.text.value = const TextEditingValue(
        text: '    print',
        selection: TextSelection.collapsed(offset: 9),
      );

      expect(controller.deleteIndentationUnit(), isFalse);
      expect(controller.text.text, '    print');
    });

    test('completion replaces only the active token', () {
      controller.text.value = const TextEditingValue(
        text: 'value = pri + 1',
        selection: TextSelection.collapsed(offset: 11),
      );

      controller.applyCompletion(
        const ReplCompletionItem(
          label: 'print',
          insertText: 'print',
          replaceStart: 8,
          replaceEnd: 11,
          kind: ReplCompletionKind.builtin,
          source: ReplCompletionSource.staticCatalog,
        ),
      );

      expect(controller.text.text, 'value = print + 1');
      expect(controller.text.selection.baseOffset, 13);
    });

    test('submits compound input only after an empty line', () {
      controller.text.value = const TextEditingValue(
        text: 'if ready:\n    print(1)',
        selection: TextSelection(baseOffset: 22, extentOffset: 22),
      );

      expect(controller.handleEnter(), isFalse);
      expect(controller.text.text, 'if ready:\n    print(1)\n    ');
      expect(controller.handleEnter(), isTrue);
      expect(controller.canSubmit, isTrue);
    });

    test('ignores brackets inside comments and triple quoted strings', () {
      controller.text.text = "value = '''('''  # [";
      expect(controller.canSubmit, isTrue);
    });

    test('restores the draft after history navigation', () {
      controller.setMode(ReplInteractionMode.prompt);
      controller.text.text = 'first()';
      expect(controller.takeSubmission(), 'first()');
      controller.setMode(ReplInteractionMode.prompt);
      controller.text.text = 'second()';
      expect(controller.takeSubmission(), 'second()');
      controller.setMode(ReplInteractionMode.prompt);
      controller.text.text = 'draft';

      expect(controller.showPreviousHistory(), isTrue);
      expect(controller.text.text, 'second()');
      expect(controller.showPreviousHistory(), isTrue);
      expect(controller.text.text, 'first()');
      expect(controller.showNextHistory(), isTrue);
      expect(controller.text.text, 'second()');
      expect(controller.showNextHistory(), isTrue);
      expect(controller.text.text, 'draft');
    });
  });

  test('formats multiline input as a clean local transcript', () {
    final payload = formatReplSubmissionEcho(
      'for i in range(5):\n    print(i)\n\n',
    );

    expect(payload, 'for i in range(5):\r\n...     print(i)\r\n');
  });

  test('formats a single line without adding a continuation prompt', () {
    expect(formatReplSubmissionEcho('print(1)'), 'print(1)\r\n');
  });

  test('tracks prompts across fragmented output', () {
    final modes = <ReplInteractionMode>[];
    final tracker = ReplPromptTracker(onMode: modes.add);

    tracker.add('boot\n>');
    tracker.add('>> ');
    tracker.add('\n... ');

    expect(modes, [
      ReplInteractionMode.prompt,
      ReplInteractionMode.continuation,
    ]);
  });

  test('tracks prompts wrapped in ANSI output and split escape sequences', () {
    final modes = <ReplInteractionMode>[];
    final tracker = ReplPromptTracker(onMode: modes.add);

    tracker.add('\x1b[32');
    tracker.add('m>>> \x1b[0m');
    tracker.add('\n\x1b[33m.');
    tracker.add('.. \x1b[0m');

    expect(modes, [
      ReplInteractionMode.prompt,
      ReplInteractionMode.continuation,
    ]);
  });

  test('reset discards an incomplete ANSI sequence', () {
    final modes = <ReplInteractionMode>[];
    final tracker = ReplPromptTracker(onMode: modes.add);

    tracker.add('\x1b[');
    tracker.reset();
    tracker.add('>>> ');

    expect(modes, [ReplInteractionMode.unknown, ReplInteractionMode.prompt]);
  });

  group('history buckets', () {
    late Directory dir;
    final controllers = <ReplInputController>[];

    ReplInputController make({String bucket = '', ReplHistoryStore? store}) {
      final controller = ReplInputController(
        store: store ?? ReplHistoryStore(directory: dir.path),
        deviceBucket: bucket,
      );
      controllers.add(controller);
      return controller;
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('pyrite_repl_bucket_');
    });

    tearDown(() async {
      for (final controller in controllers) {
        controller.dispose();
      }
      controllers.clear();
      // dispose() writes the history out in the background; deleting the
      // directory under it fails on Windows until that write has closed.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    ReplHistoryStore store() => ReplHistoryStore(directory: dir.path);

    /// The command the Up-arrow would show, or null when history is empty.
    String? pageBack(ReplInputController controller) =>
        controller.showPreviousHistory() ? controller.text.text : null;

    test('a command recorded on one device does not leak to another', () async {
      final controller = make(bucket: 'COM3');

      controller.text.text = 'import webrepl';
      controller.takeSubmission();
      await controller.flushHistory();

      await controller.useDeviceBucket('COM7');

      expect(controller.deviceBucket, 'COM7');
      expect(pageBack(controller), isNull);
    });

    test('reconnecting restores the device history', () async {
      final history = store();
      await history.save('COM3', ['a', 'b', 'c']);

      final controller = make(bucket: 'COM7', store: history);

      await controller.useDeviceBucket('COM3');

      expect(pageBack(controller), 'c');
    });

    test('switching away writes the device history out first', () async {
      final history = store();
      final controller = make(bucket: 'COM3', store: history);

      controller.text.text = 'repl.enter()';
      controller.takeSubmission();
      await controller.useDeviceBucket('COM7');

      expect(await history.load('COM3'), ['repl.enter()']);
    });

    test('the in-progress line survives a device switch', () async {
      final controller = make();

      controller.text.text = 'half typed';
      await controller.useDeviceBucket('COM3');

      // Rebucketing is a storage concern; the console's own draft is not.
      expect(controller.text.text, 'half typed');
    });

    test('switching to the same bucket is a no-op', () async {
      final controller = make(bucket: 'COM3');

      controller.text.text = 'kept';
      await controller.useDeviceBucket('COM3');

      expect(controller.text.text, 'kept');
    });
  });
}
