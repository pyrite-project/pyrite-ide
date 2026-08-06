import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/services/editor/repl_input_controller.dart';

void main() {
  group('ReplInputController', () {
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
}
