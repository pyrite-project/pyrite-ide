import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/features/function_page/problems_view.dart';

LspErrors errorAt(String message, {int line = 2}) => LspErrors(
  severity: 1,
  message: message,
  range: {
    'start': {'line': line, 'character': 0},
    'end': {'line': line, 'character': 5},
  },
);

void main() {
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // Rust runtime unavailable: the tests below cannot run.
    }
  });

  // The panel mirrors each open editor's diagnostics notifier, so the test
  // drives it through a controller registered in the editor map.
  Future<void> pumpPanel(
    WidgetTester tester,
    CodeForgeController controller,
    String path,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(editorControllerMapProvider.notifier).state = {
      path: controller,
    };
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 800, height: 240, child: ProblemsView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a multi-line message renders only its first non-empty line', (
    tester,
  ) async {
    final controller = CodeForgeController();
    addTearDown(controller.dispose);
    controller.diagnosticsNotifier.value = [
      errorAt(
        'Cannot resolve imported module `micropython`\n\n'
        'Unresolved attribute `native` on type `ModuleType`',
      ),
    ];
    await pumpPanel(tester, controller, 'a.py');

    expect(find.text('Cannot resolve imported module `micropython`'),
        findsOneWidget);
    expect(find.textContaining('Unresolved attribute'), findsNothing);
  });

  testWidgets('leading blank lines are skipped', (tester) async {
    final controller = CodeForgeController();
    addTearDown(controller.dispose);
    controller.diagnosticsNotifier.value = [
      errorAt('\n\r\n  actual first line  \nsecond line'),
    ];
    await pumpPanel(tester, controller, 'a.py');

    expect(find.text('actual first line'), findsOneWidget);
    expect(find.textContaining('second line'), findsNothing);
  });

  testWidgets('a single-line message is shown unchanged', (tester) async {
    final controller = CodeForgeController();
    addTearDown(controller.dispose);
    controller.diagnosticsNotifier.value = [
      errorAt('Cannot resolve imported module `micropython`'),
    ];
    await pumpPanel(tester, controller, 'a.py');

    expect(find.text('Cannot resolve imported module `micropython`'),
        findsOneWidget);
  });
}
