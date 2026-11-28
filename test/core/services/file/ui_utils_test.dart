import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';

/// `showFileConflictDialog` 的对话框内容和按钮文案都取自插件贡献的 i18n
/// 数据（`UseText` / `translateForWidget` 依赖 `dataRegistryProvider`），
/// 所以它只能在 ProviderScope 之内构建。真实应用里 `PyriteIDE` 自带 scope；
/// 这两个测试此前只 pump 了 `MaterialApp`，于是对话框一构建就抛
/// "No ProviderScope found"。这里补上 scope 让测试环境与生产调用环境一致，
/// 而不是改生产代码去吞掉缺少 scope 的错误。
void main() {
  Future<void> pumpDialogHost(
    WidgetTester tester,
    Future<void> Function(BuildContext context) onOpen,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => onOpen(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('conflict dialog can return show diff action', (tester) async {
    FileConflictAction? action;

    await pumpDialogHost(tester, (context) async {
      action = await showFileConflictDialog(
        context,
        sourcePath: '/local/main.py',
        targetPath: '/board/main.py',
        isUpload: true,
        canShowDiff: true,
      );
    });

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
    await pumpDialogHost(
      tester,
      (context) => showFileConflictDialog(
        context,
        sourcePath: '/local/main.py',
        targetPath: '/board/main.py',
        isUpload: true,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('展示差异'), findsNothing);
  });
}
