import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/shared/tabbed_view/tabbed_view.dart';
import 'package:tabbed_view/tabbed_view.dart' as tabbed;

void main() {
  testWidgets('tab area keeps overflow tabs visible in a horizontal scroller', (
    tester,
  ) async {
    final controller = tabbed.TabbedViewController(
      List.generate(
        12,
        (index) => tabbed.TabData(
          text: 'tab-$index-long-title',
          textSize: 120,
          content: index == 0
              ? const ColoredBox(
                  key: Key('editor-content'),
                  color: Colors.white,
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 360,
          height: 220,
          child: TabbedView(controller: controller),
        ),
      ),
    );

    for (int index = 0; index < controller.tabs.length; index++) {
      expect(find.text('tab-$index-long-title'), findsOneWidget);
    }

    final scrollable = tester.widget<Scrollable>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.right,
          )
          .first,
    );
    expect(scrollable.controller!.offset, 0);
    expect(
      tester.getSize(find.byType(SingleChildScrollView).first).height,
      lessThan(80),
    );
    expect(
      tester.getSize(find.byKey(const Key('editor-content'))).height,
      greaterThan(100),
    );

    final Offset center = tester.getCenter(find.text('tab-0-long-title'));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 80)),
    );
    await tester.pump();

    expect(scrollable.controller!.offset, greaterThan(0));
  });
}
