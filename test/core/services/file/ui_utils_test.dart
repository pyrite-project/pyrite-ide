import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/file/ui_utils.dart';

void main() {
  testWidgets('conflict dialog can return show diff action', (tester) async {
    FileConflictAction? action;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              action = await showFileConflictDialog(
                context,
                sourcePath: '/local/main.py',
                targetPath: '/board/main.py',
                isUpload: true,
                canShowDiff: true,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('展示差异'), findsOneWidget);

    await tester.tap(find.text('展示差异'));
    await tester.pumpAndSettle();

    expect(action, FileConflictAction.showDiff);
  });

  testWidgets('conflict dialog hides show diff action by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFileConflictDialog(
              context,
              sourcePath: '/local/main.py',
              targetPath: '/board/main.py',
              isUpload: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('展示差异'), findsNothing);
  });
}
