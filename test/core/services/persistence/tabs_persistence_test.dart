import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/persistence/editor/tabs_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';

void main() {
  test('persisted tab round-trips fold ranges and scroll line', () {
    final tab = PersistedTab(
      filePath: r'C:\project\main.py',
      isSaved: false,
      unsavedContent: 'print("hi")',
      cursorOffset: 42,
      scrollLine: 17,
      foldedRanges: const [
        PersistedFoldRange(
          startLine: 2,
          endLine: 20,
          children: [
            PersistedFoldRange(startLine: 5, endLine: 9),
            PersistedFoldRange(
              startLine: 11,
              endLine: 15,
              children: [PersistedFoldRange(startLine: 12, endLine: 13)],
            ),
          ],
        ),
        PersistedFoldRange(startLine: 30, endLine: 34),
      ],
    );

    final restored = PersistedTab.fromJson(
      jsonDecode(jsonEncode(tab.toJson())) as Map<String, dynamic>,
    );

    expect(restored.filePath, r'C:\project\main.py');
    expect(restored.isSaved, isFalse);
    expect(restored.unsavedContent, 'print("hi")');
    expect(restored.cursorOffset, 42);
    expect(restored.scrollLine, 17);
    expect(restored.foldedRanges.length, 2);
    expect(restored.foldedRanges[0].startLine, 2);
    expect(restored.foldedRanges[0].endLine, 20);
    expect(restored.foldedRanges[0].children.length, 2);
    expect(restored.foldedRanges[0].children[1].children.single.startLine, 12);
    expect(restored.foldedRanges[1].startLine, 30);
    expect(restored.foldedRanges[1].children, isEmpty);
  });

  test('persisted tab accepts sessions written before the new fields', () {
    final legacy = PersistedTab.fromJson({
      'filePath': '/tmp/old.py',
      'cursorOffset': 7,
    });

    expect(legacy.scrollLine, isNull);
    expect(legacy.foldedRanges, isEmpty);
  });

  test(
    'persisted fold range defaults missing keys and drops junk children',
    () {
      final range = PersistedFoldRange.fromJson({
        'children': [<String, dynamic>{}, 'junk'],
      });

      expect(range.startLine, 0);
      expect(range.endLine, 0);
      // Non-map children are dropped; an empty map parses to the defaulted
      // range, which folds nothing.
      expect(range.children.length, 1);
      expect(range.children.single.startLine, 0);
    },
  );

  test('tabs persisted data round-trips with the selection path', () {
    final data = TabsPersistedData(
      tabs: [
        PersistedTab(
          filePath: '/w/a.py',
          scrollLine: 3,
          foldedRanges: const [PersistedFoldRange(startLine: 1, endLine: 2)],
        ),
        PersistedTab(filePath: '/w/b.py'),
      ],
      selectedTabIndex: 2,
      selectedTabPath: '/w/b.py',
    );

    final restored = TabsPersistedData.fromJson(
      jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
    );

    expect(restored.tabs.map((t) => t.filePath), ['/w/a.py', '/w/b.py']);
    expect(restored.tabs.first.scrollLine, 3);
    expect(restored.tabs.first.foldedRanges.single.endLine, 2);
    expect(restored.selectedTabIndex, 2);
    expect(restored.selectedTabPath, '/w/b.py');
  });
}
