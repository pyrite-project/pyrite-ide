import 'package:flutter/material.dart';
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
        of: find.byType(SelectionArea),
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
}

Future<void> _pumpSurface(
  WidgetTester tester, {
  double width = 500,
  double height = 300,
  Color backgroundColor = const Color(0xFF101010),
  Color foregroundColor = Colors.white,
  bool looseConstraints = false,
  ProviderContainer? container,
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
