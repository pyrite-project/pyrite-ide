import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/problems_provider.dart';
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

  // The provider-backed host pins the diagnostics the panel reads, so the
  // severity filtering can be exercised without an editor behind it.
  Widget host(List<FileProblems> problems) {
    return ProviderScope(
      overrides: [
        problemsProvider.overrideWith(
          (ref) => _FixedProblemsNotifier(ref, problems),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: ProblemsView())),
    );
  }

  LspErrors diagnostic(int severity, String message, {int line = 0}) {
    return LspErrors(
      severity: severity,
      range: {
        'start': {'line': line, 'character': 0},
        'end': {'line': line, 'character': 1},
      },
      message: message,
    );
  }

  final emptyState = find.byIcon(Icons.check_circle_outline);

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

    expect(
      find.text('Cannot resolve imported module `micropython`'),
      findsOneWidget,
    );
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

    expect(
      find.text('Cannot resolve imported module `micropython`'),
      findsOneWidget,
    );
  });

  // The panel lists errors and warnings only. Diagnostics it will never draw
  // must not count as content either: a file whose entries are all info or
  // hints leaves the panel with nothing to show, so it has to fall back to
  // the same empty state as a workspace with no diagnostics at all.
  testWidgets('hint-only diagnostics show the empty state', (tester) async {
    await tester.pumpWidget(
      host([
        FileProblems(
          path: '/workspace/main.py',
          diagnostics: [diagnostic(4, 'consider a docstring')],
        ),
      ]),
    );

    expect(emptyState, findsOneWidget);
    expect(find.text('consider a docstring'), findsNothing);
  });

  testWidgets('info-only diagnostics show the empty state', (tester) async {
    await tester.pumpWidget(
      host([
        FileProblems(
          path: '/workspace/main.py',
          diagnostics: [diagnostic(3, 'unused import')],
        ),
      ]),
    );

    expect(emptyState, findsOneWidget);
    expect(find.text('unused import'), findsNothing);
  });

  testWidgets(
    'errors stay listed and unlisted severities stay out of the rows',
    (tester) async {
      await tester.pumpWidget(
        host([
          FileProblems(
            path: '/workspace/main.py',
            diagnostics: [
              diagnostic(4, 'hint row'),
              diagnostic(1, 'error row'),
            ],
          ),
        ]),
      );

      expect(emptyState, findsNothing);
      expect(find.text('error row'), findsOneWidget);
      expect(
        find.text('hint row'),
        findsNothing,
        reason: 'the empty-state filter and the row filter agree on severity',
      );
    },
  );
}

class _FixedProblemsNotifier extends ProblemsNotifier {
  _FixedProblemsNotifier(super.ref, List<FileProblems> problems) {
    state = problems;
  }
}
