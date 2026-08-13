import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/shared/tabbed_view/tabbed_view.dart';
import 'package:tabbed_view/tabbed_view.dart' as tabbed;

void main() {
  testWidgets('kept-alive content is not mounted with a global key', (
    tester,
  ) async {
    final sharedTab = tabbed.TabData(
      text: 'shared',
      keepAlive: true,
      content: const Text('shared content'),
    );
    final sourceController = tabbed.TabbedViewController([sharedTab]);
    final targetController = tabbed.TabbedViewController([sharedTab]);
    addTearDown(sourceController.dispose);
    addTearDown(targetController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Expanded(child: TabbedView(controller: sourceController)),
            Expanded(child: TabbedView(controller: targetController)),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('shared content'), findsNWidgets(2));
  });
}
