import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/file/diff_info.dart';

void main() {
  test('computeDiff reports inserted ranges', () {
    final diff = computeDiff('a\nb\nc', 'a\nx\nb\nc\ny');

    expect(diff.addCount, 2);
    expect(diff.removeCount, 0);
    expect(diff.addedRanges, [(1, 1), (4, 4)]);
    expect(diff.removedRanges, isEmpty);
    expect(diff.unifiedLines, [' a', '+x', ' b', ' c', '+y']);
  });

  test('computeDiff reports replacements as removals before additions', () {
    final diff = computeDiff('one\nold\ntail', 'one\nnew\ntail');

    expect(diff.addCount, 1);
    expect(diff.removeCount, 1);
    expect(diff.addedRanges, [(1, 1)]);
    expect(diff.removedRanges, [(afterLine: 0, content: 'old')]);
    expect(diff.unifiedLines, [' one', '-old', '+new', ' tail']);
  });

  test('computeDiff anchors leading deletions before the first new line', () {
    final diff = computeDiff('drop\nkeep', 'keep');

    expect(diff.addCount, 0);
    expect(diff.removeCount, 1);
    expect(diff.addedRanges, isEmpty);
    expect(diff.removedRanges, [(afterLine: -1, content: 'drop')]);
    expect(diff.unifiedLines, ['-drop', ' keep']);
  });

  test('computeDiff handles long files without changing range semantics', () {
    final oldLines = List.generate(300, (index) => 'line $index');
    final newLines = [...oldLines];
    newLines[120] = 'changed 120';
    newLines.insert(250, 'inserted 250');

    final diff = computeDiff(oldLines.join('\n'), newLines.join('\n'));

    expect(diff.addCount, 2);
    expect(diff.removeCount, 1);
    expect(diff.addedRanges, [(120, 120), (250, 250)]);
    expect(diff.removedRanges, [(afterLine: 119, content: 'line 120')]);
  });
}
