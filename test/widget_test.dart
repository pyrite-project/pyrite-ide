import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/app/app.dart';

void main() {
  testWidgets('Pyrite IDE starts on the editor welcome page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: PyriteIDE()));
    await tester.pumpAndSettle();

    expect(find.text('一个更轻量、清晰的 MicroPython 工作台'), findsOneWidget);
    expect(find.text('打开项目文件夹'), findsOneWidget);
    expect(find.text('连接设备'), findsOneWidget);
  });
}
