import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/shared/tabbed_view/tabbed_view.dart';
import 'package:tabbed_view/tabbed_view.dart' as tabbed;

/// 标签页本身（`tab_widget.dart`）会给可关闭的标签套一层
/// `PyriteContextMenuWidget`，后者是 `ConsumerWidget`，构建时要读
/// `useMaterialContextMenu`，所以整棵标签树必须在 ProviderScope 之内。
/// 真实应用里 `PyriteIDE` 在根部提供 scope；这个测试只声明它要验证的行为
/// （kept-alive 内容不以 GlobalKey 挂载），此前漏掉了 scope。
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
      ProviderScope(
        child: MaterialApp(
          home: Row(
            children: [
              Expanded(child: TabbedView(controller: sourceController)),
              Expanded(child: TabbedView(controller: targetController)),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('shared content'), findsNWidgets(2));
  });
}
