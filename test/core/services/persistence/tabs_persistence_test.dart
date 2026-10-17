import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/persistence/editor/tabs_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';

void main() {
  test('a split layout round-trips through json', () {
    final data = TabsPersistedData(
      tabs: [
        PersistedTab(filePath: '/a.py', isSaved: true),
        PersistedTab(filePath: '/b.py', isSaved: false),
      ],
      selectedTabIndex: 1,
      selectedTabPath: '/b.py',
      groups: [
        PersistedEditorGroup(
          tabs: [PersistedTab(filePath: '/a.py', isSaved: true)],
          selectedTabPath: '/a.py',
        ),
        PersistedEditorGroup(
          tabs: [PersistedTab(filePath: '/b.py', isSaved: false)],
          selectedTabPath: '/b.py',
        ),
      ],
      layout: PersistedEditorLayout.split('horizontal', [
        PersistedEditorLayout.group(0),
        PersistedEditorLayout.split('vertical', [
          PersistedEditorLayout.group(1),
          PersistedEditorLayout.group(0),
        ]),
      ]),
      primaryGroupIndex: 1,
    );

    final restored = TabsPersistedData.fromJson(
      jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
    );

    expect(restored.primaryGroupIndex, 1);
    expect(restored.groups, hasLength(2));
    expect(restored.groups[1].tabs.single.filePath, '/b.py');
    expect(restored.groups[1].tabs.single.isSaved, isFalse);
    expect(restored.selectedTabPath, '/b.py');
    expect(restored.layout, isNotNull);
    expect(restored.layout!.axis, 'horizontal');
    expect(restored.layout!.children, hasLength(2));
    expect(restored.layout!.children[1].axis, 'vertical');
    expect(restored.layout!.children[1].children, hasLength(2));
    // The nested group points back at group 0, which is preserved verbatim.
    expect(restored.layout!.children[1].children[1].groupIndex, 0);
  });

  test('tabs without a layout restore as a single group', () {
    final data = TabsPersistedData(
      tabs: [PersistedTab(filePath: '/a.py', isSaved: true)],
      selectedTabIndex: 0,
    );

    final restored = TabsPersistedData.fromJson(
      jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
    );

    expect(restored.groups, isEmpty);
    expect(restored.layout, isNull);
    expect(restored.primaryGroupIndex, 0);
  });

  test('a group leaf is written without an empty child list', () {
    expect(PersistedEditorLayout.group(2).toJson(), {'groupIndex': 2});
  });

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
    expect(restored.foldedRanges, hasLength(2));
    final first = restored.foldedRanges.first;
    expect(first.startLine, 2);
    expect(first.endLine, 20);
    expect(first.children, hasLength(2));
    expect(first.children.last.children.single.startLine, 12);
  });
}
