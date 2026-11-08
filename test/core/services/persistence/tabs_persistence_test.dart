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

  test('outline tabs round-trip with their strip positions', () {
    final data = TabsPersistedData(
      tabs: [
        PersistedTab(filePath: '/w/a.py'),
        // An outline dragged between two file tabs keeps that spot.
        PersistedTab(filePath: '', isOutline: true),
        PersistedTab(filePath: '/w/b.py'),
      ],
      selectedTabIndex: 1,
    );

    final restored = TabsPersistedData.fromJson(
      jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
    );

    expect(restored.tabs[1].isOutline, isTrue);
    expect(restored.tabs.where((t) => t.isOutline), hasLength(1));
    expect(restored.tabs[0].isOutline, isFalse);
  });

  test('sessions written before the outline fields restore without them', () {
    final restored = TabsPersistedData.fromJson({
      'tabs': [
        {'filePath': '/w/old.py'},
      ],
      'selectedTabIndex': 0,
    });

    expect(restored.tabs.single.isOutline, isFalse);
  });

  test('one malformed tab entry does not discard the whole session', () {
    // tabs.json also holds every unsaved buffer, and a parse error makes the
    // loader return no session at all, so a single bad entry must not throw.
    final restored = TabsPersistedData.fromJson({
      'tabs': [
        {'filePath': '/w/a.py'},
        'junk',
        {'noFilePath': true},
        {'filePath': '', 'isOutline': true},
        {'filePath': '/w/b.py'},
      ],
      'selectedTabIndex': 0,
    });

    expect(restored.tabs.map((tab) => tab.filePath), [
      '/w/a.py',
      '',
      '/w/b.py',
    ]);
    expect(restored.tabs[1].isOutline, isTrue);
  });

  test('a malformed entry inside a group is skipped too', () {
    final restored = TabsPersistedData.fromJson({
      'tabs': const [],
      'selectedTabIndex': 0,
      'groups': [
        {
          'tabs': [
            {'filePath': '/w/a.py'},
            42,
          ],
          'selectedTabPath': '/w/a.py',
        },
      ],
      'layout': {'axis': 'horizontal', 'children': [{'groupIndex': 0}]},
    });

    expect(restored.groups.single.tabs.single.filePath, '/w/a.py');
  });
}
