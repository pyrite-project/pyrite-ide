import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';
import 'package:pyrite_ide/features/terminal/desktop_terminal_surface.dart';
import 'package:pyrite_ide/features/terminal/terminal_search_bar.dart';
import 'package:xterm/xterm.dart';

void main() {
  late Terminal terminal;
  late TerminalController controller;

  setUp(() {
    terminal = Terminal()..resize(60, 12);
    controller = TerminalController();
  });

  Future<void> pumpSurface(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopTerminalSurface(
            terminal: terminal,
            controller: controller,
            theme: TerminalThemes.defaultTheme,
            textStyle: const TerminalStyle(fontSize: 12),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Focuses the terminal the same way a click would, so key events reach the
  /// view's focus node.
  Future<void> focusTerminal(WidgetTester tester) async {
    await tester.tap(find.byType(TerminalView));
    await tester.pumpAndSettle();
  }

  /// Presses the platform's find shortcut.
  ///
  /// Uses [findActivators] so the test exercises the same binding the app
  /// registers: Cmd+F on Apple hosts, Ctrl+F elsewhere.
  Future<void> pressFindShortcut(WidgetTester tester) async {
    final modifier = usesCommandShortcut
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl/Cmd+F opens the search bar', (tester) async {
    await pumpSurface(tester);
    await focusTerminal(tester);

    expect(find.byType(TerminalSearchBar), findsNothing);

    await pressFindShortcut(tester);

    expect(find.byType(TerminalSearchBar), findsOneWidget);
  });

  testWidgets('typing highlights matches and counts them from the buffer', (
    tester,
  ) async {
    terminal.write('alpha beta alpha\r\n');
    await pumpSurface(tester);
    await focusTerminal(tester);

    await pressFindShortcut(tester);

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pumpAndSettle();

    expect(find.text('第 1 / 共 2 个'), findsOneWidget);
    // Highlights come from the controller, which is what the renderer paints.
    expect(controller.highlights, hasLength(2));
  });

  testWidgets('Enter advances and Shift+Enter goes back', (tester) async {
    terminal.write('hit one hit\r\n');
    await pumpSurface(tester);
    await focusTerminal(tester);

    await pressFindShortcut(tester);

    await tester.enterText(find.byType(TextField), 'hit');
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 共 2 个'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 共 2 个'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 共 2 个'), findsOneWidget);
  });

  testWidgets('Escape closes the bar and clears the highlights', (
    tester,
  ) async {
    terminal.write('needle\r\n');
    await pumpSurface(tester);
    await focusTerminal(tester);

    await pressFindShortcut(tester);
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pumpAndSettle();
    expect(controller.highlights, isNotEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(TerminalSearchBar), findsNothing);
    expect(controller.highlights, isEmpty);
  });

  testWidgets('the close button dismisses the bar', (tester) async {
    await pumpSurface(tester);
    await focusTerminal(tester);

    await pressFindShortcut(tester);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(TerminalSearchBar), findsNothing);
  });

  testWidgets('a cleared query leaves no highlights behind', (tester) async {
    terminal.write('abc\r\n');
    await pumpSurface(tester);
    await focusTerminal(tester);

    await pressFindShortcut(tester);
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pumpAndSettle();
    expect(controller.highlights, isNotEmpty);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(controller.highlights, isEmpty);
  });
}
