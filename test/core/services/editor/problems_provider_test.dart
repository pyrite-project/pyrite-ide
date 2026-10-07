import 'package:code_forge/code_forge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/problems_provider.dart';

LspErrors diagnostic(int severity) =>
    LspErrors(severity: severity, message: 'm', range: const {});

FileProblems file(String path, List<int> severities) => FileProblems(
  path: path,
  diagnostics: [for (final severity in severities) diagnostic(severity)],
);

void main() {
  group('problemCountsFor', () {
    test('counts errors and warnings separately', () {
      final counts = problemCountsFor([
        file('a.py', [1, 1, 2]),
      ], 'a.py');
      expect(counts.errors, 2);
      expect(counts.warnings, 1);
    });

    test('ignores information and hint severities', () {
      // The badge is about things to fix; a "hint" would light up every tab.
      final counts = problemCountsFor([
        file('a.py', [3, 4]),
      ], 'a.py');
      expect(counts.errors, 0);
      expect(counts.warnings, 0);
    });

    test('a path with no entry counts as nothing', () {
      expect(
        problemCountsFor([
          file('a.py', [1]),
        ], 'b.py'),
        (errors: 0, warnings: 0),
      );
    });

    test('an empty workspace counts as nothing', () {
      expect(problemCountsFor(const [], 'a.py'), (errors: 0, warnings: 0));
    });

    test('picks the requested file out of several', () {
      final counts = problemCountsFor([
        file('a.py', [1]),
        file('b.py', [2, 2, 2]),
      ], 'b.py');
      expect(counts.errors, 0);
      expect(counts.warnings, 3);
    });

    test('a file with no diagnostics reports no badge', () {
      expect(problemCountsFor([file('a.py', const [])], 'a.py'), (
        errors: 0,
        warnings: 0,
      ));
    });
  });
}
