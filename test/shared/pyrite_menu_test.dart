import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/constants/corner_radius.dart';
import 'package:pyrite_ide/shared/pyrite_menu.dart';

void main() {
  /// Pumps a selectable text that opens a [showPyriteMenu] popup on right
  /// click, mirroring how the REPL transcript drives its menu.
  Future<({FocusNode focus, List<String?> selections})> pumpMenuHost(
    WidgetTester tester,
  ) async {
    final focus = FocusNode(debugLabel: 'test-selectable');
    final selections = <String?>[];
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: const <ThemeExtension<dynamic>>[
            AppCornerRadii.comfortable,
          ],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => SelectionArea(
              focusNode: focus,
              onSelectionChanged: (content) =>
                  selections.add(content?.plainText),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onSecondaryTapUp: (details) => showPyriteMenu<String>(
                  context,
                  globalPosition: details.globalPosition,
                  entries: const [
                    PyriteMenuEntry(value: 'copy', label: 'Copy'),
                    PyriteMenuEntry(
                      value: 'clear',
                      label: 'Clear',
                      enabled: false,
                    ),
                  ],
                ),
                child: const Text('hello world'),
              ),
            ),
          ),
        ),
      ),
    );
    return (focus: focus, selections: selections);
  }

  Future<void> selectAll(WidgetTester tester, FocusNode focus) async {
    focus.requestFocus();
    await tester.pump();
    tester
        .state<SelectionAreaState>(find.byType(SelectionArea))
        .selectableRegion
        .selectAll();
    await tester.pump();
  }

  Future<void> rightClick(WidgetTester tester) async {
    await tester.tap(
      find.text('hello world'),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
  }

  testWidgets('right click keeps the selection and the focus behind it', (
    tester,
  ) async {
    final host = await pumpMenuHost(tester);
    await selectAll(tester, host.focus);
    expect(host.selections.last, 'hello world');

    await rightClick(tester);

    expect(find.text('Copy'), findsOneWidget);
    // The whole point of the custom route: a route that requested focus would
    // make the SelectableRegion drop its selection before the menu even paints.
    // Focus is what to assert — `SelectableRegion.clearSelection()` repaints
    // without the highlight but does not fire `onSelectionChanged`, so the
    // selected text alone would not reveal the bug.
    expect(host.focus.hasFocus, isTrue);
    expect(
      host.selections.last,
      'hello world',
      reason: 'opening the menu must not clear the selection it acts on',
    );
  });

  testWidgets('the menu uses the app-wide outer corner radius', (tester) async {
    final host = await pumpMenuHost(tester);
    await selectAll(tester, host.focus);
    await rightClick(tester);

    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(PyriteMenuSurface),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.borderRadius, AppCornerRadii.comfortable.outerRadius);
  });

  testWidgets('escape dismisses the menu without picking a row', (
    tester,
  ) async {
    final host = await pumpMenuHost(tester);
    await selectAll(tester, host.focus);
    await rightClick(tester);
    expect(find.text('Copy'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a disabled row cannot be picked', (tester) async {
    final host = await pumpMenuHost(tester);
    await selectAll(tester, host.focus);
    await rightClick(tester);

    await tester.tap(find.text('Clear'));
    await tester.pump();

    expect(
      find.text('Clear'),
      findsOneWidget,
      reason: 'a disabled row leaves the menu open',
    );
  });
}
