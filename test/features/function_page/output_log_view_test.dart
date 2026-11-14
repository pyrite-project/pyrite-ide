import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/features/function_page.dart';
import 'package:pyrite_ide/shared/pyrite_menu.dart';
import 'package:xterm/xterm.dart';

void main() {
  setUp(() {
    ideOutputTerminal.clear();
    ideOutputController.clearSelection();
  });

  /// The clipboard backing the platform channel, for tests that copy.
  void mockClipboard(WidgetTester tester, {void Function(String?)? onSet}) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          onSet?.call(call.arguments['text'] as String?);
        } else if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': null};
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
  }

  Future<void> pumpLogView(
    WidgetTester tester, {
    ProviderContainer? container,
  }) async {
    final view = SizedBox(
      width: 400,
      height: 300,
      child: const OutputLogView(),
    );
    final app = MaterialApp(home: Scaffold(body: view));
    await tester.pumpWidget(
      container == null
          ? ProviderScope(child: app)
          : UncontrolledProviderScope(container: container, child: app),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('right-click offers copy, select all and clear but no paste or '
      'search', (tester) async {
    ideOutputTerminal.write('hello log\r\n');
    await pumpLogView(tester);

    await tester.tap(find.byType(TerminalView), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('清屏'), findsOneWidget);
    expect(find.text('粘贴'), findsNothing);
    expect(find.text('搜索'), findsNothing);

    // Nothing is selected yet, so copy is greyed out rather than hidden.
    final copyRow = tester.widget<PyriteMenuRow>(
      find.widgetWithText(PyriteMenuRow, '复制'),
    );
    expect(copyRow.enabled, isFalse);
  });

  testWidgets('select all from the menu selects the whole buffer', (
    tester,
  ) async {
    ideOutputTerminal.write('hello log\r\n');
    await pumpLogView(tester);

    await tester.tap(find.byType(TerminalView), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    final selection = ideOutputController.selection;
    expect(selection, isNotNull);
    expect(ideOutputTerminal.buffer.getText(selection!), contains('hello log'));
  });

  testWidgets('copy from the menu puts the selected log on the clipboard', (
    tester,
  ) async {
    String? copied;
    mockClipboard(tester, onSet: (text) => copied = text);
    ideOutputTerminal.write('hello log\r\n');
    await pumpLogView(tester);

    await tester.tap(find.byType(TerminalView), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TerminalView), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    expect(copied, contains('hello log'));
  });

  testWidgets('clear from the menu empties the buffer and the entry list', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpLogView(tester, container: container);
    container
        .read(ideOutputLogProvider.notifier)
        .add(IdeOutputSource.ide, 'hello log');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TerminalView), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('清屏'));
    await tester.pumpAndSettle();

    expect(container.read(ideOutputLogProvider), isEmpty);
    expect(ideOutputController.selection, isNull);
  });

  /// The viewport's scroll position, the one the log's own scrolling uses.
  ScrollPosition logScrollPosition(WidgetTester tester) {
    final scrollable = find.descendant(
      of: find.byType(TerminalView),
      matching: find.byType(Scrollable),
    );
    return tester.state<ScrollableState>(scrollable.first).position;
  }

  /// The text of the line drawn at the top of the viewport.
  String topVisibleLine(WidgetTester tester) {
    final render = tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .renderTerminal;
    final cell = render.getCellOffset(const Offset(2, 2));
    return ideOutputTerminal.buffer.lines[cell.y].toString().trim();
  }

  testWidgets('a reader scrolled up keeps their lines while the log grows', (
    tester,
  ) async {
    await pumpLogView(tester);
    // Fill the scrollback so that every further line drops the oldest one: a
    // full buffer is what used to slide the text under a fixed viewport.
    for (var i = 0; i < ideOutputTerminal.maxLines + 100; i++) {
      ideOutputTerminal.write('line $i\r\n');
    }
    await tester.pumpAndSettle();

    final position = logScrollPosition(tester);
    final lineHeight = tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .renderTerminal
        .lineHeight;
    position.jumpTo(position.maxScrollExtent - 40 * lineHeight);
    await tester.pumpAndSettle();

    final before = topVisibleLine(tester);
    for (var i = 0; i < 20; i++) {
      ideOutputTerminal.write('new $i\r\n');
    }
    await tester.pumpAndSettle();

    expect(topVisibleLine(tester), before);
  });

  testWidgets('a reader at the bottom follows the new output', (tester) async {
    await pumpLogView(tester);
    for (var i = 0; i < ideOutputTerminal.maxLines + 100; i++) {
      ideOutputTerminal.write('line $i\r\n');
    }
    await tester.pumpAndSettle();

    final position = logScrollPosition(tester);
    ideOutputTerminal.write('the newest line\r\n');
    await tester.pumpAndSettle();

    expect(position.pixels, position.maxScrollExtent);
    final lines = ideOutputTerminal.buffer.lines;
    final render = tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .renderTerminal;
    final bottomCell = render.getCellOffset(Offset(2, render.size.height - 4));
    // The entry ends with a line break, so the blank line the cursor sits on is
    // the last one and the text is the row above it.
    expect(lines[bottomCell.y].toString().trim(), isEmpty);
    expect(lines[bottomCell.y - 1].toString().trim(), 'the newest line');
  });

  testWidgets('a selection stays on its text while the log grows', (
    tester,
  ) async {
    await pumpLogView(tester);
    for (var i = 0; i < ideOutputTerminal.maxLines + 100; i++) {
      ideOutputTerminal.write('line $i\r\n');
    }
    await tester.pumpAndSettle();

    final position = logScrollPosition(tester);
    final lineHeight = tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .renderTerminal
        .lineHeight;
    position.jumpTo(position.maxScrollExtent - 30 * lineHeight);
    await tester.pumpAndSettle();

    final render = tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .renderTerminal;
    final top = render.getCellOffset(const Offset(2, 2));
    ideOutputController.setSelection(
      ideOutputTerminal.buffer.createAnchorFromOffset(CellOffset(0, top.y)),
      ideOutputTerminal.buffer.createAnchorFromOffset(
        CellOffset(12, top.y + 3),
      ),
    );
    await tester.pumpAndSettle();
    final before = ideOutputTerminal.buffer.getText(
      ideOutputController.selection!,
    );

    for (var i = 0; i < 20; i++) {
      ideOutputTerminal.write('new $i\r\n');
    }
    await tester.pumpAndSettle();

    expect(
      ideOutputTerminal.buffer.getText(ideOutputController.selection!),
      before,
    );
  });
}
