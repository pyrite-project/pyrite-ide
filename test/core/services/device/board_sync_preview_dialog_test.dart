import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/device/board_sync_plan.dart';
import 'package:pyrite_ide/core/services/device/board_sync_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BoardSyncPlan buildPlan() {
    final now = DateTime.now();
    return BoardSyncPlan(
      entries: [
        BoardSyncEntry(
          relativePath: 'new.py',
          action: BoardSyncAction.uploadNew,
          direction: BoardSyncDirection.localToBoard,
          local: SyncFileInfo(relativePath: 'new.py', size: 10, modified: now),
        ),
        BoardSyncEntry(
          relativePath: 'other.py',
          action: BoardSyncAction.downloadNew,
          direction: BoardSyncDirection.boardToLocal,
          board: SyncFileInfo(
            relativePath: 'other.py',
            size: 20,
            modified: now,
          ),
        ),
        BoardSyncEntry(
          relativePath: 'same.py',
          action: BoardSyncAction.unchanged,
          direction: BoardSyncDirection.none,
          local: SyncFileInfo(relativePath: 'same.py', size: 1, modified: now),
          board: SyncFileInfo(relativePath: 'same.py', size: 1, modified: now),
        ),
      ],
      localRoot: '/workspace',
    );
  }

  Future<BoardSyncPreviewResult?> pumpAndConfirm(
    WidgetTester tester, {
    String buttonLabel = '同步',
  }) async {
    BoardSyncPreviewResult? captured;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await showBoardSyncPreviewDialog(
                  context,
                  plan: buildPlan(),
                  localRoot: '/workspace',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('同步本地工作区到设备'), findsOneWidget);
    expect(find.text('new.py'), findsOneWidget);
    expect(find.text('other.py'), findsOneWidget);
    expect(find.text('same.py'), findsOneWidget);

    await tester.tap(find.textContaining(buttonLabel).last);
    await tester.pumpAndSettle();
    return captured;
  }

  testWidgets('preview defaults to every actionable row', (tester) async {
    final result = await pumpAndConfirm(tester, buttonLabel: '同步');

    expect(result, isNotNull);
    expect(result!.selectedPaths, {'new.py', 'other.py'});
    expect(result.direction, BoardSyncDirection.none);
  });

  testWidgets('dismissing the preview returns null and starts nothing', (
    tester,
  ) async {
    BoardSyncPreviewResult? captured;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await showBoardSyncPreviewDialog(
                  context,
                  plan: buildPlan(),
                  localRoot: '/workspace',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(captured, isNull);
  });

  testWidgets('local-only direction hides the board-only row', (tester) async {
    BoardSyncPreviewResult? captured;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await showBoardSyncPreviewDialog(
                  context,
                  plan: buildPlan(),
                  localRoot: '/workspace',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅本地 → 设备'));
    await tester.pumpAndSettle();

    expect(find.text('new.py'), findsOneWidget);
    expect(find.text('other.py'), findsNothing);

    await tester.tap(find.textContaining('同步').last);
    await tester.pumpAndSettle();

    expect(captured!.direction, BoardSyncDirection.localToBoard);
    expect(captured!.selectedPaths, {'new.py'});
  });

  // -------------------------------------------------------------------------
  // .pyrsyncignore
  // -------------------------------------------------------------------------

  BoardSyncPlan buildPlanWithIgnored() {
    final now = DateTime.now();
    return BoardSyncPlan(
      entries: [
        BoardSyncEntry(
          relativePath: '.pyrsyncignore',
          action: BoardSyncAction.uploadNew,
          direction: BoardSyncDirection.localToBoard,
          local: SyncFileInfo(
            relativePath: '.pyrsyncignore',
            size: 8,
            modified: now,
          ),
          ignoredByDefault: true,
        ),
        BoardSyncEntry(
          relativePath: 'main.py',
          action: BoardSyncAction.uploadNew,
          direction: BoardSyncDirection.localToBoard,
          local: SyncFileInfo(relativePath: 'main.py', size: 10, modified: now),
        ),
        BoardSyncEntry(
          relativePath: 'vendor/lib.py',
          action: BoardSyncAction.uploadNew,
          direction: BoardSyncDirection.localToBoard,
          local: SyncFileInfo(
            relativePath: 'vendor/lib.py',
            size: 20,
            modified: now,
          ),
          ignoredByDefault: true,
        ),
      ],
      localRoot: '/workspace',
    );
  }

  Future<void> openIgnoredPlan(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showBoardSyncPreviewDialog(
                  context,
                  plan: buildPlanWithIgnored(),
                  localRoot: '/workspace',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('ignored rows start unticked and folded into one group', (
    tester,
  ) async {
    BoardSyncPreviewResult? captured;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await showBoardSyncPreviewDialog(
                  context,
                  plan: buildPlanWithIgnored(),
                  localRoot: '/workspace',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('已按 .pyrsyncignore 忽略 2 项'), findsOneWidget);
    expect(find.text('main.py'), findsOneWidget);
    // Folded: the ignored paths are not rendered as rows yet.
    expect(find.text('vendor/lib.py'), findsNothing);
    expect(find.text('.pyrsyncignore'), findsNothing);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(captured!.selectedPaths, {'main.py'});
  });

  testWidgets('expanding the group shows its rows unticked', (tester) async {
    await openIgnoredPlan(tester);

    await tester.tap(find.text('已按 .pyrsyncignore 忽略 2 项'));
    await tester.pumpAndSettle();

    expect(find.text('.pyrsyncignore'), findsOneWidget);

    // The dialog only builds the rows that fit its viewport, so the last row has
    // to be scrolled into view before it exists in the tree.
    await tester.scrollUntilVisible(
      find.text('vendor/lib.py'),
      80,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    final row = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text('vendor/lib.py'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(row.value, isFalse);
  });

  testWidgets('the group checkbox ticks every ignored row', (tester) async {
    BoardSyncPreviewResult? captured;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await showBoardSyncPreviewDialog(
                  context,
                  plan: buildPlanWithIgnored(),
                  localRoot: '/workspace',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final groupTile = find.ancestor(
      of: find.text('已按 .pyrsyncignore 忽略 2 项'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: groupTile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(captured!.selectedPaths, {
      'main.py',
      '.pyrsyncignore',
      'vendor/lib.py',
    });
  });

  testWidgets('select all does not reach into the ignored group', (
    tester,
  ) async {
    BoardSyncPreviewResult? captured;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await showBoardSyncPreviewDialog(
                  context,
                  plan: buildPlanWithIgnored(),
                  localRoot: '/workspace',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Clear, then select again: only the rows listed one by one come back.
    await tester.tap(find.text('全选/全不选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选/全不选'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(captured!.selectedPaths, {'main.py'});
  });
}
