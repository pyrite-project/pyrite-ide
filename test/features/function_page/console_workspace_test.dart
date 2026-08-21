import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/features/function_page.dart';

const _workspaceKey = ValueKey<String>('test-console-workspace');
const _primaryContentKey = ValueKey<String>('test-primary-content');
const _consoleContentKey = ValueKey<String>('test-console-content');

void main() {
  testWidgets('dragging console to the top hides the editor content', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpWorkspace(tester, container);

    await _dragHandle(tester, -600);

    expect(
      tester.getSize(find.byKey(_primaryContentKey)).height,
      closeTo(44, 0.01),
    );
    expect(
      tester.getRect(find.byKey(_consoleContentKey)).bottom,
      closeTo(tester.getRect(find.byKey(_workspaceKey)).bottom, 0.01),
    );
    expect(find.bySemanticsLabel('调整底部面板大小'), findsOneWidget);
  });

  testWidgets('dragging a maximized console down restores the editor', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpWorkspace(tester, container);
    await _dragHandle(tester, -600);

    await _dragHandle(tester, 180);

    expect(
      tester.getSize(find.byKey(_primaryContentKey)).height,
      greaterThan(44),
    );
  });

  testWidgets('hiding a maximized console restores the primary pane', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpWorkspace(tester, container);
    await _dragHandle(tester, -600);

    container.read(consolePageShow.notifier).state = false;
    await tester.pump();

    expect(find.byKey(_consoleContentKey), findsNothing);
    expect(
      tester.getRect(find.byKey(_primaryContentKey)),
      tester.getRect(find.byKey(_workspaceKey)),
    );

    container.read(consolePageShow.notifier).state = true;
    await tester.pump();

    expect(find.byKey(_consoleContentKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(_primaryContentKey)).height,
      greaterThan(240),
    );
  });
}

Future<void> _pumpWorkspace(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => buildShadcnLayer(
              context,
              const SizedBox.expand(
                key: _workspaceKey,
                child: ConsoleWorkspace(
                  collapsedPrimarySize: 44,
                  primary: ColoredBox(
                    key: _primaryContentKey,
                    color: Colors.blue,
                  ),
                  console: ColoredBox(
                    key: _consoleContentKey,
                    color: Colors.green,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _dragHandle(WidgetTester tester, double delta) async {
  final handle = find.byKey(ConsoleWorkspace.draggerKey);
  final gesture = await tester.startGesture(
    tester.getCenter(handle),
    kind: PointerDeviceKind.mouse,
    buttons: kPrimaryButton,
  );
  const steps = 12;
  for (var index = 0; index < steps; index++) {
    await gesture.moveBy(Offset(0, delta / steps));
  }
  await gesture.up();
  await tester.pump();
}
