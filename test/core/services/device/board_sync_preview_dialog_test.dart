import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/device/board_sync_plan.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';
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

  group('FileTransferProgressBar', () {
    Widget host(Widget child) => ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    );

    testWidgets('shows a cancel button while a transfer is running', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(fileTransferProgressProvider.notifier)
          .start(
            direction: FileTransferDirection.upload,
            scope: FileTransferScope.folder,
            totalFiles: 3,
            message: '上传中',
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: FileTransferProgressBar()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('取消'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pump();

      expect(
        container.read(fileTransferProgressProvider).cancelRequested,
        isTrue,
      );
      expect(find.text('取消中…'), findsOneWidget);
      expect(find.text('取消'), findsNothing);
    });

    testWidgets('renders nothing when idle', (tester) async {
      await tester.pumpWidget(host(const FileTransferProgressBar()));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('取消'), findsNothing);
    });
  });
}
