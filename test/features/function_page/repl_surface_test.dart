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
  ProviderContainer? container,
}) async {
  final sized = MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: const ReplSurface(
          backgroundColor: Color(0xFF101010),
          textStyle: TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 14,
            height: 1,
          ),
        ),
      ),
    ),
  );
  final scope = container == null
      ? ProviderScope(child: sized)
      : UncontrolledProviderScope(container: container, child: sized);
  await tester.pumpWidget(scope);
}
