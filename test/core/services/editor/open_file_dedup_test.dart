import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

/// Reopening a file must focus the tab that already has it, in whichever
/// group that tab lives.
void main() {
  late File file;

  setUp(() {
    file = File(
      '${Directory.systemTemp.path}/pyrite_open_dedup_${DateTime.now().microsecondsSinceEpoch}.py',
    )..writeAsStringSync('print(1)\n');
  });

  tearDown(() {
    if (file.existsSync()) file.deleteSync();
  });

  testWidgets('reopening focuses the open tab instead of duplicating it', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox.expand())),
      ),
    );
    final context = tester.element(find.byType(Scaffold));

    // Split first, then put the file's tab in the *second* group: the primary
    // group is the one the old duplicate check searched, so a tab parked in a
    // split group used to open the same file a second time.
    final primary = container.read(tabbedViewControllerProvider);
    final other = TabData(text: 'other');
    primary.addTab(other);
    container
        .read(editorLayoutProvider.notifier)
        .splitGroup(
          from: primary,
          target: primary,
          tab: other,
          where: EditorSplit.right,
        );
    final second = allEditorControllers(container)[1];
    final fileTab = TabData(
      text: file.uri.pathSegments.last,
      value: TabDataValue(type: 'file', filePath: file.path),
    );
    second.addTab(fileTab);

    await container
        .read(tabbedViewControllerProvider.notifier)
        .openFile(context, file: file);

    // Exactly one tab for that file across every group.
    final matches = allEditorControllers(container)
        .expand((controller) => controller.tabs)
        .where((tab) => editorTabValueOf(tab)?.filePath == file.path)
        .length;
    expect(matches, 1);

    // ...and it is the one the user is now looking at.
    expect(second.selectedTab, same(fileTab));
    expect(container.read(focusedEditorGroupProvider), same(second));
    expect(primary.selectedTab, isNot(same(fileTab)));
  });

  testWidgets('reopening a file whose own tab was split out focuses it', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox.expand())),
      ),
    );
    final context = tester.element(find.byType(Scaffold));

    // The usual gesture: drag the file's tab onto an edge, then open the same
    // file again from the tree. The split group holds the very tab that left
    // the primary, so the tab's stored index must have followed it.
    final primary = container.read(tabbedViewControllerProvider);
    final fileTab = TabData(
      text: file.uri.pathSegments.last,
      value: TabDataValue(type: 'file', filePath: file.path),
    );
    primary.addTab(fileTab);
    container
        .read(editorLayoutProvider.notifier)
        .splitGroup(
          from: primary,
          target: primary,
          tab: fileTab,
          where: EditorSplit.right,
        );
    final split = allEditorControllers(container)[1];
    split.addTab(TabData(text: 'other'));
    split.selectedIndex = 1;

    await container
        .read(tabbedViewControllerProvider.notifier)
        .openFile(context, file: file);

    expect(split.selectedTab, same(fileTab));
    expect(container.read(focusedEditorGroupProvider), same(split));
  });
}
