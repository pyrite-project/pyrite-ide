import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/terminal/terminal_search.dart';
import 'package:pyrite_ide/features/terminal/terminal_search_bar.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required TerminalSearchState state,
    TextEditingController? controller,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    VoidCallback? onToggleCase,
    VoidCallback? onClose,
    ValueChanged<String>? onChanged,
  }) async {
    final textController = controller ?? TextEditingController();
    addTearDown(textController.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    // The bar reads its labels from the registry now, so it needs a scope.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: TerminalSearchBar(
                controller: textController,
                focusNode: focusNode,
                state: state,
                onChanged: onChanged ?? (_) {},
                onPrevious: onPrevious ?? () {},
                onNext: onNext ?? () {},
                onToggleCase: onToggleCase ?? () {},
                onClose: onClose ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the match counter', (tester) async {
    final state = const TerminalSearchState().withQuery(['ab ab', 'ab'], 'ab');

    await pumpBar(tester, state: state);

    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('shows "no results" when nothing matched', (tester) async {
    await pumpBar(
      tester,
      state: const TerminalSearchState().withQuery(['abc'], 'zzz'),
    );

    expect(find.text('无结果'), findsOneWidget);
  });

  testWidgets('shows no counter before a query is typed', (tester) async {
    await pumpBar(tester, state: const TerminalSearchState());

    expect(find.text('无结果'), findsNothing);
    expect(find.textContaining('共'), findsNothing);
  });

  testWidgets('the query field forwards edits', (tester) async {
    String? typed;
    await pumpBar(
      tester,
      state: const TerminalSearchState(),
      onChanged: (value) => typed = value,
    );

    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pump();

    expect(typed, 'needle');
  });

  testWidgets('previous and next are disabled without matches', (tester) async {
    await pumpBar(
      tester,
      state: const TerminalSearchState().withQuery(['abc'], 'zzz'),
    );

    final up = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.keyboard_arrow_up),
    );
    final down = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.keyboard_arrow_down),
    );

    expect(up.onPressed, isNull);
    expect(down.onPressed, isNull);
  });

  testWidgets('navigation and close buttons fire', (tester) async {
    var previous = 0;
    var next = 0;
    var closed = 0;
    await pumpBar(
      tester,
      state: const TerminalSearchState().withQuery(['ab'], 'ab'),
      onPrevious: () => previous++,
      onNext: () => next++,
      onClose: () => closed++,
    );

    await tester.tap(find.widgetWithIcon(IconButton, Icons.keyboard_arrow_up));
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.keyboard_arrow_down),
    );
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));

    expect(previous, 1);
    expect(next, 1);
    expect(closed, 1);
  });

  testWidgets('the case toggle reflects the active state', (tester) async {
    var toggles = 0;
    final state = const TerminalSearchState()
        .withQuery(['AB ab'], 'ab')
        .withCaseSensitive(['AB ab'], true);

    await pumpBar(tester, state: state, onToggleCase: () => toggles++);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.text_fields));

    expect(toggles, 1);
  });
}
