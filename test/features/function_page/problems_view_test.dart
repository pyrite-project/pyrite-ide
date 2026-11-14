import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/problems_provider.dart';
import 'package:pyrite_ide/features/function_page/problems_view.dart';

/// The panel lists errors and warnings only. Diagnostics it will never draw
/// must not count as content either: a file whose entries are all info or
/// hints leaves the panel with nothing to show, so it has to fall back to the
/// same empty state as a workspace with no diagnostics at all.
void main() {
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

  testWidgets('errors stay listed and unlisted severities stay out of the '
      'rows', (tester) async {
    await tester.pumpWidget(
      host([
        FileProblems(
          path: '/workspace/main.py',
          diagnostics: [diagnostic(4, 'hint row'), diagnostic(1, 'error row')],
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
  });
}

class _FixedProblemsNotifier extends ProblemsNotifier {
  _FixedProblemsNotifier(super.ref, List<FileProblems> problems) {
    state = problems;
  }
}
