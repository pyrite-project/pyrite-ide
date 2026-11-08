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
}
