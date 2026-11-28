import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';

void main() {
  Future<void> pumpHeader(
    WidgetTester tester, {
    required double width,
    required int actionCount,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: PaneHeader(
                  title: 'A project name long enough to need the room',
                  subtitle: '/home/user/projects/a-rather-long-project',
                  leadingIcon: Icons.folder_outlined,
                  compact: true,
                  actions: [
                    for (var index = 0; index < actionCount; index++)
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.circle_outlined),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a narrow pane moves the actions under the title', (
    tester,
  ) async {
    await pumpHeader(tester, width: 240, actionCount: 5);

    expect(tester.takeException(), isNull);
    final titleRect = tester.getRect(find.textContaining('A project name'));
    final actionRect = tester.getRect(find.byIcon(Icons.circle_outlined).first);
    expect(
      actionRect.top,
      greaterThanOrEqualTo(titleRect.bottom - 1),
      reason: 'the actions should occupy their own line',
    );
  });

  testWidgets('a wide pane keeps the actions beside the title', (tester) async {
    await pumpHeader(tester, width: 560, actionCount: 5);

    expect(tester.takeException(), isNull);
    final titleRect = tester.getRect(find.textContaining('A project name'));
    final actionRect = tester.getRect(find.byIcon(Icons.circle_outlined).first);
    expect(
      actionRect.left,
      greaterThan(titleRect.right - 1),
      reason: 'the actions should sit to the right of the title',
    );
  });

  testWidgets('a header without actions never stacks', (tester) async {
    await pumpHeader(tester, width: 180, actionCount: 0);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('A project name'), findsOneWidget);
  });
}
