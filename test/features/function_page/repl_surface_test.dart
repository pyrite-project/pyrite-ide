import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/repl_input_controller.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/features/function_page/repl_surface.dart';

void main() {
  setUp(() {
    repl.onOutput = null;
    replInputSink = null;
    replOutputSink = null;
    replClearSink = null;
    replRunStartedSink = null;
    replRunFinishedSink = null;
  });

  testWidgets('shows one inline editor only at a friendly prompt', (
    tester,
  ) async {
    await _pumpSurface(tester);

    expect(find.byType(EditableText), findsNothing);

    writeReplOutput('MicroPython\r\n>>> ');
    await tester.pump();
    await tester.pump();

    expect(find.byType(EditableText), findsOneWidget);
    expect(find.textContaining('MicroPython'), findsOneWidget);
    expect(find.text('>>> '), findsOneWidget);
  });

  testWidgets('starts short REPL documents at the top of the viewport', (
    tester,
  ) async {
    await _pumpSurface(tester, height: 300);
    writeReplOutput('>>> ');
    await tester.pump();
    await tester.pump();

    final surfaceRect = tester.getRect(find.byType(ReplSurface));
    final editorRect = tester.getRect(find.byType(EditableText));
    expect(editorRect.top, lessThan(surfaceRect.top + 24));
  });

  testWidgets('background fills the entire REPL panel when empty', (
    tester,
  ) async {
    const background = Color(0xFF102030);
    await _pumpSurface(
      tester,
      backgroundColor: background,
      looseConstraints: true,
    );

    final surfaceRect = tester.getRect(find.byType(ReplSurface));
    final backgroundFinder = find.byKey(const ValueKey('repl-background'));
    final backgroundRect = tester.getRect(backgroundFinder);
    final backgroundWidget = tester.widget<Container>(backgroundFinder);

    expect(backgroundRect, surfaceRect);
    expect(backgroundRect.size, const Size(500, 300));
    expect(backgroundWidget.color, background);
  });

  testWidgets('uses the supplied REPL background and foreground colors', (
    tester,
  ) async {
    const background = Color(0xFF102030);
    const foreground = Color(0xFFE1E2E3);
    await _pumpSurface(
      tester,
      backgroundColor: background,
      foregroundColor: foreground,
    );

    writeReplOutput('boot\r\n>>> ');
    await tester.pump();
    await tester.pump();

    final coloredContainers = tester.widgetList<Container>(
      find.descendant(
        of: find.byType(ReplSurface),
        matching: find.byType(Container),
      ),
    );
    expect(
      coloredContainers.any((widget) => widget.color == background),
      isTrue,
    );

    final editor = tester.widget<EditableText>(find.byType(EditableText));
    expect(editor.style.color, foreground);

    final transcript = tester.widget<Text>(
      find.descendant(
        of: find.byType(ReplSurface),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textSpan?.toPlainText().contains('boot') == true,
        ),
      ),
    );
    expect(
      transcript.textSpan?.style?.color,
      foreground.withValues(alpha: .78),
    );
  });

  testWidgets('clicking the panel restores focus to the active REPL input', (
    tester,
  ) async {
    await _pumpSurface(tester, height: 300);
    writeReplOutput('boot\r\n>>> ');
    await tester.pump();
    await tester.pump();

    final editor = find.byType(EditableText);
    expect(editor, findsOneWidget);
    final focusNode = tester.widget<EditableText>(editor).focusNode;
    focusNode.unfocus();
    await tester.pump();

    await tester.tap(find.textContaining('boot'));
    await tester.pump();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus, same(focusNode));
  });

  testWidgets('restoring focus does not scroll the panel to the input', (
    tester,
  ) async {
    await _pumpSurface(tester, height: 120);
    writeReplOutput(
      '${List.generate(40, (index) => 'line $index\r\n').join()}>>> ',
    );
    await tester.pump();
    await tester.pump();

    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent / 2);
    final before = scroll.offset;
    final focusNode = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    focusNode.unfocus();
    await tester.pump();

    await tester.tap(find.textContaining('line 20'));
    await tester.pump();
    await tester.pump();

    expect(scroll.offset, closeTo(before, 1));
  });

  testWidgets(
    'scrollbar thumb can be dragged',
    (tester) async {
      await _pumpSurface(tester, height: 200);
      // The prompt is what leaves the inline input on screen, and it is what the
      // panel focuses when the transcript is clicked.
      writeReplOutput(
        '${List.generate(60, (index) => 'line $index\r\n').join()}>>> ',
      );
      await tester.pump();
      await tester.pump();

      final scroll = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent / 2);
      await tester.pump();
      // The thumb only accepts pointer events once the fade-in has run.
      await tester.pump(const Duration(milliseconds: 400));
      final before = scroll.offset;

      final gesture = await tester.startGesture(
        _thumbCenter(tester, scroll),
        kind: PointerDeviceKind.mouse,
      );
      // A real press is followed by a frame in which the panel focuses its input.
      await tester.pump();
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(scroll.offset, greaterThan(before));

      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(scroll.offset, closeTo(before, 1));
      await gesture.up();
    },
    // The scrollbar only accepts thumb drags on desktop platforms.
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('filters ANSI-wrapped prompts without duplicating the gutter', (
    tester,
  ) async {
    await _pumpSurface(tester);

    writeReplOutput('\x1b[32m>>> \x1b[0m');
    await tester.pump();
    await tester.pump();

    expect(find.byType(EditableText), findsOneWidget);
    expect(find.text('>>> '), findsOneWidget);
  });

  testWidgets('keeps submitted text in IDE state until Enter', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSurface(tester, container: container);
    writeReplOutput('>>> ');
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'print(1)');
    final input = container.read(replInputControllerProvider);
    expect(input.text.text, 'print(1)');
    expect(input.mode, ReplInteractionMode.prompt);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(input.text.text, isEmpty);
    expect(input.mode, ReplInteractionMode.passthrough);
    expect(
      container.read(replTranscriptControllerProvider).text,
      '>>> print(1)\n',
    );

    writeReplOutput('print(1)\r\n1\r\n>>> ');
    await tester.pump();
    await tester.pump();

    expect(
      container.read(replTranscriptControllerProvider).text,
      '>>> print(1)\n1\n',
    );
    expect(input.mode, ReplInteractionMode.prompt);
  });

  testWidgets(
    'shows and focuses passthrough input while a program is running',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _pumpSurface(tester, container: container);
      writeReplOutput('>>> ');
      await tester.pump();
      await tester.pump();

      final editor = find.byType(EditableText);
      await tester.enterText(editor, 'input("Name: ")');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      writeReplOutput('Name: ');
      await tester.pump();
      await tester.pump();

      expect(
        container.read(replInputControllerProvider).mode,
        ReplInteractionMode.passthrough,
      );
      expect(tester.getSize(editor).width, greaterThan(100));

      await tester.enterText(editor, 'abc');
      final input = container.read(replInputControllerProvider);
      expect(input.text.text, 'abc');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(input.text.selection.extentOffset, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(input.text.text, 'ac');

      final focusNode = tester.widget<EditableText>(editor).focusNode;
      focusNode.unfocus();
      await tester.pump();
      await tester.tap(find.textContaining('Name:'));
      await tester.pump();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, same(focusNode));
    },
  );

  testWidgets('Tab opens static completion and Enter accepts it', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSurface(tester, container: container);
    writeReplOutput('>>> ');
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'pri');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();

    expect(find.text('print'), findsOneWidget);
    expect(find.text('MicroPython builtin'), findsWidgets);
    // Keep the popup bounded even though the root Overlay is full-screen.
    final popupSize = tester.getSize(
      find.byKey(const ValueKey('repl-completion-popup')),
    );
    expect(popupSize.width, lessThanOrEqualTo(360));
    expect(popupSize.height, lessThanOrEqualTo(240));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(container.read(replInputControllerProvider).text.text, 'print');
    expect(find.text('MicroPython builtin'), findsNothing);
  });

  testWidgets('accepting right after typing replaces the whole token', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSurface(tester, container: container);
    writeReplOutput('>>> ');
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'pri');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('repl-completion-popup')), findsOneWidget);

    // The popup still lists items for "pri" while the next character is
    // typed; accepting it must not leave that character behind.
    await tester.enterText(find.byType(EditableText), 'prin');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(container.read(replInputControllerProvider).text.text, 'print');
  });

  testWidgets('moving the caret dismisses the completion popup', (
    tester,
  ) async {
    await _pumpSurface(tester);
    writeReplOutput('>>> ');
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'pri');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('repl-completion-popup')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('repl-completion-popup')), findsNothing);
  });

  testWidgets('completion navigation takes precedence over REPL history', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSurface(tester, container: container);
    writeReplOutput('>>> ');
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'pr');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(container.read(replInputControllerProvider).text.text, 'property');
  });

  testWidgets('clicking outside dismisses the completion popup', (
    tester,
  ) async {
    await _pumpSurface(tester);
    writeReplOutput('boot\r\n>>> ');
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'pri');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('repl-completion-popup')), findsOneWidget);

    await tester.tap(find.textContaining('boot'));
    await tester.pump();

    expect(find.byKey(const ValueKey('repl-completion-popup')), findsNothing);
  });

  testWidgets('shows and dismisses a function signature without losing focus', (
    tester,
  ) async {
    await _pumpSurface(tester);
    writeReplOutput('>>> ');
    await tester.pump();
    await tester.pump();

    final editor = find.byType(EditableText);
    await tester.enterText(editor, 'print');
    await tester.enterText(editor, 'print(');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.textContaining('print(*objects'), findsOneWidget);
    final popupSize = tester.getSize(
      find.byKey(const ValueKey('repl-signature-popup')),
    );
    expect(popupSize.width, lessThanOrEqualTo(480));
    expect(popupSize.height, lessThanOrEqualTo(64));
    final focusNode = tester.widget<EditableText>(editor).focusNode;
    expect(FocusManager.instance.primaryFocus, same(focusNode));

    await tester.enterText(editor, 'print()');
    await tester.pump();
    expect(find.textContaining('print(*objects'), findsNothing);
  });

  testWidgets('routes internal REPL output into the transcript', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSurface(tester, container: container);

    writeReplOutput('internal run output\r\n');
    await tester.pump();

    expect(
      container.read(replTranscriptControllerProvider).text,
      'internal run output\n',
    );
  });

  testWidgets('separates consecutive internal runs with a REPL prompt', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSurface(tester, container: container);
    writeReplOutput('>>> ');
    await tester.pump();
    await tester.pump();

    beginReplRunOutput();
    writeReplOutput('first failure');
    finishReplRunOutput();
    await tester.pump();

    expect(
      container.read(replTranscriptControllerProvider).text,
      '>>> \nfirst failure\n',
    );

    beginReplRunOutput();
    await tester.pump();
    expect(
      container.read(replTranscriptControllerProvider).text,
      '>>> \nfirst failure\n>>> \n',
    );
  });

  testWidgets(
    'ignores repeated Enter events instead of inserting extra lines',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _pumpSurface(tester, container: container);
      writeReplOutput('>>> ');
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(EditableText), 'if ready:');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      final input = container.read(replInputControllerProvider);
      expect(input.text.text, 'if ready:\n    ');
      expect(input.mode, ReplInteractionMode.prompt);
    },
  );

  testWidgets(
    'keeps Chinese source in the transcript when device echo is encoded',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _pumpSurface(tester, container: container);
      writeReplOutput('>>> ');
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(EditableText), 'print("你好")');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      writeReplOutput(
        r'print("\u4f60\u597d")'
        '\r\n1\r\n>>> ',
      );
      await tester.pump();
      await tester.pump();

      final transcript = container.read(replTranscriptControllerProvider).text;
      expect(transcript, '>>> print("你好")\n1\n');
      expect(transcript, isNot(contains(r'\u4f60')));
    },
  );

  testWidgets('reports a traceback frame whose file cannot be located', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSurface(tester, container: container);
    writeReplOutput('>>> ');
    await tester.pump();
    await tester.pump();

    writeReplOutput(
      'Traceback (most recent call last):\r\n'
      '  File "<stdin>", line 4, in <module>\r\n'
      '  File "definitely_missing_9f2a.py", line 2, in c\r\n'
      "NameError: name 'ErrorHere' isn't defined\r\n",
    );
    await tester.pump();
    await tester.pump();

    // <stdin> is never a jump target, so the one real frame is the only link.
    final transcript = container.read(replTranscriptControllerProvider).text;
    final frameStart = transcript.indexOf('definitely_missing_9f2a.py');
    final frameEnd = transcript.indexOf(', line 2', frameStart);

    // The whole transcript is one paragraph, so its centre is not on the
    // frame's line; tap the laid-out box of the frame span instead.
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: frameStart, extentOffset: frameEnd),
    );
    expect(boxes, isNotEmpty, reason: 'frame should occupy a laid-out box');

    final origin = tester.getTopLeft(find.byType(ReplSurface));
    await tester.tapAt(origin + boxes.first.toRect().center);
    await tester.pump();
    await tester.pump();

    // The frame was styled like a link, so a silent no-op read as a dead
    // console rather than a file that is not on this machine.
    expect(
      container.read(replTranscriptControllerProvider).text,
      contains('cannot locate definitely_missing_9f2a.py'),
    );
  });

  testWidgets('hovering a traceback frame shows the click cursor', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSurface(tester, container: container);
    writeReplOutput('>>> ');
    await tester.pump();
    await tester.pump();

    writeReplOutput(
      'Traceback (most recent call last):\r\n'
      '  File "hovered_frame.py", line 7, in c\r\n'
      "NameError: name 'x' isn't defined\r\n",
    );
    await tester.pump();
    await tester.pump();

    final transcript = container.read(replTranscriptControllerProvider).text;
    final frameStart = transcript.indexOf('File "hovered_frame.py"');
    final frameEnd = transcript.indexOf(', line 7', frameStart);
    final errorStart = transcript.indexOf('NameError');

    // The transcript is one paragraph, so aim through its laid-out boxes: the
    // boxes are in the paragraph's coordinates and the RichText's origin turns
    // them back into global ones.
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final origin = tester.getTopLeft(find.byType(RichText).first);
    Rect boxFor(int start, int end) => paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        )
        .first
        .toRect();
    final framePoint = origin + boxFor(frameStart, frameEnd).center;
    final errorPoint = origin + boxFor(errorStart, errorStart + 9).center;

    MouseCursor cursor() => tester
        .widget<MouseRegion>(
          find.byKey(const ValueKey('repl-transcript-region')),
        )
        .cursor;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: errorPoint);
    await tester.pump();
    expect(cursor(), SystemMouseCursors.text);

    await gesture.moveTo(framePoint);
    await tester.pump();
    expect(cursor(), SystemMouseCursors.click);

    await gesture.moveTo(errorPoint);
    await tester.pump();
    expect(cursor(), SystemMouseCursors.text);
  });

  testWidgets('keeps multiline input and transcript in one scroll document', (
    tester,
  ) async {
    await _pumpSurface(tester, height: 120);
    writeReplOutput('${List.generate(20, (i) => '$i\r\n').join()}>>> ');
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.byType(EditableText),
      'for i in range(5):\n    print(i)\n    ',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final surfaceRect = tester.getRect(find.byType(ReplSurface));
    final editorRect = tester.getRect(find.byType(EditableText));
    expect(editorRect.bottom, lessThanOrEqualTo(surfaceRect.bottom + 1));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('submits an empty prompt instead of starting multiline input', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSurface(tester, container: container);
    writeReplOutput('>>> ');
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    final input = container.read(replInputControllerProvider);
    expect(input.text.text, isEmpty);
    expect(input.mode, ReplInteractionMode.passthrough);
    expect(container.read(replTranscriptControllerProvider).text, '>>> ');
  });

  testWidgets('keeps the current prompt after Ctrl-C', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSurface(tester, container: container);
    writeReplOutput('>>> ');
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(container.read(replTranscriptControllerProvider).text, '>>> ');
    expect(
      container.read(replInputControllerProvider).mode,
      ReplInteractionMode.passthrough,
    );
  });

  testWidgets('restores the transport output callback when disposed', (
    tester,
  ) async {
    void previousOutput(String _) {}
    void previousClear() {}

    repl.onOutput = previousOutput;
    replClearSink = previousClear;
    await _pumpSurface(tester);
    await tester.pumpWidget(const SizedBox.shrink());

    expect(repl.onOutput, same(previousOutput));
    expect(replClearSink, same(previousClear));
  });

  testWidgets('right-click offers the terminal menu on the transcript', (
    tester,
  ) async {
    await _pumpSurface(tester);
    writeReplOutput('boot output\r\n>>> ');
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.textContaining('boot output'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('粘贴'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('清屏'), findsOneWidget);
    expect(find.text('搜索'), findsNothing);

    await tester.tap(find.text('清屏'));
    await tester.pumpAndSettle();

    expect(find.textContaining('boot output'), findsNothing);
  });

  testWidgets('select all and copy from the menu fill the clipboard', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = call.arguments['text'] as String?;
        } else if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboard};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await _pumpSurface(tester);
    writeReplOutput('boot output\r\n>>> ');
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.textContaining('boot output'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.textContaining('boot output'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    // The device-echoed prompt is filtered out of the transcript; the gutter
    // renders it, so the selectable text ends after 'boot output'.
    expect(clipboard, 'boot output\n');
  });

  testWidgets('paste from the menu inserts into the local input', (
    tester,
  ) async {
    String? clipboard = 'print(42)';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = call.arguments['text'] as String?;
        } else if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboard};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSurface(tester, container: container);
    writeReplOutput('ready\r\n>>> ');
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.textContaining('ready'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('粘贴'));
    await tester.pumpAndSettle();

    expect(container.read(replInputControllerProvider).text.text, 'print(42)');
  });

  testWidgets('the REPL menu is the only popup on right-click', (tester) async {
    await _pumpSurface(tester);
    writeReplOutput('menu probe\r\n>>> ');
    await tester.pump();
    await tester.pump();

    // The transcript paints its own selection, so no platform text toolbar can
    // stack on top of the REPL menu the way `SelectionArea` used to.
    await tester.tap(
      find.textContaining('menu probe'),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
  });

  testWidgets('a click leaves the transcript scrollable', (tester) async {
    await _pumpSurface(tester);
    final buffer = StringBuffer();
    for (var i = 0; i < 120; i++) {
      buffer.write('line $i of the transcript\r\n');
    }
    buffer.write('>>> ');
    writeReplOutput(buffer.toString());
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(0);
    await tester.pumpAndSettle();

    // Clicking the transcript hands focus back to the input, and the offset it
    // holds while doing that has to be released: a stuck anchor snaps every
    // later scroll back, which reads as the transcript being pinned.
    await tester.tapAt(const Offset(60, 50));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 150),
        scrollDelta: Offset(0, 200),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(position.pixels, greaterThan(0));
  });

  testWidgets('dragging to the left edge keeps the pointer line', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = call.arguments['text'] as String?;
        } else if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboard};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await _pumpSurface(tester);
    final buffer = StringBuffer();
    for (var i = 0; i < 120; i++) {
      buffer.write('line $i of the transcript\r\n');
    }
    buffer.write('>>> ');
    writeReplOutput(buffer.toString());
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(1000);
    await tester.pumpAndSettle();

    // Drag up and into the panel's left edge. The transcript paints its own
    // selection, so a point left of the text maps to the start of the line under
    // the pointer instead of the top-left corner of the whole paragraph.
    final gesture = await tester.startGesture(
      const Offset(60, 200),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveTo(
        Offset(60 + (4 - 60) * (i + 1) / 10, 200 + (50 - 200) * (i + 1) / 10),
      );
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tapAt(
      const Offset(60, 250),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    final lines = (clipboard ?? '').split('\n');
    expect(lines, isNotEmpty);
    expect(lines.first, isNot(contains('line 0 ')));
    expect(lines.length, lessThan(40));
  });

  testWidgets('a drag above the panel stops at the top visible line', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = call.arguments['text'] as String?;
        } else if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboard};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await _pumpSurface(tester);
    final buffer = StringBuffer();
    for (var i = 0; i < 120; i++) {
      buffer.write('line $i of the transcript\r\n');
    }
    buffer.write('>>> ');
    writeReplOutput(buffer.toString());
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    // 1005 leaves the top line half visible: the state the old selection code
    // turned into "select from the first line" whenever the drag left the panel.
    position.jumpTo(1005);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      const Offset(60, 200),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveTo(Offset(60, 200 + (-60 - 200) * (i + 1) / 10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tapAt(
      const Offset(60, 250),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    final lines = (clipboard ?? '').split('\n');
    expect(lines, isNotEmpty);
    // The selection must stop at what is on screen: the first line it covers is
    // one of the lines around the scroll offset, never the document's first.
    final index = RegExp(
      r'(\d+) of the transcript',
    ).firstMatch(lines.first)?.group(1);
    expect(index, isNotNull);
    expect(int.parse(index!), greaterThan(40));
    expect(lines.length, lessThan(40));
  });

  testWidgets('double-click selects the word under the pointer', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = call.arguments['text'] as String?;
        } else if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboard};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await _pumpSurface(tester);
    writeReplOutput('alpha beta\r\n>>> ');
    await tester.pump();
    await tester.pump();

    final line = find.textContaining('alpha beta');
    // The test font is fixed-width, so the sixth character starts one fontSize
    // in: land on "beta" rather than on the space before it.
    final target = tester.getTopLeft(line) + const Offset(6 * 14 + 4, 8);
    await tester.tapAt(target, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(target, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getTopLeft(line) + const Offset(4, 8),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    expect(clipboard, 'beta');
  });

  testWidgets('dragging the scrollbar thumb scrolls the transcript', (
    tester,
  ) async {
    await _pumpSurface(tester, theme: _desktopScrollbarTheme);

    final buffer = StringBuffer();
    for (var i = 0; i < 30; i++) {
      buffer.write('line $i of the transcript\r\n');
    }
    buffer.write('>>> ');
    writeReplOutput(buffer.toString());
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    // A prompt is on screen, so a press also runs the "take focus and hold the
    // offset" path; that path used to revert every scroll the thumb produced.
    position.jumpTo(0);
    await tester.pumpAndSettle();

    const pressPoint = Offset(495, 20);
    final gesture = await tester.startGesture(
      pressPoint,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveTo(pressPoint + Offset(0, 6.0 * (i + 1)));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
  });
}

/// Centre of the scrollbar thumb, which the framework paints flush against
/// the right edge and sizes from how much of the transcript is on screen.
Offset _thumbCenter(WidgetTester tester, ScrollController scroll) {
  final surface = tester.getRect(find.byType(ReplSurface));
  final metrics = scroll.position;
  const thickness = 8.0;
  const minThumbExtent = 18.0;
  final visible =
      metrics.viewportDimension /
      (metrics.viewportDimension + metrics.maxScrollExtent);
  final thumbExtent = math.max(minThumbExtent, surface.height * visible);
  final travelled = surface.height - thumbExtent;
  final top =
      surface.top + (metrics.pixels / metrics.maxScrollExtent) * travelled;
  return Offset(surface.right - thickness / 2, top + thumbExtent / 2);
}

/// A desktop theme whose scrollbar can be grabbed without hovering first.
///
/// `flutter test` defaults to the Android platform, where the Material
/// scrollbar is an indicator only and installs no drag recognizers at all.
final ThemeData _desktopScrollbarTheme = ThemeData(
  platform: TargetPlatform.macOS,
  scrollbarTheme: const ScrollbarThemeData(
    thumbVisibility: WidgetStatePropertyAll(true),
  ),
);

Future<void> _pumpSurface(
  WidgetTester tester, {
  double width = 500,
  double height = 300,
  Color backgroundColor = const Color(0xFF101010),
  Color foregroundColor = Colors.white,
  bool looseConstraints = false,
  ProviderContainer? container,
  ThemeData? theme,
}) async {
  final surface = ReplSurface(
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    textStyle: const TextStyle(
      color: Colors.white,
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1,
    ),
  );
  final sized = MaterialApp(
    theme: theme,
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: looseConstraints
            ? Align(alignment: Alignment.topLeft, child: surface)
            : surface,
      ),
    ),
  );
  final scope = container == null
      ? ProviderScope(child: sized)
      : UncontrolledProviderScope(container: container, child: sized);
  await tester.pumpWidget(scope);
}
