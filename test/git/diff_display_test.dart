import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/git/diff_display.dart';

void main() {
  test('buildGitDiffDisplay hides git headers and hunk markers', () {
    const patch = '''
diff --git a/README.zh-CN.md b/README.zh-CN.md
index 99ecb6b..47b6367 100644
--- a/README.zh-CN.md
+++ b/README.zh-CN.md
@@ -10,7 +10,7 @@
 context
-old line
+new line
''';

    final display = buildGitDiffDisplay(patch);

    expect(display.text, 'context\nnew line');
    expect(display.removedRanges, [(afterLine: 0, content: 'old line')]);
    expect(display.addedRanges, [(1, 1)]);
  });

  test('buildGitDiffDisplay keeps content lines that look like headers', () {
    const patch = '''
diff --git a/options.txt b/options.txt
index 1111111..2222222 100644
--- a/options.txt
+++ b/options.txt
@@ -1,2 +1,2 @@
--- old option
+++ new option
''';

    final display = buildGitDiffDisplay(patch);

    expect(display.text, '++ new option');
    expect(display.removedRanges, [(afterLine: -1, content: '-- old option')]);
    expect(display.addedRanges, [(0, 0)]);
  });
}
